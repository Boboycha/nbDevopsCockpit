unit Terminal.LocalPTY;

interface

uses System.SysUtils, System.Classes;

type
  { Internal OS resource owner. Read/Write run on different workers. }
  TLocalPTY = class
  private
    {$IFDEF MSWINDOWS}
    FConsole: THandle;
    FInput, FOutput, FProcess, FJob: THandle;
    FPendingSize, FResizeError: Integer;
    {$ELSE}
    FMaster, FPid: Integer;
    {$ENDIF}
    FExitCode: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const Executable: string; const Arguments: TArray<string>;
      const Directory: string; Cols, Rows: Integer);
    function Read(var Bytes: TBytes): Integer;
    function Write(const Bytes: TBytes; Offset: Integer): Integer;
    procedure Resize(Cols, Rows: Integer);
    procedure Terminate;
    procedure CancelWriter(Worker: TThread);
    procedure CloseTerminal;
    function ExitCode: Integer;
    function ProcessExited: Boolean;
    procedure FinishRead;
  end;

implementation

{$IFDEF MSWINDOWS}
uses Winapi.Windows, System.SyncObjs;

type
  TCreatePseudoConsole = function(Size: TCoord; Input, Output: THandle;
    Flags: DWORD; out Console: THandle): HRESULT; stdcall;
  TResizePseudoConsole = function(Console: THandle; Size: TCoord): HRESULT; stdcall;
  TClosePseudoConsole = procedure(Console: THandle); stdcall;
  TLocalStartupInfoEx = record
    StartupInfo: TStartupInfo;
    AttributeList: PProcThreadAttributeList;
  end;

{ Use a pointer to the full extended record. Delphi's const TStartupInfo
  declaration can copy only the base record when marshalling a Win64 call. }
function CreatePTYProcess(ApplicationName, CommandLine: PWideChar;
  ProcessAttributes, ThreadAttributes: Pointer; InheritHandles: BOOL;
  Flags: DWORD; Environment: Pointer; Directory: PWideChar;
  Startup: Pointer; out ProcessInfo: TProcessInformation): BOOL; stdcall;
  external 'kernel32.dll' name 'CreateProcessW';

procedure CloseHandleVar(var Handle: THandle);
begin
  if Handle <> 0 then CloseHandle(Handle);
  Handle := 0;
end;

function QuoteArgument(const Value: string): string;
var
  C: Char;
  Slashes: Integer;
begin
  Result := '"';
  Slashes := 0;
  for C in Value do
  begin
    if C = '\' then Inc(Slashes)
    else
    begin
      if C = '"' then
        Result := Result + StringOfChar('\', Slashes * 2 + 1) + C
      else
        Result := Result + StringOfChar('\', Slashes) + C;
      Slashes := 0;
    end;
  end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

constructor TLocalPTY.Create;
begin
  inherited;
  FExitCode := -1;
end;

procedure TLocalPTY.Start(const Executable: string;
  const Arguments: TArray<string>; const Directory: string; Cols, Rows: Integer);
var
  CreateConsole: TCreatePseudoConsole;
  InputRead, OutputWrite: THandle;
  Size: TCoord;
  Startup: TLocalStartupInfoEx;
  ProcessInfo: TProcessInformation;
  AttrSize: NativeUInt;
  JobInfo: TJobObjectExtendedLimitInformation;
  CommandLine, Shell, Arg: string;
  WorkDir: PChar;
  HR: HRESULT;
  AttrInitialized: Boolean;
  SystemDir: array[0..MAX_PATH] of Char;
begin
  @CreateConsole := GetProcAddress(GetModuleHandle('kernel32.dll'), 'CreatePseudoConsole');
  if not Assigned(CreateConsole) then
    raise ENotSupportedException.Create('Local terminal requires Windows 10 1809 or newer');
  InputRead := 0;
  OutputWrite := 0;
  AttrInitialized := False;
  FillChar(Startup, SizeOf(Startup), 0);
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
  try
    Win32Check(CreatePipe(InputRead, FInput, nil, 0));
    Win32Check(CreatePipe(FOutput, OutputWrite, nil, 0));
    Size.X := Cols;
    Size.Y := Rows;
    HR := CreateConsole(Size, InputRead, OutputWrite, 0, FConsole);
    if HR < 0 then raise EOSError.CreateFmt('CreatePseudoConsole failed: %.8x', [Cardinal(HR)]);
    AttrSize := 0;
    InitializeProcThreadAttributeList(nil, 1, 0, AttrSize);
    GetMem(Startup.AttributeList, AttrSize);
    Win32Check(InitializeProcThreadAttributeList(Startup.AttributeList, 1, 0, AttrSize));
    AttrInitialized := True;
    Win32Check(UpdateProcThreadAttribute(Startup.AttributeList, 0, $00020016,
      Pointer(FConsole), SizeOf(FConsole), nil, PNativeUInt(nil)^));
    Startup.StartupInfo.cb := SizeOf(Startup);
    { Null standard handles let ConPTY supply its console handles instead of
      inheriting redirected standard streams from a console host/test runner. }
    Startup.StartupInfo.dwFlags := STARTF_USESTDHANDLES;
    Shell := Executable;
    if Shell = '' then
    begin
      if GetSystemDirectory(SystemDir, Length(SystemDir)) = 0 then RaiseLastOSError;
      Shell := IncludeTrailingPathDelimiter(string(SystemDir)) +
        'WindowsPowerShell\v1.0\powershell.exe';
    end;
    CommandLine := QuoteArgument(Shell);
    for Arg in Arguments do CommandLine := CommandLine + ' ' + QuoteArgument(Arg);
    UniqueString(CommandLine);
    WorkDir := nil;
    if Directory <> '' then WorkDir := PChar(Directory);
    FJob := CreateJobObject(nil, nil);
    Win32Check(FJob <> 0);
    FillChar(JobInfo, SizeOf(JobInfo), 0);
    JobInfo.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    Win32Check(SetInformationJobObject(FJob, JobObjectExtendedLimitInformation,
      @JobInfo, SizeOf(JobInfo)));
    Win32Check(CreatePTYProcess(nil, PChar(CommandLine), nil, nil, False,
      EXTENDED_STARTUPINFO_PRESENT or CREATE_UNICODE_ENVIRONMENT or CREATE_SUSPENDED,
      nil, WorkDir, @Startup, ProcessInfo));
    FProcess := ProcessInfo.hProcess;
    try
      Win32Check(AssignProcessToJobObject(FJob, FProcess));
      Win32Check(ResumeThread(ProcessInfo.hThread) <> DWORD(-1));
    except
      TerminateProcess(FProcess, 1);
      raise;
    end;
  finally
    CloseHandleVar(ProcessInfo.hThread);
    if AttrInitialized then DeleteProcThreadAttributeList(Startup.AttributeList);
    FreeMem(Startup.AttributeList);
    CloseHandleVar(InputRead);
    CloseHandleVar(OutputWrite);
  end;
end;

function TLocalPTY.Read(var Bytes: TBytes): Integer;
var
  Available, Count, Error: DWORD;
  ResizeError: Integer;
begin
  ResizeError := TInterlocked.CompareExchange(FResizeError, 0, 0);
  if ResizeError < 0 then
    raise EOSError.CreateFmt('ResizePseudoConsole failed: %.8x', [Cardinal(ResizeError)]);
  if not PeekNamedPipe(FOutput, nil, 0, nil, @Available, nil) then
  begin
    Error := GetLastError;
    if Error = ERROR_BROKEN_PIPE then Exit(-1);
    RaiseLastOSError(Error);
  end;
  if Available = 0 then
  begin
    Exit(0);
  end;
  if Available > DWORD(Length(Bytes)) then Available := Length(Bytes);
  if not ReadFile(FOutput, Bytes[0], Available, Count, nil) then
  begin
    Error := GetLastError;
    if Error = ERROR_BROKEN_PIPE then Exit(-1);
    RaiseLastOSError(Error);
  end;
  Result := Count;
end;

function TLocalPTY.Write(const Bytes: TBytes; Offset: Integer): Integer;
var
  Count, Error: DWORD;
begin
  if not WriteFile(FInput, Bytes[Offset], Length(Bytes) - Offset, Count, nil) then
  begin
    Error := GetLastError;
    if (Error = ERROR_BROKEN_PIPE) or (Error = ERROR_OPERATION_ABORTED) then Exit(-1);
    RaiseLastOSError(Error);
  end;
  Result := Count;
end;

procedure TLocalPTY.Resize(Cols, Rows: Integer);
begin
  // Serialize native resize and close on the monitor, never block the FMX UI.
  TInterlocked.Exchange(FPendingSize, Cols or (Rows shl 16));
end;

procedure TLocalPTY.Terminate;
begin
  if FProcess <> 0 then ExitCode;
  if FJob <> 0 then TerminateJobObject(FJob, 1);
end;

procedure TLocalPTY.CancelWriter(Worker: TThread);
begin
  CancelSynchronousIo(Worker.Handle);
end;

procedure TLocalPTY.CloseTerminal;
var
  CloseConsole: TClosePseudoConsole;
begin
  if FConsole = 0 then Exit;
  @CloseConsole := GetProcAddress(GetModuleHandle('kernel32.dll'), 'ClosePseudoConsole');
  CloseConsole(FConsole);
  FConsole := 0;
end;

function TLocalPTY.ExitCode: Integer;
var
  Code: DWORD;
begin
  if (FProcess <> 0) and GetExitCodeProcess(FProcess, Code) and
    (Code <> STILL_ACTIVE) then FExitCode := Integer(Code);
  Result := FExitCode;
end;

function TLocalPTY.ProcessExited: Boolean;
var
  Pending: Integer;
  Size: TCoord;
  ResizeConsole: TResizePseudoConsole;
  HR: HRESULT;
begin
  Pending := TInterlocked.Exchange(FPendingSize, 0);
  if (Pending <> 0) and (FConsole <> 0) then
  begin
    Size.X := Pending and $FFFF;
    Size.Y := Pending shr 16;
    @ResizeConsole := GetProcAddress(GetModuleHandle('kernel32.dll'), 'ResizePseudoConsole');
    HR := ResizeConsole(FConsole, Size);
    if HR < 0 then TInterlocked.Exchange(FResizeError, HR);
  end;
  Result := (FProcess <> 0) and (WaitForSingleObject(FProcess, 0) = WAIT_OBJECT_0);
end;

procedure TLocalPTY.FinishRead;
begin
  CloseHandleVar(FOutput);
end;

destructor TLocalPTY.Destroy;
begin
  Terminate;
  { Startup failures have no reader. Closing the pipe prevents a final-frame
    write from blocking ClosePseudoConsole. Normal Stop already closed it. }
  CloseHandleVar(FOutput);
  CloseTerminal;
  CloseHandleVar(FInput);
  CloseHandleVar(FProcess);
  CloseHandleVar(FJob);
  inherited;
end;

{$ELSE}
{$IF Defined(LINUX) or (Defined(MACOS) and not Defined(IOS))}
uses Posix.Base, Posix.Unistd, Posix.Fcntl, Posix.Errno, Posix.Signal,
  Posix.SysWait, Posix.Termios;

type
  TPTYSize = record
    Rows, Cols, XPixel, YPixel: Word;
  end;

const
  {$IFDEF LINUX}
  PTYLibrary = 'libutil.so.1';
  SetControllingTTY = $540E;
  SetWindowSize = $5414;
  {$ELSE}
  PTYLibrary = '/usr/lib/libSystem.B.dylib';
  SetControllingTTY = $20007461;
  SetWindowSize = $80087467;
  {$ENDIF}

function OpenPTY(out Master, Slave: Integer; Name, Settings: Pointer;
  Size: Pointer): Integer; cdecl; external PTYLibrary name _PU + 'openpty';
function PTYIoctl(FD: Integer; Request: NativeUInt; Arg: Pointer): Integer;
  cdecl; external libc name _PU + 'ioctl';

procedure PrepareFD(var FD: Integer);
var NewFD: Integer;
begin
  if FD < 3 then
  begin
    NewFD := fcntl(FD, F_DUPFD, 3);
    if NewFD < 0 then RaiseLastOSError;
    __close(FD);
    FD := NewFD;
  end;
  if fcntl(FD, F_SETFD, FD_CLOEXEC) < 0 then RaiseLastOSError;
end;

constructor TLocalPTY.Create;
begin
  inherited;
  FMaster := -1;
  FPid := -1;
  FExitCode := -1;
end;

procedure TLocalPTY.Start(const Executable: string;
  const Arguments: TArray<string>; const Directory: string; Cols, Rows: Integer);
var
  Slave, I, ErrorCode, Got, MaxFD: Integer;
  ErrorPipe: array[0..1] of Integer;
  Size: TPTYSize;
  Shell, WorkDir: UTF8String;
  Args, EnvStrings: TArray<UTF8String>;
  ArgPointers, EnvPointers: TArray<MarshaledAString>;
  Env: PMarshaledAString;
  Entry: UTF8String;
  ShellPtr, DirPtr: MarshaledAString;
  ArgPtr, EnvPtr: PMarshaledAString;
  DefaultAction: sigaction_t;
  EmptyMask: sigset_t;
const
  ResetSignals: array[0..9] of Integer = (SIGINT, SIGQUIT, SIGTERM, SIGHUP,
    SIGPIPE, SIGCHLD, SIGTSTP, SIGTTIN, SIGTTOU, SIGWINCH);
begin
  Shell := UTF8String(Executable);
  if Shell = '' then Shell := UTF8String(GetEnvironmentVariable('SHELL'));
  if Shell = '' then Shell := '/bin/sh';
  if Shell[1] <> '/' then
    raise EArgumentException.Create('POSIX shell executable must be an absolute path');
  WorkDir := UTF8String(Directory);
  SetLength(Args, Length(Arguments) + 1);
  Args[0] := Shell;
  for I := 0 to High(Arguments) do Args[I + 1] := UTF8String(Arguments[I]);
  if Length(Arguments) = 0 then
  begin
    SetLength(Args, 2);
    Args[1] := '-i';
  end;
  SetLength(ArgPointers, Length(Args) + 1);
  for I := 0 to High(Args) do ArgPointers[I] := MarshaledAString(Args[I]);
  Env := environ;
  while Env^ <> nil do
  begin
    Entry := UTF8String(Env^);
    if (Copy(Entry, 1, 5) <> 'TERM=') and
      (Copy(Entry, 1, 10) <> 'COLORTERM=') then
      EnvStrings := EnvStrings + [Entry];
    Inc(Env);
  end;
  EnvStrings := EnvStrings + ['TERM=xterm-256color', 'COLORTERM=truecolor'];
  SetLength(EnvPointers, Length(EnvStrings) + 1);
  for I := 0 to High(EnvStrings) do EnvPointers[I] := MarshaledAString(EnvStrings[I]);
  ShellPtr := MarshaledAString(Shell);
  DirPtr := nil;
  if WorkDir <> '' then DirPtr := MarshaledAString(WorkDir);
  ArgPtr := @ArgPointers[0];
  EnvPtr := @EnvPointers[0];
  MaxFD := sysconf(_SC_OPEN_MAX);
  if MaxFD < 0 then MaxFD := 65536;
  FillChar(DefaultAction, SizeOf(DefaultAction), 0); // SIG_DFL = 0
  sigemptyset(DefaultAction.sa_mask);
  sigemptyset(EmptyMask);
  Size.Rows := Rows;
  Size.Cols := Cols;
  Size.XPixel := 0;
  Size.YPixel := 0;
  Slave := -1;
  ErrorPipe[0] := -1;
  ErrorPipe[1] := -1;
  try
    if OpenPTY(FMaster, Slave, nil, nil, @Size) <> 0 then RaiseLastOSError;
    PrepareFD(FMaster);
    PrepareFD(Slave);
    if pipe(@ErrorPipe[0]) <> 0 then RaiseLastOSError;
    PrepareFD(ErrorPipe[0]);
    PrepareFD(ErrorPipe[1]);
    FPid := fork;
    if FPid < 0 then RaiseLastOSError;
    if FPid = 0 then
    begin
      { No managed-string operations, allocation, exceptions or RTL callbacks
        between fork and exec. All buffers were prepared in the parent. }
      if (setsid < 0) or (PTYIoctl(Slave, SetControllingTTY, nil) < 0) or
        (dup2(Slave, 0) < 0) or (dup2(Slave, 1) < 0) or
        (dup2(Slave, 2) < 0) then
      begin
        ErrorCode := errno;
        __write(ErrorPipe[1], @ErrorCode, SizeOf(ErrorCode));
        _exit(126);
      end;
      for I := Low(ResetSignals) to High(ResetSignals) do
        sigaction(ResetSignals[I], @DefaultAction, nil);
      sigprocmask(SIG_SETMASK, @EmptyMask, nil);
      for I := 3 to MaxFD - 1 do
        if I <> ErrorPipe[1] then __close(I);
      if (DirPtr <> nil) and (__chdir(DirPtr) <> 0) then
      begin
        ErrorCode := errno;
        __write(ErrorPipe[1], @ErrorCode, SizeOf(ErrorCode));
        _exit(126);
      end;
      execve(ShellPtr, ArgPtr, EnvPtr);
      ErrorCode := errno;
      __write(ErrorPipe[1], @ErrorCode, SizeOf(ErrorCode));
      _exit(127);
    end;
    __close(ErrorPipe[1]);
    ErrorPipe[1] := -1;
    repeat
      Got := __read(ErrorPipe[0], @ErrorCode, SizeOf(ErrorCode));
    until (Got >= 0) or (errno <> EINTR);
    if Got > 0 then RaiseLastOSError(ErrorCode);
    if Got < 0 then RaiseLastOSError;
    if fcntl(FMaster, F_SETFL, fcntl(FMaster, F_GETFL, 0) or O_NONBLOCK) < 0 then
      RaiseLastOSError;
  finally
    if Slave >= 0 then __close(Slave);
    if ErrorPipe[0] >= 0 then __close(ErrorPipe[0]);
    if ErrorPipe[1] >= 0 then __close(ErrorPipe[1]);
  end;
end;

function TLocalPTY.Read(var Bytes: TBytes): Integer;
begin
  Result := __read(FMaster, @Bytes[0], Length(Bytes));
  if Result = 0 then Exit(-1);
  if Result < 0 then
  begin
    if (errno = EAGAIN) or (errno = EINTR) then Exit(0);
    if errno = EIO then Exit(-1); // Linux PTY slave closed
    RaiseLastOSError;
  end;
end;

function TLocalPTY.Write(const Bytes: TBytes; Offset: Integer): Integer;
begin
  Result := __write(FMaster, @Bytes[Offset], Length(Bytes) - Offset);
  if Result < 0 then
  begin
    if (errno = EAGAIN) or (errno = EINTR) then Exit(0);
    if errno = EIO then Exit(-1);
    RaiseLastOSError;
  end;
end;

procedure TLocalPTY.Resize(Cols, Rows: Integer);
var Size: TPTYSize;
begin
  FillChar(Size, SizeOf(Size), 0);
  Size.Rows := Rows;
  Size.Cols := Cols;
  if PTYIoctl(FMaster, SetWindowSize, @Size) < 0 then RaiseLastOSError;
end;

procedure TLocalPTY.Terminate;
var Status, Foreground: Integer;
begin
  if FPid <= 0 then Exit;
  { Do not reap before signalling: retaining the child PID prevents reuse. }
  Foreground := tcgetpgrp(FMaster);
  if (Foreground > 0) and (Foreground <> getpgrp) then kill(-Foreground, SIGKILL);
  kill(-FPid, SIGKILL);
  kill(FPid, SIGKILL);
  repeat
    Status := 0;
    Foreground := waitpid(FPid, @Status, 0);
  until (Foreground >= 0) or (errno <> EINTR);
  if (Foreground > 0) and (FExitCode = -1) then
  begin
    if WIFEXITED(Status) then FExitCode := WEXITSTATUS(Status)
    else if WIFSIGNALED(Status) then FExitCode := 128 + WTERMSIG(Status);
  end;
  FPid := -1;
end;

procedure TLocalPTY.CancelWriter(Worker: TThread);
begin
  // PTY descriptor is nonblocking; the writer observes Stop every 5 ms.
end;

procedure TLocalPTY.CloseTerminal;
begin
  // Descriptor stays valid until both workers have joined.
end;

function TLocalPTY.ExitCode: Integer;
begin
  Result := FExitCode; // final wait status becomes available in Terminate
end;

function TLocalPTY.ProcessExited: Boolean;
var
  Info: siginfo_t;
begin
  if FPid <= 0 then Exit(True);
  FillChar(Info, SizeOf(Info), 0);
  { WNOWAIT observes exit without releasing the PID before group cleanup. }
  Result := (waitid(P_PID, FPid, @Info, WEXITED or WNOHANG or WNOWAIT) = 0) and
    (Info.si_signo <> 0);
end;

procedure TLocalPTY.FinishRead;
begin
end;

destructor TLocalPTY.Destroy;
begin
  Terminate;
  if FMaster >= 0 then __close(FMaster);
  inherited;
end;

{$ELSE}
constructor TLocalPTY.Create;
begin
  inherited;
end;
destructor TLocalPTY.Destroy;
begin
  inherited;
end;
procedure TLocalPTY.Start(const Executable: string;
  const Arguments: TArray<string>; const Directory: string; Cols, Rows: Integer);
begin
  raise ENotSupportedException.Create('Local terminal supports Windows, Linux and desktop macOS');
end;
function TLocalPTY.Read(var Bytes: TBytes): Integer;
begin
  Result := -1;
end;
function TLocalPTY.Write(const Bytes: TBytes; Offset: Integer): Integer;
begin
  Result := -1;
end;
procedure TLocalPTY.Resize(Cols, Rows: Integer);
begin
end;
procedure TLocalPTY.Terminate;
begin
end;
procedure TLocalPTY.CancelWriter(Worker: TThread);
begin
end;
procedure TLocalPTY.CloseTerminal;
begin
end;
function TLocalPTY.ExitCode: Integer;
begin
  Result := -1;
end;
function TLocalPTY.ProcessExited: Boolean;
begin
  Result := True;
end;
procedure TLocalPTY.FinishRead;
begin
end;
{$ENDIF}
{$ENDIF}

end.
