unit nbSFTPTransfer;

(*
  TnbSFTPTransfer streams files between SFTP endpoints or between SFTP and the
  local filesystem. SFTP has no server-to-server copy primitive, so bytes pass
  through this process. The worker reads chunks from the source and writes them
  to the target using a pipelined reader thread + buffer queue.

  Supported transfer modes:
    SFTP → SFTP   via Start()
    SFTP → local  via StartDownload()
    local → SFTP  via StartUpload()
*)

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, System.SyncObjs,
  System.Generics.Collections,
  nbSFTPClient;

type
  TnbTransferPhase = (tpIdle, tpDownload, tpUpload, tpStream,
    tpReadingSource, tpWritingTarget,
    tpClosingTarget, tpClosingSource, tpClosingSession);

  TnbTransferProgressEvent = procedure(Sender: TObject;
    APhase: TnbTransferPhase; ADone, ATotal: Int64) of object;
  TnbTransferErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;

  TnbSFTPTransfer = class;

  TnbSFTPTransferJob = record
    SourceInfo: TnbSFTPConnectionInfo;
    TargetInfo: TnbSFTPConnectionInfo;
    SourcePath: string;
    TargetPath: string;
    SourceIsLocal: Boolean;
    TargetIsLocal: Boolean;
  end;

  TnbSFTPTransferWorker = class(TThread)
  private
    FOwner: TnbSFTPTransfer;
    FSourceInfo: TnbSFTPConnectionInfo;
    FTargetInfo: TnbSFTPConnectionInfo;
    FSourcePath: string;
    FTargetPath: string;
    FSourceIsLocal: Boolean;
    FTargetIsLocal: Boolean;
    FError: string;
    FStage: TnbTransferPhase;
    FDone: Int64;
    FTotal: Int64;
    FLastProgressTick: UInt64;
    FTracePath: string;
    procedure Summary(const AMsg: string);
    procedure Trace(const AMsg: string);
    procedure QueueProgress(AForce: Boolean = False);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TnbSFTPTransfer;
      const ASourceInfo, ATargetInfo: TnbSFTPConnectionInfo;
      const ASourcePath, ATargetPath: string;
      ASourceIsLocal: Boolean = False; ATargetIsLocal: Boolean = False);

    property Error: string read FError;
  end;

  TnbSFTPTransfer = class(TComponent)
  private
    FQueue: TQueue<TnbSFTPTransferJob>;
    FWorker: TnbSFTPTransferWorker;
    FPhase: TnbTransferPhase;
    FOnProgress: TnbTransferProgressEvent;
    FOnDone: TNotifyEvent;
    FOnError: TnbTransferErrorEvent;

    procedure StartJob(const AJob: TnbSFTPTransferJob);
    procedure StartNextQueuedJob;
    procedure WorkerFinished(AWorker: TnbSFTPTransferWorker;
      const AError: string);
    procedure WorkerProgress(ADone, ATotal: Int64);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function Busy: Boolean;
    function PendingCount: Integer;
    procedure Cancel;
    procedure ClearQueue;

    procedure Start(ASource: TnbSFTPClient; const ARemoteSrc: string;
      ATarget: TnbSFTPClient; const ADstPath: string);
    procedure StartDownload(ASource: TnbSFTPClient;
      const ARemotePath, ALocalPath: string);
    procedure StartUpload(const ALocalPath: string;
      ATarget: TnbSFTPClient; const ARemotePath: string);

  published
    property OnProgress: TnbTransferProgressEvent read FOnProgress write FOnProgress;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
    property OnError: TnbTransferErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  System.StrUtils,
  blcksock, nbSSH.LibSSH2;

const
  STREAM_BUFFER_SIZE = 8 * 1024 * 1024;
  PIPELINE_QUEUE_LIMIT = 8;
  PIPELINE_WAIT_MS = 50;
  TARGET_WRITE_MODE_SSH_EXEC = True;
  TRANSFER_SUMMARY_ENABLED = True;
  TRANSFER_TRACE_ENABLED = False;

type
  TSSHSessionHandle = nbSSH.LibSSH2.PLIBSSH2_SESSION;
  TSSHChannelHandle = nbSSH.LibSSH2.PLIBSSH2_CHANNEL;

  TnbSFTPBufferQueue = class
  private
    FQueue: TQueue<TBytes>;
    FLock: TCriticalSection;
    FDataEvent: TEvent;
    FSpaceEvent: TEvent;
    FLimit: Integer;
    FClosed: Boolean;
  public
    constructor Create(ALimit: Integer);
    destructor Destroy; override;

    function Push(const ABuffer: TBytes;
      const ACancelled: TFunc<Boolean>): Boolean;
    function Pop(out ABuffer: TBytes;
      const ACancelled: TFunc<Boolean>): Boolean;
    procedure Close;
  end;

  TnbSSHExecWriteSession = class
  private
    FInfo: TnbSFTPConnectionInfo;
    FSocket: TTCPBlockSocket;
    FSession: TSSHSessionHandle;
    FChannel: TSSHChannelHandle;
    FCancelled: TFunc<Boolean>;
    FFinished: Boolean;
    FEagainCount: Int64;
    FEagainWaitMs: Int64;
    FCurrentEagainStreak: Integer;
    FMaxEagainStreak: Integer;
    function GetSessionError: string;
    function IsCancelled: Boolean;
    procedure TrackEagain;
    function WaitChannelResult(const AFunc: TFunc<Integer>): Integer;
  public
    constructor Create(const AInfo: TnbSFTPConnectionInfo;
      const ACancelled: TFunc<Boolean>);
    destructor Destroy; override;

    procedure StartWriteCommand(const ATargetPath: string);
    function Write(const ABuffer; ACount: NativeUInt): NativeInt;
    procedure Finish;
    procedure Disconnect;
    property EagainCount: Int64 read FEagainCount;
    property EagainWaitMs: Int64 read FEagainWaitMs;
    property MaxEagainStreak: Integer read FMaxEagainStreak;
  end;

function TraceTick: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

function ToUtf8AnsiLocal(const S: string): AnsiString;
begin
  Result := AnsiString(UTF8String(S));
end;

function ShellQuote(const S: string): string;
begin
  Result := #39 + StringReplace(S, #39, #39 + '\' + #39 + #39,
    [rfReplaceAll]) + #39;
end;

{ TnbSFTPBufferQueue }

constructor TnbSFTPBufferQueue.Create(ALimit: Integer);
begin
  inherited Create;
  FLimit := ALimit;
  FQueue := TQueue<TBytes>.Create;
  FLock := TCriticalSection.Create;
  FDataEvent := TEvent.Create(nil, True, False, '');
  FSpaceEvent := TEvent.Create(nil, True, True, '');
end;

destructor TnbSFTPBufferQueue.Destroy;
begin
  FSpaceEvent.Free;
  FDataEvent.Free;
  FLock.Free;
  FQueue.Free;
  inherited;
end;

procedure TnbSFTPBufferQueue.Close;
begin
  FLock.Enter;
  try
    FClosed := True;
    FDataEvent.SetEvent;
    FSpaceEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TnbSFTPBufferQueue.Push(const ABuffer: TBytes;
  const ACancelled: TFunc<Boolean>): Boolean;
begin
  Result := False;
  while True do
  begin
    FLock.Enter;
    try
      if FClosed then Exit;
      if FQueue.Count < FLimit then
      begin
        FQueue.Enqueue(ABuffer);
        FDataEvent.SetEvent;
        if FQueue.Count >= FLimit then
          FSpaceEvent.ResetEvent
        else
          FSpaceEvent.SetEvent;
        Exit(True);
      end;
      FSpaceEvent.ResetEvent;
    finally
      FLock.Leave;
    end;

    if Assigned(ACancelled) and ACancelled() then Exit;
    FSpaceEvent.WaitFor(PIPELINE_WAIT_MS);
  end;
end;

function TnbSFTPBufferQueue.Pop(out ABuffer: TBytes;
  const ACancelled: TFunc<Boolean>): Boolean;
begin
  Result := False;
  ABuffer := nil;
  while True do
  begin
    FLock.Enter;
    try
      if FQueue.Count > 0 then
      begin
        ABuffer := FQueue.Dequeue;
        FSpaceEvent.SetEvent;
        if FQueue.Count = 0 then
          FDataEvent.ResetEvent;
        Exit(True);
      end;
      if FClosed then Exit;
      FDataEvent.ResetEvent;
    finally
      FLock.Leave;
    end;

    if Assigned(ACancelled) and ACancelled() then Exit;
    FDataEvent.WaitFor(PIPELINE_WAIT_MS);
  end;
end;

{ TnbSSHExecWriteSession }

constructor TnbSSHExecWriteSession.Create(const AInfo: TnbSFTPConnectionInfo;
  const ACancelled: TFunc<Boolean>);
begin
  inherited Create;
  FInfo := AInfo;
  FCancelled := ACancelled;
end;

destructor TnbSSHExecWriteSession.Destroy;
begin
  Disconnect;
  inherited;
end;

function TnbSSHExecWriteSession.GetSessionError: string;
var
  ErrMsg: PAnsiChar;
  ErrLen: Integer;
begin
  Result := '';
  ErrMsg := nil;
  ErrLen := 0;
  if (FSession <> nil) and Assigned(ssh2_session_last_error) then
    ssh2_session_last_error(FSession, @ErrMsg, @ErrLen, 0);
  if (ErrMsg <> nil) and (ErrLen > 0) then
    Result := string(UTF8String(Copy(AnsiString(ErrMsg), 1, ErrLen)));
  if Result = '' then
    Result := 'libssh2 error';
end;

function TnbSSHExecWriteSession.IsCancelled: Boolean;
begin
  Result := Assigned(FCancelled) and FCancelled();
end;

procedure TnbSSHExecWriteSession.TrackEagain;
var
  Started: UInt64;
begin
  Inc(FEagainCount);
  Inc(FCurrentEagainStreak);
  if FCurrentEagainStreak > FMaxEagainStreak then
    FMaxEagainStreak := FCurrentEagainStreak;

  Started := TraceTick;
  Sleep(0);
  Inc(FEagainWaitMs, TraceTick - Started);
end;

function TnbSSHExecWriteSession.WaitChannelResult(
  const AFunc: TFunc<Integer>): Integer;
begin
  repeat
    Result := AFunc();
    if Result <> LIBSSH2_ERROR_EAGAIN then
    begin
      FCurrentEagainStreak := 0;
      Exit;
    end;
    if IsCancelled then
      raise EAbort.Create('SSH target write cancelled');
    TrackEagain;
  until False;
end;

procedure TnbSSHExecWriteSession.StartWriteCommand(const ATargetPath: string);
var
  RC: Integer;
  AnsiUser, AnsiPwd, AnsiPassphrase, Command: AnsiString;
  PassphrasePtr: PAnsiChar;
begin
  Disconnect;
  EnsureLibLoaded;

  FSocket := TTCPBlockSocket.Create;
  FSocket.ConnectionTimeout := 10000;
  FSocket.SetTimeout(30000);
  FSocket.Connect(FInfo.Host, FInfo.Port);
  if FSocket.LastError <> 0 then
    raise Exception.Create('TCP connect failed: ' + FSocket.LastErrorDesc);

  FSession := ssh2_session_init_ex(nil, nil, nil, nil);
  if FSession = nil then
    raise Exception.Create('libssh2_session_init failed');

  RC := ssh2_session_handshake(FSession, FSocket.Socket);
  if RC <> 0 then
    raise Exception.Create('SSH handshake failed: ' + GetSessionError);

  AnsiUser := AnsiString(FInfo.User);
  AnsiPassphrase := AnsiString(FInfo.Passphrase);
  if AnsiPassphrase = '' then
    PassphrasePtr := nil
  else
    PassphrasePtr := PAnsiChar(AnsiPassphrase);

  if Length(FInfo.KeyData) > 0 then
    RC := ssh2_userauth_publickey_frommemory(FSession,
      PAnsiChar(AnsiUser), Length(AnsiUser),
      PAnsiChar(FInfo.PubKeyData), Length(FInfo.PubKeyData),
      PAnsiChar(FInfo.KeyData), Length(FInfo.KeyData),
      PassphrasePtr)
  else if FInfo.Password <> '' then
  begin
    AnsiPwd := AnsiString(FInfo.Password);
    RC := ssh2_userauth_password_ex(FSession, PAnsiChar(AnsiUser),
      Length(AnsiUser), PAnsiChar(AnsiPwd), Length(AnsiPwd), nil);
  end
  else
    raise Exception.Create('No authentication method');

  if RC <> 0 then
    raise Exception.Create('Authentication failed: ' + GetSessionError);

  FChannel := ssh2_channel_open_ex(FSession,
    'session', 7,
    LIBSSH2_CHANNEL_WINDOW_DEFAULT, LIBSSH2_CHANNEL_PACKET_DEFAULT,
    nil, 0);
  if FChannel = nil then
    raise Exception.Create('Channel open failed: ' + GetSessionError);

  Command := ToUtf8AnsiLocal('sh -c ' + ShellQuote('cat > "$1"') +
    ' sh ' + ShellQuote(ATargetPath));
  RC := ssh2_channel_process_startup(FChannel, 'exec', 4,
    PAnsiChar(Command), Length(Command));
  if RC <> 0 then
    raise Exception.Create('Exec target write failed: ' + GetSessionError);

  FSocket.NonBlockMode := True;
  ssh2_session_set_blocking(FSession, 0);
end;

function TnbSSHExecWriteSession.Write(const ABuffer;
  ACount: NativeUInt): NativeInt;
var
  BufferPtr: PAnsiChar;
begin
  BufferPtr := PAnsiChar(@ABuffer);
  repeat
    Result := ssh2_channel_write_ex(FChannel, 0, BufferPtr, ACount);
    if Result <> LIBSSH2_ERROR_EAGAIN then Break;
    if IsCancelled then
      raise EAbort.Create('SSH target write cancelled');
    TrackEagain;
  until False;
  FCurrentEagainStreak := 0;
  if Result < 0 then
    raise Exception.Create('SSH target write failed: ' + GetSessionError);
end;

procedure TnbSSHExecWriteSession.Finish;
var
  RC: Integer;
begin
  if (FChannel = nil) or FFinished then Exit;
  FFinished := True;
  WaitChannelResult(
    function: Integer
    begin
      Result := ssh2_channel_send_eof(FChannel);
    end);
  WaitChannelResult(
    function: Integer
    begin
      Result := ssh2_channel_wait_closed(FChannel);
    end);
  RC := ssh2_channel_get_exit_status(FChannel);
  if RC <> 0 then
    raise Exception.CreateFmt('SSH target command failed with exit status %d',
      [RC]);
end;

procedure TnbSSHExecWriteSession.Disconnect;
begin
  if FChannel <> nil then
  begin
    try
      if not FFinished then
        ssh2_channel_send_eof(FChannel);
    except
    end;
    try ssh2_channel_close(FChannel); except end;
    try ssh2_channel_free(FChannel); except end;
    FChannel := nil;
  end;
  if FSession <> nil then
  begin
    try
      ssh2_session_disconnect_ex(FSession, LIBSSH2_DISCONNECT_BY_APPLICATION,
        'bye', '');
    except
    end;
    try ssh2_session_free(FSession); except end;
    FSession := nil;
  end;
  FreeAndNil(FSocket);
end;

{ TnbSFTPTransferWorker }

constructor TnbSFTPTransferWorker.Create(AOwner: TnbSFTPTransfer;
  const ASourceInfo, ATargetInfo: TnbSFTPConnectionInfo;
  const ASourcePath, ATargetPath: string;
  ASourceIsLocal: Boolean = False; ATargetIsLocal: Boolean = False);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FSourceInfo := ASourceInfo;
  FTargetInfo := ATargetInfo;
  FSourcePath := ASourcePath;
  FTargetPath := ATargetPath;
  FSourceIsLocal := ASourceIsLocal;
  FTargetIsLocal := ATargetIsLocal;
  if ASourceIsLocal then
    FStage := tpUpload
  else if ATargetIsLocal then
    FStage := tpDownload
  else
    FStage := tpStream;
end;

procedure TnbSFTPTransferWorker.Summary(const AMsg: string);
var
  Path, Line: string;
begin
  if not TRANSFER_SUMMARY_ENABLED then Exit;

  Path := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
  ForceDirectories(Path);
  Path := TPath.Combine(Path, 'sftp-transfer-summary.log');

  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
    Format(' [thread %d] ', [TThread.CurrentThread.ThreadID]) + AMsg + sLineBreak;
  TFile.AppendAllText(Path, Line, TEncoding.UTF8);
end;

procedure TnbSFTPTransferWorker.Trace(const AMsg: string);
var
  Line: string;
begin
  if not TRANSFER_TRACE_ENABLED then Exit;

  if FTracePath = '' then
  begin
    FTracePath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
    ForceDirectories(FTracePath);
    FTracePath := TPath.Combine(FTracePath,
      FormatDateTime('"sftp-transfer-"yyyymmdd"-"hhnnss"-"zzz".log"', Now));
  end;

  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
    Format(' [thread %d] ', [TThread.CurrentThread.ThreadID]) + AMsg + sLineBreak;
  TFile.AppendAllText(FTracePath, Line, TEncoding.UTF8);
end;

procedure TnbSFTPTransferWorker.QueueProgress(AForce: Boolean);
var
  Owner: TnbSFTPTransfer;
  Stage: TnbTransferPhase;
  Done, Total: Int64;
  Tick: UInt64;
begin
  if FOwner = nil then Exit;

  Tick := TThread.GetTickCount64;
  if (not AForce) and (FLastProgressTick <> 0) and
     (Tick - FLastProgressTick < 100) then Exit;
  FLastProgressTick := Tick;

  Owner := FOwner;
  Stage := FStage;
  Done := FDone;
  Total := FTotal;
  TThread.Queue(nil,
    procedure
    begin
      if Owner.FWorker <> nil then
      begin
        Owner.FPhase := Stage;
        Owner.WorkerProgress(Done, Total);
      end;
    end);
end;

procedure TnbSFTPTransferWorker.Execute;
var
  SourceSession, TargetSession: TnbSFTPRawSession;
  TargetExec: TnbSSHExecWriteSession;
  LocalSourceStream, LocalTargetStream: TFileStream;
  SourceHandle, TargetHandle: PLIBSSH2_SFTP_HANDLE;
  PipelineQueue: TnbSFTPBufferQueue;
  ReaderThread: TThread;
  Buffer: TBytes;
  ReadLen, WriteLen, Offset: NativeInt;
  OpStarted: UInt64;
  Owner: TnbSFTPTransfer;
  ErrorText: string;
  ReaderError: string;
  TransferStarted: UInt64;
  ReadStarted, WriteStarted, WaitStarted: UInt64;
  ReadMs, WriteMs, PushWaitMs, PopWaitMs: Int64;
  ReadChunks, WriteCalls: Int64;
  SshEagainCount, SshEagainWaitMs: Int64;
  SshMaxEagainStreak: Integer;
  StatusText, ModeText: string;
  WasCancelled: Boolean;

  procedure DeletePartialTarget;
  var
    CleanupSession: TnbSFTPRawSession;
  begin
    if FTargetIsLocal then
    begin
      try
        if TFile.Exists(FTargetPath) then
          TFile.Delete(FTargetPath);
        Trace('partial local target deleted');
      except
      end;
      Exit;
    end;
    CleanupSession := nil;
    try
      CleanupSession := TnbSFTPRawSession.Create(FTargetInfo,
        function: Boolean
        begin
          Result := False;
        end, True);
      CleanupSession.Connect;
      CleanupSession.DeleteFile(FTargetPath);
      Trace('partial target deleted');
    finally
      if CleanupSession <> nil then
      begin
        CleanupSession.AbortDisconnect;
        CleanupSession.Free;
      end;
    end;
  end;
begin
  SourceSession := nil;
  TargetSession := nil;
  TargetExec := nil;
  LocalSourceStream := nil;
  LocalTargetStream := nil;
  SourceHandle := nil;
  TargetHandle := nil;
  PipelineQueue := nil;
  ReaderThread := nil;
  TransferStarted := TraceTick;
  ReadMs := 0;
  WriteMs := 0;
  PushWaitMs := 0;
  PopWaitMs := 0;
  ReadChunks := 0;
  WriteCalls := 0;
  SshEagainCount := 0;
  SshEagainWaitMs := 0;
  SshMaxEagainStreak := 0;
  try
    if TRANSFER_TRACE_ENABLED then
    begin
      if FSourceIsLocal then
        Trace(Format('start source=local %s target=%s:%s %s',
          [FSourcePath, FTargetInfo.Host, FTargetInfo.Port, FTargetPath]))
      else if FTargetIsLocal then
        Trace(Format('start source=%s:%s %s target=local %s',
          [FSourceInfo.Host, FSourceInfo.Port, FSourcePath, FTargetPath]))
      else
        Trace(Format('start source=%s:%s %s target=%s:%s %s',
          [FSourceInfo.Host, FSourceInfo.Port, FSourcePath,
           FTargetInfo.Host, FTargetInfo.Port, FTargetPath]));
    end;

    // --- Source setup ---
    if FSourceIsLocal then
    begin
      LocalSourceStream := TFileStream.Create(FSourcePath,
        fmOpenRead or fmShareDenyWrite);
      FTotal := LocalSourceStream.Size;
    end
    else
    begin
      SourceSession := TnbSFTPRawSession.Create(FSourceInfo,
        function: Boolean
        begin
          Result := Terminated;
        end, True);
      if TRANSFER_TRACE_ENABLED then
      begin
        Trace('connect source begin');
        OpStarted := TraceTick;
      end;
      SourceSession.Connect;
      if TRANSFER_TRACE_ENABLED then
        Trace(Format('connect source end elapsed=%dms', [TraceTick - OpStarted]));
      if TRANSFER_TRACE_ENABLED then
      begin
        Trace('stat source begin');
        OpStarted := TraceTick;
      end;
      FTotal := SourceSession.StatSize(FSourcePath);
      if TRANSFER_TRACE_ENABLED then
        Trace(Format('stat source end size=%d elapsed=%dms',
          [FTotal, TraceTick - OpStarted]));
    end;

    // --- Target setup ---
    if FTargetIsLocal then
    begin
      LocalTargetStream := TFileStream.Create(FTargetPath, fmCreate);
    end
    else
    begin
      if TARGET_WRITE_MODE_SSH_EXEC then
        TargetExec := TnbSSHExecWriteSession.Create(FTargetInfo,
          function: Boolean
          begin
            Result := Terminated;
          end)
      else
        TargetSession := TnbSFTPRawSession.Create(FTargetInfo,
          function: Boolean
          begin
            Result := Terminated;
          end, True);
      if TRANSFER_TRACE_ENABLED then
      begin
        Trace('connect target begin');
        OpStarted := TraceTick;
      end;
      if TARGET_WRITE_MODE_SSH_EXEC then
        TargetExec.StartWriteCommand(FTargetPath)
      else
        TargetSession.Connect;
      if TRANSFER_TRACE_ENABLED then
        Trace(Format('connect target end elapsed=%dms', [TraceTick - OpStarted]));
    end;

    // --- Open SFTP handles ---
    if not FSourceIsLocal then
    begin
      if TRANSFER_TRACE_ENABLED then
      begin
        Trace('open source begin');
        OpStarted := TraceTick;
      end;
      SourceHandle := SourceSession.OpenRead(FSourcePath);
      if TRANSFER_TRACE_ENABLED then
        Trace(Format('open source end elapsed=%dms', [TraceTick - OpStarted]));
    end;
    if (TargetSession <> nil) then
    begin
      if TRANSFER_TRACE_ENABLED then
      begin
        Trace('open target begin');
        OpStarted := TraceTick;
      end;
      TargetHandle := TargetSession.OpenWrite(FTargetPath);
      if TRANSFER_TRACE_ENABLED then
        Trace(Format('open target end elapsed=%dms', [TraceTick - OpStarted]));
    end;

    SetLength(Buffer, STREAM_BUFFER_SIZE);
    FDone := 0;
    QueueProgress(True);

    PipelineQueue := TnbSFTPBufferQueue.Create(PIPELINE_QUEUE_LIMIT);
    ReaderThread := TThread.CreateAnonymousThread(
      procedure
      var
        ReadBuffer, Chunk: TBytes;
        LocalReadLen: NativeInt;
      begin
        try
          SetLength(ReadBuffer, STREAM_BUFFER_SIZE);
          while not Terminated do
          begin
            ReadStarted := TraceTick;
            if FSourceIsLocal then
              LocalReadLen := LocalSourceStream.Read(ReadBuffer[0], Length(ReadBuffer))
            else
              LocalReadLen := SourceSession.Read(SourceHandle, ReadBuffer[0],
                Length(ReadBuffer));
            Inc(ReadMs, TraceTick - ReadStarted);
            if LocalReadLen = 0 then Break;
            Inc(ReadChunks);

            SetLength(Chunk, LocalReadLen);
            Move(ReadBuffer[0], Chunk[0], LocalReadLen);
            WaitStarted := TraceTick;
            if not PipelineQueue.Push(Chunk,
              function: Boolean
              begin
                Result := Terminated;
              end) then
              Break;
            Inc(PushWaitMs, TraceTick - WaitStarted);
          end;
        except
          on E: Exception do
          begin
            ReaderError := E.Message;
            Trace('reader error: ' + E.Message);
          end;
        end;
        PipelineQueue.Close;
      end);
    ReaderThread.FreeOnTerminate := False;
    ReaderThread.Start;

    while not Terminated do
    begin
      WaitStarted := TraceTick;
      if not PipelineQueue.Pop(Buffer,
        function: Boolean
        begin
          Result := Terminated;
        end) then
        Break;
      Inc(PopWaitMs, TraceTick - WaitStarted);

      ReadLen := Length(Buffer);
      Offset := 0;
      while (Offset < ReadLen) and not Terminated do
      begin
        if TRANSFER_TRACE_ENABLED then
        begin
          FStage := tpWritingTarget;
          QueueProgress;
          Trace(Format('write begin done=%d offset=%d request=%d',
            [FDone, Offset, ReadLen - Offset]));
          OpStarted := TraceTick;
        end;
        WriteStarted := TraceTick;
        if FTargetIsLocal then
          WriteLen := LocalTargetStream.Write(Buffer[Offset], ReadLen - Offset)
        else if TARGET_WRITE_MODE_SSH_EXEC then
          WriteLen := TargetExec.Write(Buffer[Offset], ReadLen - Offset)
        else
          WriteLen := TargetSession.Write(TargetHandle, Buffer[Offset],
            ReadLen - Offset);
        Inc(WriteMs, TraceTick - WriteStarted);
        if TRANSFER_TRACE_ENABLED then
          Trace(Format('write end done=%d offset=%d result=%d elapsed=%dms',
            [FDone, Offset, WriteLen, TraceTick - OpStarted]));
        if WriteLen = 0 then
          raise Exception.Create('Write target file failed: zero bytes written');
        Inc(Offset, WriteLen);
        Inc(FDone, WriteLen);
        Inc(WriteCalls);
        if FSourceIsLocal then
          FStage := tpUpload
        else if FTargetIsLocal then
          FStage := tpDownload
        else
          FStage := tpStream;
        QueueProgress;
        if (FTotal > 0) and (FDone >= FTotal) then Break;
      end;
    end;

    if PipelineQueue <> nil then
      PipelineQueue.Close;
    if ReaderThread <> nil then
    begin
      ReaderThread.WaitFor;
      FreeAndNil(ReaderThread);
    end;
    FreeAndNil(PipelineQueue);
    if ReaderError <> '' then
      raise Exception.Create(ReaderError);
  except
    on E: EAbort do
      if not Terminated then
      begin
        FError := E.Message;
        Trace('abort: ' + E.Message);
      end;
    on E: Exception do
    begin
      FError := E.Message;
      Trace('error: ' + E.Message);
    end;
  end;

  if PipelineQueue <> nil then
    PipelineQueue.Close;
  if ReaderThread <> nil then
  begin
    ReaderThread.Terminate;
    ReaderThread.WaitFor;
    FreeAndNil(ReaderThread);
  end;
  FreeAndNil(PipelineQueue);

  // --- Close target ---
  if FTargetIsLocal then
    FreeAndNil(LocalTargetStream)
  else
  begin
    if TargetSession <> nil then
    begin
      FStage := tpClosingTarget;
      QueueProgress(True);
      Trace('close target begin');
      OpStarted := TraceTick;
      TargetSession.CloseFile(TargetHandle);
      Trace(Format('close target end elapsed=%dms', [TraceTick - OpStarted]));
    end;
    if TargetExec <> nil then
    begin
      FStage := tpClosingTarget;
      QueueProgress(True);
      Trace('finish ssh target begin');
      OpStarted := TraceTick;
      if FError = '' then
      begin
        try
          TargetExec.Finish;
        except
          on E: Exception do
            FError := E.Message;
        end;
      end;
      Trace(Format('finish ssh target end elapsed=%dms', [TraceTick - OpStarted]));
    end;
  end;

  // --- Close source ---
  if not FSourceIsLocal then
  begin
    if SourceSession <> nil then
    begin
      FStage := tpClosingSource;
      QueueProgress(True);
      Trace('close source begin');
      OpStarted := TraceTick;
      SourceSession.CloseFile(SourceHandle);
      Trace(Format('close source end elapsed=%dms', [TraceTick - OpStarted]));
    end;
  end
  else
    FreeAndNil(LocalSourceStream);

  // --- Disconnect sessions ---
  FStage := tpClosingSession;
  QueueProgress(True);
  Trace('abort sessions begin');
  if TargetSession <> nil then
  begin
    TargetSession.AbortDisconnect;
    FreeAndNil(TargetSession);
  end;
  if TargetExec <> nil then
  begin
    SshEagainCount := TargetExec.EagainCount;
    SshEagainWaitMs := TargetExec.EagainWaitMs;
    SshMaxEagainStreak := TargetExec.MaxEagainStreak;
    TargetExec.Disconnect;
    FreeAndNil(TargetExec);
  end;
  if SourceSession <> nil then
  begin
    SourceSession.AbortDisconnect;
    FreeAndNil(SourceSession);
  end;
  Trace('abort sessions end');

  WasCancelled := Terminated;
  if WasCancelled or (FError <> '') then
  begin
    try
      DeletePartialTarget;
    except
      on E: Exception do
        if WasCancelled then
          FError := 'Transfer cancelled, but partial target file was not deleted: ' +
            E.Message;
    end;
    if WasCancelled and (FError = '') then
      FError := 'Transfer cancelled';
  end;

  if FError = '' then
    StatusText := 'ok'
  else
    StatusText := 'error: ' + FError;
  if FTargetIsLocal then
    ModeText := 'download'
  else if FSourceIsLocal then
    ModeText := 'upload'
  else if TARGET_WRITE_MODE_SSH_EXEC then
    ModeText := 'ssh-exec'
  else
    ModeText := 'sftp';
  Summary(Format('transfer summary status=%s bytes=%d/%d elapsed=%dms ' +
    'read=%dms write=%dms pop_wait=%dms push_wait=%dms ' +
    'read_chunks=%d write_calls=%d ssh_eagain=%d ssh_eagain_wait=%dms ' +
    'ssh_eagain_max_streak=%d buffer=%d queue_limit=%d mode=%s source=%s target=%s',
    [StatusText, FDone, FTotal,
     TraceTick - TransferStarted, ReadMs, WriteMs, PopWaitMs, PushWaitMs,
     ReadChunks, WriteCalls, SshEagainCount, SshEagainWaitMs,
     SshMaxEagainStreak, STREAM_BUFFER_SIZE, PIPELINE_QUEUE_LIMIT,
     ModeText,
     IfThen(FSourceIsLocal, 'local', FSourceInfo.Host),
     IfThen(FTargetIsLocal, 'local', FTargetInfo.Host)]));

  Owner := FOwner;
  ErrorText := FError;
  TThread.Queue(nil,
    procedure
    begin
      if Owner <> nil then
        Owner.WorkerFinished(Self, ErrorText);
    end);
end;

{ TnbSFTPTransfer }

constructor TnbSFTPTransfer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FQueue := TQueue<TnbSFTPTransferJob>.Create;
end;

destructor TnbSFTPTransfer.Destroy;
begin
  ClearQueue;
  if FWorker <> nil then
  begin
    FWorker.FOwner := nil;
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FreeAndNil(FQueue);
  inherited;
end;

function TnbSFTPTransfer.Busy: Boolean;
begin
  Result := FWorker <> nil;
end;

function TnbSFTPTransfer.PendingCount: Integer;
begin
  if FQueue = nil then
    Result := 0
  else
    Result := FQueue.Count;
end;

procedure TnbSFTPTransfer.Cancel;
begin
  if FWorker <> nil then
    FWorker.Terminate;
end;

procedure TnbSFTPTransfer.ClearQueue;
begin
  if FQueue <> nil then
    FQueue.Clear;
end;

procedure TnbSFTPTransfer.Start(ASource: TnbSFTPClient;
  const ARemoteSrc: string; ATarget: TnbSFTPClient; const ADstPath: string);
var
  Job: TnbSFTPTransferJob;
begin
  if (ASource = nil) or (ATarget = nil) then Exit;

  ASource.ExportConnectionInfo(Job.SourceInfo);
  ATarget.ExportConnectionInfo(Job.TargetInfo);
  Job.SourcePath := ARemoteSrc;
  Job.TargetPath := ADstPath;

  if SameText(Job.SourceInfo.Host, Job.TargetInfo.Host) and
     SameText(Job.SourceInfo.Port, Job.TargetInfo.Port) and
     SameText(Job.SourceInfo.User, Job.TargetInfo.User) and
     SameText(ARemoteSrc, ADstPath) then
  begin
    if Assigned(FOnError) then
      FOnError(Self, 'Source and target are the same remote file');
    Exit;
  end;

  if Busy then
  begin
    FQueue.Enqueue(Job);
    Exit;
  end;

  StartJob(Job);
end;

procedure TnbSFTPTransfer.StartJob(const AJob: TnbSFTPTransferJob);
begin
  if AJob.SourceIsLocal then
    FPhase := tpUpload
  else if AJob.TargetIsLocal then
    FPhase := tpDownload
  else
    FPhase := tpStream;
  FWorker := TnbSFTPTransferWorker.Create(Self, AJob.SourceInfo, AJob.TargetInfo,
    AJob.SourcePath, AJob.TargetPath, AJob.SourceIsLocal, AJob.TargetIsLocal);
  FWorker.Start;
end;

procedure TnbSFTPTransfer.StartDownload(ASource: TnbSFTPClient;
  const ARemotePath, ALocalPath: string);
var
  Job: TnbSFTPTransferJob;
begin
  if ASource = nil then Exit;
  FillChar(Job, SizeOf(Job), 0);
  ASource.ExportConnectionInfo(Job.SourceInfo);
  Job.SourcePath := ARemotePath;
  Job.TargetPath := ALocalPath;
  Job.SourceIsLocal := False;
  Job.TargetIsLocal := True;
  if Busy then
    FQueue.Enqueue(Job)
  else
    StartJob(Job);
end;

procedure TnbSFTPTransfer.StartUpload(const ALocalPath: string;
  ATarget: TnbSFTPClient; const ARemotePath: string);
var
  Job: TnbSFTPTransferJob;
begin
  if ATarget = nil then Exit;
  FillChar(Job, SizeOf(Job), 0);
  Job.SourcePath := ALocalPath;
  ATarget.ExportConnectionInfo(Job.TargetInfo);
  Job.TargetPath := ARemotePath;
  Job.SourceIsLocal := True;
  Job.TargetIsLocal := False;
  if Busy then
    FQueue.Enqueue(Job)
  else
    StartJob(Job);
end;

procedure TnbSFTPTransfer.StartNextQueuedJob;
var
  Job: TnbSFTPTransferJob;
begin
  if (FWorker <> nil) or (FQueue = nil) or (FQueue.Count = 0) then Exit;
  Job := FQueue.Dequeue;
  StartJob(Job);
end;

procedure TnbSFTPTransfer.WorkerFinished(AWorker: TnbSFTPTransferWorker;
  const AError: string);
begin
  if AWorker <> FWorker then Exit;
  FWorker := nil;
  FPhase := tpIdle;

  try
    if AError <> '' then
    begin
      if Assigned(FOnError) then
        FOnError(Self, AError);
    end
    else if Assigned(FOnDone) then
      FOnDone(Self);
  finally
    TThread.Queue(nil,
      procedure
      begin
        AWorker.Free;
      end);
  end;
  StartNextQueuedJob;
end;

procedure TnbSFTPTransfer.WorkerProgress(ADone, ATotal: Int64);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FPhase, ADone, ATotal);
end;

end.
