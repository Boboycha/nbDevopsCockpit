unit nbSFTPTransfer;

(*
  TnbSFTPTransfer streams one remote SFTP file to another SFTP target.

  SFTP has no server-to-server copy primitive, so bytes still pass through this
  process. The file is no longer buffered as a full local temp file: the worker
  reads chunks from source and writes them to target.
*)

interface

uses
  System.Classes, System.SysUtils, System.IOUtils,
  nbSFTPClient;

type
  TnbTransferPhase = (tpIdle, tpDownload, tpUpload, tpStream,
    tpReadingSource, tpWritingTarget,
    tpClosingTarget, tpClosingSource, tpClosingSession);

  TnbTransferProgressEvent = procedure(Sender: TObject;
    APhase: TnbTransferPhase; ADone, ATotal: Int64) of object;
  TnbTransferErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;

  TnbSFTPTransfer = class;

  TnbSFTPTransferWorker = class(TThread)
  private
    FOwner: TnbSFTPTransfer;
    FSourceInfo: TnbSFTPConnectionInfo;
    FTargetInfo: TnbSFTPConnectionInfo;
    FSourcePath: string;
    FTargetPath: string;
    FError: string;
    FStage: TnbTransferPhase;
    FDone: Int64;
    FTotal: Int64;
    FLastProgressTick: UInt64;
    FTracePath: string;
    procedure Trace(const AMsg: string);
    procedure QueueProgress(AForce: Boolean = False);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TnbSFTPTransfer;
      const ASourceInfo, ATargetInfo: TnbSFTPConnectionInfo;
      const ASourcePath, ATargetPath: string);

    property Error: string read FError;
  end;

  TnbSFTPTransfer = class(TComponent)
  private
    FWorker: TnbSFTPTransferWorker;
    FPhase: TnbTransferPhase;
    FOnProgress: TnbTransferProgressEvent;
    FOnDone: TNotifyEvent;
    FOnError: TnbTransferErrorEvent;

    procedure WorkerFinished(AWorker: TnbSFTPTransferWorker;
      const AError: string);
    procedure WorkerProgress(ADone, ATotal: Int64);
  public
    destructor Destroy; override;

    function Busy: Boolean;

    (* Р—Р°РїСѓСЃС‚РёС‚СЊ РїРµСЂРµРґР°С‡Сѓ ARemoteSrc (РЅР° СЃРµСЂРІРµСЂРµ ASource) РІ ADstPath
       (РЅР° СЃРµСЂРІРµСЂРµ ATarget). РћР±Р° РїСѓС‚Рё вЂ” Р°Р±СЃРѕР»СЋС‚РЅС‹Рµ РїСѓС‚Рё РЅР° СЃРµСЂРІРµСЂР°С…. *)
    procedure Start(ASource: TnbSFTPClient; const ARemoteSrc: string;
      ATarget: TnbSFTPClient; const ADstPath: string);

    property OnProgress: TnbTransferProgressEvent read FOnProgress write FOnProgress;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
    property OnError: TnbTransferErrorEvent read FOnError write FOnError;
  end;

implementation

const
  STREAM_BUFFER_SIZE = 32 * 1024;

function TraceTick: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

{ TnbSFTPTransferWorker }

constructor TnbSFTPTransferWorker.Create(AOwner: TnbSFTPTransfer;
  const ASourceInfo, ATargetInfo: TnbSFTPConnectionInfo;
  const ASourcePath, ATargetPath: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FSourceInfo := ASourceInfo;
  FTargetInfo := ATargetInfo;
  FSourcePath := ASourcePath;
  FTargetPath := ATargetPath;
  FStage := tpStream;
end;

procedure TnbSFTPTransferWorker.Trace(const AMsg: string);
var
  Line: string;
begin
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
  SourceHandle, TargetHandle: PLIBSSH2_SFTP_HANDLE;
  Buffer: TBytes;
  ReadLen, WriteLen, Offset: NativeInt;
  OpStarted: UInt64;
  Owner: TnbSFTPTransfer;
  ErrorText: string;
begin
  SourceSession := nil;
  TargetSession := nil;
  SourceHandle := nil;
  TargetHandle := nil;
  try
    Trace(Format('start source=%s:%s %s %s target=%s:%s %s %s',
      [FSourceInfo.Host, FSourceInfo.Port, FSourceInfo.User, FSourcePath,
       FTargetInfo.Host, FTargetInfo.Port, FTargetInfo.User, FTargetPath]));

    SourceSession := TnbSFTPRawSession.Create(FSourceInfo,
      function: Boolean
      begin
        Result := Terminated;
      end, True);
    TargetSession := TnbSFTPRawSession.Create(FTargetInfo,
      function: Boolean
      begin
        Result := Terminated;
      end, True);
    Trace('connect source begin');
    OpStarted := TraceTick;
    SourceSession.Connect;
    Trace(Format('connect source end elapsed=%dms', [TraceTick - OpStarted]));

    Trace('connect target begin');
    OpStarted := TraceTick;
    TargetSession.Connect;
    Trace(Format('connect target end elapsed=%dms', [TraceTick - OpStarted]));

    Trace('stat source begin');
    OpStarted := TraceTick;
    FTotal := SourceSession.StatSize(FSourcePath);
    Trace(Format('stat source end size=%d elapsed=%dms',
      [FTotal, TraceTick - OpStarted]));

    Trace('open source begin');
    OpStarted := TraceTick;
    SourceHandle := SourceSession.OpenRead(FSourcePath);
    Trace(Format('open source end elapsed=%dms', [TraceTick - OpStarted]));

    Trace('open target begin');
    OpStarted := TraceTick;
    TargetHandle := TargetSession.OpenWrite(FTargetPath);
    Trace(Format('open target end elapsed=%dms', [TraceTick - OpStarted]));

    SetLength(Buffer, STREAM_BUFFER_SIZE);
    FDone := 0;
    QueueProgress(True);

    while not Terminated do
    begin
      if (FTotal > 0) and (FDone >= FTotal) then Break;

      FStage := tpReadingSource;
      QueueProgress(True);
      Trace(Format('read begin done=%d request=%d', [FDone, Length(Buffer)]));
      OpStarted := TraceTick;
      ReadLen := SourceSession.Read(SourceHandle, Buffer[0], Length(Buffer));
      Trace(Format('read end done=%d result=%d elapsed=%dms',
        [FDone, ReadLen, TraceTick - OpStarted]));
      if ReadLen = 0 then Break;

      Offset := 0;
      while (Offset < ReadLen) and not Terminated do
      begin
        FStage := tpWritingTarget;
        QueueProgress(True);
        Trace(Format('write begin done=%d offset=%d request=%d',
          [FDone, Offset, ReadLen - Offset]));
        OpStarted := TraceTick;
        WriteLen := TargetSession.Write(TargetHandle, Buffer[Offset],
          ReadLen - Offset);
        Trace(Format('write end done=%d offset=%d result=%d elapsed=%dms',
          [FDone, Offset, WriteLen, TraceTick - OpStarted]));
        if WriteLen = 0 then
          raise Exception.Create('Write target file failed: zero bytes written');
        Inc(Offset, WriteLen);
        Inc(FDone, WriteLen);
        FStage := tpStream;
        QueueProgress;
        if (FTotal > 0) and (FDone >= FTotal) then Break;
      end;
    end;
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

  if TargetSession <> nil then
  begin
    FStage := tpClosingTarget;
    QueueProgress(True);
    Trace('close target begin');
    OpStarted := TraceTick;
    TargetSession.CloseFile(TargetHandle);
    Trace(Format('close target end elapsed=%dms', [TraceTick - OpStarted]));
  end;
  if SourceSession <> nil then
  begin
    FStage := tpClosingSource;
    QueueProgress(True);
    Trace('close source begin');
    OpStarted := TraceTick;
    SourceSession.CloseFile(SourceHandle);
    Trace(Format('close source end elapsed=%dms', [TraceTick - OpStarted]));
  end;
  FStage := tpClosingSession;
  QueueProgress(True);
  Trace('abort sessions begin');
  if TargetSession <> nil then
  begin
    TargetSession.AbortDisconnect;
    FreeAndNil(TargetSession);
  end;
  if SourceSession <> nil then
  begin
    SourceSession.AbortDisconnect;
    FreeAndNil(SourceSession);
  end;
  Trace('abort sessions end');

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

destructor TnbSFTPTransfer.Destroy;
begin
  if FWorker <> nil then
  begin
    FWorker.FOwner := nil;
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  inherited;
end;

function TnbSFTPTransfer.Busy: Boolean;
begin
  Result := FWorker <> nil;
end;

procedure TnbSFTPTransfer.Start(ASource: TnbSFTPClient;
  const ARemoteSrc: string; ATarget: TnbSFTPClient; const ADstPath: string);
var
  SourceInfo, TargetInfo: TnbSFTPConnectionInfo;
begin
  if Busy then Exit;
  if (ASource = nil) or (ATarget = nil) then Exit;

  ASource.ExportConnectionInfo(SourceInfo);
  ATarget.ExportConnectionInfo(TargetInfo);

  if SameText(SourceInfo.Host, TargetInfo.Host) and
     SameText(SourceInfo.Port, TargetInfo.Port) and
     SameText(SourceInfo.User, TargetInfo.User) and
     SameText(ARemoteSrc, ADstPath) then
  begin
    if Assigned(FOnError) then
      FOnError(Self, 'Source and target are the same remote file');
    Exit;
  end;

  FPhase := tpStream;
  FWorker := TnbSFTPTransferWorker.Create(Self, SourceInfo, TargetInfo,
    ARemoteSrc, ADstPath);
  FWorker.Start;
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
end;

procedure TnbSFTPTransfer.WorkerProgress(ADone, ATotal: Int64);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FPhase, ADone, ATotal);
end;

end.
