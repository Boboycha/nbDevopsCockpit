unit Terminal.LocalSession;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections;

type
  TLocalTerminalDataEvent = procedure(Sender: TObject; const Data: string) of object;
  TLocalTerminalExitEvent = procedure(Sender: TObject; ExitCode: Integer) of object;

  { All public methods and events belong to the UI thread. Call Pump regularly
    (TnbTerminalControl does this). Workers never call or queue UI callbacks. }
  TnbLocalTerminalSession = class(TComponent)
  private
    FBackend: TObject;
    FReader, FWriter, FMonitor: TThread;
    FLock: TCriticalSection;
    FInput: TQueue<TBytes>;
    FOutput: TQueue<TBytes>;
    FInputSize, FOutputSize: Integer;
    FStopping, FReaderStop, FReadDone, FWriteDone: Integer;
    FRunning: Boolean;
    FTail: TBytes;
    FError: string;
    FOnReadData: TLocalTerminalDataEvent;
    FOnExit: TLocalTerminalExitEvent;
    FOnError: TLocalTerminalDataEvent;
    procedure ReadLoop;
    procedure WriteLoop;
    procedure MonitorLoop;
    procedure RecordError(const Msg: string);
    function Decode(const Bytes: TBytes; Final: Boolean): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start(const Executable: string = '';
      const Arguments: TArray<string> = nil; const Directory: string = '';
      Cols: Integer = 80; Rows: Integer = 24);
    procedure Stop;
    procedure SendText(const Text: string);
    procedure ResizePTY(Cols, Rows: Integer);
    procedure Pump;
    property Running: Boolean read FRunning;
  published
    property OnReadData: TLocalTerminalDataEvent read FOnReadData write FOnReadData;
    property OnExit: TLocalTerminalExitEvent read FOnExit write FOnExit;
    property OnError: TLocalTerminalDataEvent read FOnError write FOnError;
  end;

implementation

uses
  System.Math, System.IOUtils, Terminal.LocalPTY;

const
  QueueLimit = 4 * 1024 * 1024;
  PumpBudget = 256 * 1024;

constructor TnbLocalTerminalSession.Create(AOwner: TComponent);
begin
  inherited;
  FLock := TCriticalSection.Create;
  FInput := TQueue<TBytes>.Create;
  FOutput := TQueue<TBytes>.Create;
end;

destructor TnbLocalTerminalSession.Destroy;
begin
  Stop;
  FOutput.Free;
  FInput.Free;
  FLock.Free;
  inherited;
end;

procedure TnbLocalTerminalSession.Start(const Executable: string;
  const Arguments: TArray<string>; const Directory: string; Cols, Rows: Integer);
var
  WorkingDirectory: string;
begin
  WorkingDirectory := Directory;
  if WorkingDirectory = '' then
  begin
    {$IFDEF MSWINDOWS}
    // Delphi GetHomePath maps to roaming AppData on Windows.
    WorkingDirectory := GetEnvironmentVariable('USERPROFILE');
    {$ELSE}
    WorkingDirectory := TPath.GetHomePath;
    {$ENDIF}
  end;
  if WorkingDirectory = '' then
    raise EDirectoryNotFoundException.Create('Cannot determine the user home directory');
  Stop;
  FStopping := 0;
  FReaderStop := 0;
  FReadDone := 0;
  FWriteDone := 0;
  FError := '';
  FTail := nil;
  FBackend := TLocalPTY.Create;
  try
    TLocalPTY(FBackend).Start(Executable, Arguments, WorkingDirectory,
      EnsureRange(Cols, 1, 32767), EnsureRange(Rows, 1, 32767));
    FReader := TThread.CreateAnonymousThread(ReadLoop);
    FReader.FreeOnTerminate := False;
    FReader.Start;
    FWriter := TThread.CreateAnonymousThread(WriteLoop);
    FWriter.FreeOnTerminate := False;
    FWriter.Start;
    FMonitor := TThread.CreateAnonymousThread(MonitorLoop);
    FMonitor.FreeOnTerminate := False;
    FMonitor.Start;
    FRunning := True;
  except
    Stop;
    raise;
  end;
end;

procedure TnbLocalTerminalSession.Stop;
begin
  FRunning := False;
  TInterlocked.Exchange(FStopping, 1);
  if Assigned(FBackend) then
  begin
    { The reader MUST remain alive while ConPTY closes: closing emits output.
      It discards output during shutdown instead of waiting for a UI consumer. }
    if not Assigned(FMonitor) then TLocalPTY(FBackend).Terminate;
    if Assigned(FWriter) then
    begin
      while TInterlocked.CompareExchange(FWriteDone, 0, 0) = 0 do
      begin
        TLocalPTY(FBackend).CancelWriter(FWriter);
        TThread.Sleep(1);
      end;
      FWriter.WaitFor;
      FreeAndNil(FWriter);
    end;
    if Assigned(FMonitor) then
    begin
      FMonitor.WaitFor;
      FreeAndNil(FMonitor);
    end
    else
    begin
      if not Assigned(FReader) then TLocalPTY(FBackend).FinishRead;
      TLocalPTY(FBackend).CloseTerminal;
    end;
  end;
  TInterlocked.Exchange(FReaderStop, 1);
  if Assigned(FReader) then
  begin
    FReader.WaitFor;
    FreeAndNil(FReader);
  end;
  FreeAndNil(FBackend);
  if Assigned(FInput) then FInput.Clear;
  if Assigned(FOutput) then FOutput.Clear;
  FInputSize := 0;
  FOutputSize := 0;
  FTail := nil;
end;

procedure TnbLocalTerminalSession.MonitorLoop;
begin
  while (TInterlocked.CompareExchange(FStopping, 0, 0) = 0) and
    (TInterlocked.CompareExchange(FReadDone, 0, 0) = 0) and
    not TLocalPTY(FBackend).ProcessExited do TThread.Sleep(5);
  TLocalPTY(FBackend).Terminate;
  TLocalPTY(FBackend).CloseTerminal;
end;

procedure TnbLocalTerminalSession.RecordError(const Msg: string);
begin
  FLock.Acquire;
  try
    if FError = '' then FError := Msg;
  finally
    FLock.Release;
  end;
end;

procedure TnbLocalTerminalSession.ReadLoop;
var
  Bytes: TBytes;
  Count: Integer;
  Queued: Boolean;
begin
  try
    try
      while TInterlocked.CompareExchange(FReaderStop, 0, 0) = 0 do
      begin
        SetLength(Bytes, 16384);
        Count := TLocalPTY(FBackend).Read(Bytes);
        if Count < 0 then Break;
        if Count = 0 then
        begin
          TThread.Sleep(5);
          Continue;
        end;
        SetLength(Bytes, Count);
        repeat
          if TInterlocked.CompareExchange(FStopping, 0, 0) <> 0 then Break;
          FLock.Acquire;
          try
            Queued := FOutputSize + Count <= QueueLimit;
            if Queued then
            begin
              FOutput.Enqueue(Bytes);
              Inc(FOutputSize, Count);
              Bytes := nil; // next Read must not overwrite a queued array
            end;
          finally
            FLock.Release;
          end;
          if not Queued then TThread.Sleep(5);
        until Queued;
      end;
    except
      on E: Exception do RecordError(E.Message);
    end;
  finally
    TLocalPTY(FBackend).FinishRead;
    TInterlocked.Exchange(FReadDone, 1);
  end;
end;

procedure TnbLocalTerminalSession.WriteLoop;
var
  Bytes: TBytes;
  Offset, Count: Integer;
begin
  try
    try
      while TInterlocked.CompareExchange(FStopping, 0, 0) = 0 do
      begin
        Bytes := nil;
        FLock.Acquire;
        try
          if FInput.Count > 0 then
          begin
            Bytes := FInput.Dequeue;
            Dec(FInputSize, Length(Bytes));
          end;
        finally
          FLock.Release;
        end;
        if Length(Bytes) = 0 then
        begin
          TThread.Sleep(5);
          Continue;
        end;
        Offset := 0;
        while (Offset < Length(Bytes)) and
          (TInterlocked.CompareExchange(FStopping, 0, 0) = 0) do
        begin
          Count := TLocalPTY(FBackend).Write(Bytes, Offset);
          if Count < 0 then Exit;
          if Count = 0 then TThread.Sleep(5) else Inc(Offset, Count);
        end;
      end;
    except
      on E: Exception do RecordError(E.Message);
    end;
  finally
    TInterlocked.Exchange(FWriteDone, 1);
  end;
end;

procedure TnbLocalTerminalSession.SendText(const Text: string);
var
  Bytes: TBytes;
begin
  if not FRunning or (Text = '') then Exit;
  Bytes := TEncoding.UTF8.GetBytes(Text);
  FLock.Acquire;
  try
    if Length(Bytes) > QueueLimit - FInputSize then
      raise EInvalidOperation.Create('Local terminal input queue is full');
    FInput.Enqueue(Bytes);
    Inc(FInputSize, Length(Bytes));
  finally
    FLock.Release;
  end;
end;

procedure TnbLocalTerminalSession.ResizePTY(Cols, Rows: Integer);
begin
  if FRunning then
    TLocalPTY(FBackend).Resize(EnsureRange(Cols, 1, 32767),
      EnsureRange(Rows, 1, 32767));
end;

function TnbLocalTerminalSession.Decode(const Bytes: TBytes; Final: Boolean): string;
var
  Combined: TBytes;
  Cut, Lead, Expected: Integer;
  B: Byte;
begin
  Combined := FTail + Bytes;
  Cut := Length(Combined);
  if not Final and (Cut > 0) then
  begin
    Lead := Cut - 1;
    while (Lead > 0) and ((Combined[Lead] and $C0) = $80) do Dec(Lead);
    B := Combined[Lead];
    Expected := 1;
    if (B >= $C2) and (B <= $DF) then Expected := 2
    else if (B >= $E0) and (B <= $EF) then Expected := 3
    else if (B >= $F0) and (B <= $F4) then Expected := 4;
    if Cut - Lead < Expected then Cut := Lead;
  end;
  Result := TEncoding.UTF8.GetString(Combined, 0, Cut);
  FTail := Copy(Combined, Cut, Length(Combined) - Cut);
end;

procedure TnbLocalTerminalSession.Pump;
var
  Bytes: TBytes;
  Text, ErrorText: string;
  Budget, ExitCode: Integer;
  Empty: Boolean;
begin
  if not FRunning then Exit;
  Text := '';
  Budget := PumpBudget;
  repeat
    Bytes := nil;
    FLock.Acquire;
    try
      if FOutput.Count > 0 then
      begin
        Bytes := FOutput.Dequeue;
        Dec(FOutputSize, Length(Bytes));
      end;
      Empty := FOutput.Count = 0;
      ErrorText := FError;
    finally
      FLock.Release;
    end;
    Text := Text + Decode(Bytes, False);
    Dec(Budget, Length(Bytes));
  until Empty or (Budget <= 0);
  if (Text <> '') and Assigned(FOnReadData) then FOnReadData(Self, Text);
  if not FRunning then Exit;
  FLock.Acquire;
  try
    Empty := FOutput.Count = 0;
  finally
    FLock.Release;
  end;
  if (ErrorText <> '') or
    ((TInterlocked.CompareExchange(FReadDone, 0, 0) <> 0) and Empty) then
  begin
    Text := Decode(nil, True);
    if ErrorText <> '' then TInterlocked.Exchange(FStopping, 1);
    if Assigned(FMonitor) then FMonitor.WaitFor;
    ExitCode := TLocalPTY(FBackend).ExitCode;
    Stop;
    if (Text <> '') and Assigned(FOnReadData) then FOnReadData(Self, Text);
    if (ErrorText <> '') and Assigned(FOnError) then FOnError(Self, ErrorText);
    if Assigned(FOnExit) then FOnExit(Self, ExitCode);
  end;
end;

end.
