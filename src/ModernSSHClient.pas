unit ModernSSHClient;

(*
  ModernSSHClient v5 - кросс-платформенный (Windows / Linux / macOS)

  Изменения по сравнению с v4:
    - TSSHShell упразднён, его API перенесён в TnbSSHClient:
        * OnReadData
        * WriteString
    - Добавлено свойство WakeOnConnect (по умолчанию True):
        после статуса Connected клиент сам шлёт #21 чтобы разбудить shell
        на серверах где bash не отдаёт первый prompt без ввода
    - Готов к привязке к контролу через property TerminalControl.SSHClient
*)

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, System.Generics.Collections,
  System.NetEncoding,
  blcksock, synsock, nbSSH.LibSSH2, nbSSH.KeyValidation;

type
  TSSHStatus = (ssIdle, ssConnecting, ssAuthenticating, ssConnected, ssError);
  TSSHStatusEvent = procedure(Sender: TObject; Status: TSSHStatus) of object;
  TSSHReadEvent = procedure(Sender: TObject; const Data: string) of object;
  TSSHCommandCompletedEvent = procedure(Sender: TObject;
    AExitStatus: Integer) of object;
  TSSHErrorEvent = procedure(Sender: TObject; const ErrorMessage: string) of object;
  (* Проверка ключа хоста. Fingerprint имеет вид 'SHA256:<base64>'.
     Accept на входе = True; если обработчик выставит False - соединение
     прерывается. Если обработчик не назначен, ключ принимается (как раньше). *)
  TSSHHostKeyEvent = procedure(Sender: TObject; const Host, Fingerprint: string;
    var Accept: Boolean) of object;
  PLIBSSH2_SESSION = nbSSH.LibSSH2.PLIBSSH2_SESSION;
  PLIBSSH2_CHANNEL = nbSSH.LibSSH2.PLIBSSH2_CHANNEL;
  ESSHLibError = nbSSH.LibSSH2.ESSHLibError;

  TSSHCommandKind = (sckWrite, sckResize);
  TSSHCommand = record
    Kind: TSSHCommandKind;
    StrPayload: string;
    IntA, IntB: Integer;
  end;

  TnbSSHClient = class;

  TSSHWorkerThread = class(TThread)
  private
    FOwner: TnbSSHClient;
    FSocket: TTCPBlockSocket;
    FSocketLock: TCriticalSection;
    FSession: PLIBSSH2_SESSION;
    FChannel: PLIBSSH2_CHANNEL;
    FCurrentReadData: string;
    FCurrentStatus: TSSHStatus;
    FCommandQueue: TList<TSSHCommand>;
    FCommandLock: TCriticalSection;
    FUtf8Tail: TBytes;
    FStdErrUtf8Tail: TBytes;
    FIsExecCommand: Boolean;
    FCommandEndedNormally: Boolean;
    FCommandOutputBytes: Int64;
    FCommandOutputBuilder: TStringBuilder;
    FCurrentFingerprint: string;
    FHostKeyAccepted: Boolean;
    FProbeRequested: Integer;
    procedure DoStatusChange;
    procedure DoSyncRead;
    procedure DoVerifyHostKey;
    function VerifyHostKey(out ErrorMsg: string): Boolean;
    procedure ProcessIncoming(const Bytes: TBytes; ByteCount: Integer;
      AStdErr: Boolean = False);
    procedure ProcessOutgoing;
    function ValidateKey(out ErrorMsg: string): Boolean;
    function GetLibLastError: string;
  protected
    procedure Execute; override;
    procedure DoTerminate; override;
  public
    constructor Create(AOwner: TnbSSHClient);
    destructor Destroy; override;
    procedure EnqueueCommand(const Cmd: TSSHCommand);
    procedure RequestProbe;
    procedure RequestStop;
  end;

  TnbSSHClient = class(TComponent)
  private
    FHost: string;
    FPort: string;
    FUser: string;
    FPassword: string;
    FKeyPath: string;
    FPassphrase: string;
    FKeyData: AnsiString;
    FPubKeyData: AnsiString;
    FInitialCols: Integer;
    FInitialRows: Integer;
    FConnectionTimeoutMs: Integer;
    FCommandTimeoutMs: Integer;
    FCommandOutputLimitBytes: Int64;
    FWorker: TSSHWorkerThread;
    FOnStatusChange: TSSHStatusEvent;
    FOnReadData: TSSHReadEvent;
    FStatus: TSSHStatus;
     FErrorMessage: string;
    FWakeOnConnect: Boolean;
    FExecCommand: string;
    FCommandOutput: string;
    FCommandExitStatus: Integer;
    FOnCommandCompleted: TSSHCommandCompletedEvent;
    FDisconnecting: Boolean;
    FOnConnecting: TNotifyEvent;
    FOnAuthenticating: TNotifyEvent;
    FOnConnected: TNotifyEvent;
    FOnDisconnected: TNotifyEvent;
    FOnError: TSSHErrorEvent;
    FOnVerifyHostKey: TSSHHostKeyEvent;
    procedure SetStatus(Value: TSSHStatus);
    procedure WorkerFinished;
    procedure DoCommandCompleted;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Connect;
    procedure ExecuteCommand(const ACommand: string);
    procedure RequestStop;
    procedure Disconnect;
    procedure ProbeConnection;

    (* Отправка строки в SSH-канал. Кодируется в UTF-8 внутри. *)
    procedure WriteString(const S: string);

    (* Изменение размера PTY. Можно вызывать в любой момент. *)
    procedure ResizePTY(Cols, Rows: Integer);

    (* Загрузка приватного ключа в память (для случаев из БД и т.п.) *)
    procedure SetPrivateKeyFromString(const APrivKeyPEM: AnsiString;
      const APubKey: AnsiString = '');
    procedure SetPrivateKeyFromBytes(const APrivKey: TBytes;
      const APubKey: TBytes = nil);
    procedure ClearPrivateKeyData;

    property Status: TSSHStatus read FStatus;
    property ErrorMessage: string read FErrorMessage;
    property CommandOutput: string read FCommandOutput;
    property CommandExitStatus: Integer read FCommandExitStatus;
  published
    property Host: string read FHost write FHost;
    property Port: string read FPort write FPort;
    property User: string read FUser write FUser;
    property Password: string read FPassword write FPassword;
    property KeyPath: string read FKeyPath write FKeyPath;
    property Passphrase: string read FPassphrase write FPassphrase;
    property InitialCols: Integer read FInitialCols write FInitialCols;
    property InitialRows: Integer read FInitialRows write FInitialRows;
    property ConnectionTimeoutMs: Integer read FConnectionTimeoutMs
      write FConnectionTimeoutMs default 10000;
    property CommandTimeoutMs: Integer read FCommandTimeoutMs
      write FCommandTimeoutMs default 0;
    property CommandOutputLimitBytes: Int64 read FCommandOutputLimitBytes
      write FCommandOutputLimitBytes default 16777216;

    (* Если True, после успешного коннекта в канал отправляется #21 (Ctrl+U)
       чтобы "разбудить" bash на серверах где первый prompt не показывается
       без ввода. На пустой command line это no-op, без видимых артефактов. *)
    property WakeOnConnect: Boolean read FWakeOnConnect write FWakeOnConnect default True;

    property OnStatusChange: TSSHStatusEvent read FOnStatusChange write FOnStatusChange;
    property OnReadData: TSSHReadEvent read FOnReadData write FOnReadData;
    property OnCommandCompleted: TSSHCommandCompletedEvent
      read FOnCommandCompleted write FOnCommandCompleted;
    property OnConnecting: TNotifyEvent read FOnConnecting write FOnConnecting;
    property OnAuthenticating: TNotifyEvent read FOnAuthenticating write FOnAuthenticating;
    property OnConnected: TNotifyEvent read FOnConnected write FOnConnected;
    property OnDisconnected: TNotifyEvent read FOnDisconnected write FOnDisconnected;
    property OnError: TSSHErrorEvent read FOnError write FOnError;

    (* Вызывается после SSH-рукопожатия с отпечатком ключа сервера.
       Позволяет реализовать проверку (known_hosts, доверие при первом
       подключении и т.п.). Если обработчик не назначен - ключ принимается. *)
    property OnVerifyHostKey: TSSHHostKeyEvent read FOnVerifyHostKey write FOnVerifyHostKey;
  end;

(* Отладочные хелперы *)
function SSHLib_IsLoaded: Boolean;
function SSHLib_Version: string;
function SSHLib_LoadedFrom: string;
function SSHLib_HasFromMemory: Boolean;

implementation

(* === Публичные хелперы === *)

function SSHLib_IsLoaded: Boolean;
begin
  Result := LibSSH2_IsLoaded;
end;

function SSHLib_Version: string;
begin
  Result := LibSSH2_Version;
end;

function SSHLib_LoadedFrom: string;
begin
  Result := LibSSH2_LoadedFrom;
end;

function SSHLib_HasFromMemory: Boolean;
begin
  Result := LibSSH2_HasFromMemory;
end;

(* === Утилиты === *)

procedure SecureZero(var S: AnsiString);
begin
  if Length(S) > 0 then
  begin
    UniqueString(S);
    FillChar(PAnsiChar(S)^, Length(S), 0);
  end;
  S := '';
end;

function FindUtf8SafeCutoff(const Bytes: TBytes; Count: Integer): Integer;
var
  i, NeedTail, LowBound: Integer;
  B: Byte;
begin
  Result := Count;
  if Count = 0 then Exit;

  LowBound := Count - 4;
  if LowBound < 0 then LowBound := 0;

  for i := Count - 1 downto LowBound do
  begin
    B := Bytes[i];
    if (B and $80) = 0 then
      Exit(Count)
    else if (B and $C0) = $C0 then
    begin
      if (B and $E0) = $C0 then NeedTail := 1
      else if (B and $F0) = $E0 then NeedTail := 2
      else if (B and $F8) = $F0 then NeedTail := 3
      else
        Exit(Count);

      if (Count - 1 - i) >= NeedTail then
        Exit(Count)
      else
        Exit(i);
    end;
  end;
  Result := Count;
end;

{ TSSHWorkerThread }

constructor TSSHWorkerThread.Create(AOwner: TnbSSHClient);
begin
  inherited Create(True);
  FOwner := AOwner;
  FCommandQueue := TList<TSSHCommand>.Create;
  FCommandLock := TCriticalSection.Create;
  FSocketLock := TCriticalSection.Create;
  SetLength(FUtf8Tail, 0);
  SetLength(FStdErrUtf8Tail, 0);
  FIsExecCommand := FOwner.FExecCommand <> '';
  if FIsExecCommand then
    FCommandOutputBuilder := TStringBuilder.Create;
  FreeOnTerminate := False;
end;

destructor TSSHWorkerThread.Destroy;
begin
  FCommandQueue.Free;
  FCommandLock.Free;
  FSocketLock.Free;
  FCommandOutputBuilder.Free;
  inherited;
end;

procedure TSSHWorkerThread.EnqueueCommand(const Cmd: TSSHCommand);
begin
  FCommandLock.Enter;
  try
    FCommandQueue.Add(Cmd);
  finally
    FCommandLock.Leave;
  end;
end;

procedure TSSHWorkerThread.RequestProbe;
begin
  TInterlocked.Exchange(FProbeRequested, 1);
end;

procedure TSSHWorkerThread.RequestStop;
begin
  Terminate;
  FSocketLock.Acquire;
  try
    if Assigned(FSocket) and (FSocket.Socket <> INVALID_SOCKET) then
      Synsock.Shutdown(FSocket.Socket, 2);
  finally
    FSocketLock.Release;
  end;
end;

procedure TSSHWorkerThread.DoStatusChange;
begin
  FOwner.SetStatus(FCurrentStatus);
end;

procedure TSSHWorkerThread.DoSyncRead;
begin
  if Assigned(FOwner.FOnReadData) then
    FOwner.FOnReadData(FOwner, FCurrentReadData);
end;

procedure TSSHWorkerThread.DoTerminate;
begin
  inherited;
  TThread.Queue(Self, FOwner.WorkerFinished);
end;

procedure TSSHWorkerThread.DoVerifyHostKey;
var
  Accept: Boolean;
begin
  Accept := True;
  if Assigned(FOwner.FOnVerifyHostKey) then
    FOwner.FOnVerifyHostKey(FOwner, FOwner.Host, FCurrentFingerprint, Accept);
  FHostKeyAccepted := Accept;
end;

function TSSHWorkerThread.VerifyHostKey(out ErrorMsg: string): Boolean;
var
  HashPtr: PAnsiChar;
  Raw: TBytes;
begin
  Result := True;
  ErrorMsg := '';
  FCurrentFingerprint := '';

  (* Обработчик не назначен - проверку не делаем (поведение как в v5) *)
  if not Assigned(FOwner.FOnVerifyHostKey) then Exit;

  if not Assigned(ssh2_hostkey_hash) then
  begin
    ErrorMsg := 'Host key verification requested, but libssh2_hostkey_hash ' +
                'is not available in current libssh2';
    Exit(False);
  end;

  HashPtr := ssh2_hostkey_hash(FSession, LIBSSH2_HOSTKEY_HASH_SHA256);
  if HashPtr = nil then
  begin
    ErrorMsg := 'Cannot obtain host key fingerprint';
    Exit(False);
  end;

  SetLength(Raw, HOSTKEY_HASH_SHA256_LEN);
  Move(HashPtr^, Raw[0], HOSTKEY_HASH_SHA256_LEN);
  FCurrentFingerprint := 'SHA256:' +
    TNetEncoding.Base64.EncodeBytesToString(Raw).TrimRight(['=']);

  FHostKeyAccepted := True;
  Synchronize(DoVerifyHostKey);

  if not FHostKeyAccepted then
  begin
    ErrorMsg := 'Host key rejected by application: ' + FCurrentFingerprint;
    Result := False;
  end;
end;

procedure TSSHWorkerThread.ProcessIncoming(const Bytes: TBytes;
  ByteCount: Integer; AStdErr: Boolean);
var
  Combined, PreviousTail: TBytes;
  CutAt, TailLen: Integer;
begin
  if ByteCount <= 0 then Exit;

  if FIsExecCommand then
  begin
    Inc(FCommandOutputBytes, ByteCount);
    if (FOwner.FCommandOutputLimitBytes > 0) and
      (FCommandOutputBytes > FOwner.FCommandOutputLimitBytes) then
    begin
      FOwner.FErrorMessage := Format(
        'SSH command output exceeded the %d-byte limit',
        [FOwner.FCommandOutputLimitBytes]);
      FCurrentStatus := ssError;
      Terminate;
      Exit;
    end;
  end;

  if AStdErr then
  begin
    PreviousTail := FStdErrUtf8Tail;
    SetLength(FStdErrUtf8Tail, 0);
  end
  else
  begin
    PreviousTail := FUtf8Tail;
    SetLength(FUtf8Tail, 0);
  end;

  if Length(PreviousTail) > 0 then
  begin
    SetLength(Combined, Length(PreviousTail) + ByteCount);
    Move(PreviousTail[0], Combined[0], Length(PreviousTail));
    Move(Bytes[0], Combined[Length(PreviousTail)], ByteCount);
  end
  else
  begin
    SetLength(Combined, ByteCount);
    Move(Bytes[0], Combined[0], ByteCount);
  end;

  CutAt := FindUtf8SafeCutoff(Combined, Length(Combined));
  TailLen := Length(Combined) - CutAt;

  if TailLen > 0 then
  begin
    if AStdErr then
    begin
      SetLength(FStdErrUtf8Tail, TailLen);
      Move(Combined[CutAt], FStdErrUtf8Tail[0], TailLen);
    end
    else
    begin
      SetLength(FUtf8Tail, TailLen);
      Move(Combined[CutAt], FUtf8Tail[0], TailLen);
    end;
  end;

  if CutAt > 0 then
  begin
    FCurrentReadData := TEncoding.UTF8.GetString(Combined, 0, CutAt);
    if FCurrentReadData <> '' then
      if FIsExecCommand then
        FCommandOutputBuilder.Append(FCurrentReadData)
      else
        Synchronize(DoSyncRead);
  end;
end;

procedure TSSHWorkerThread.ProcessOutgoing;
var
  i: Integer;
  Cmd: TSSHCommand;
  PendingCmds: TArray<TSSHCommand>;
  Bytes: TBytes;
  TotalSent: NativeInt;
  WriteLen: NativeInt;
  WriteStartTick: UInt64;
  WriteTimeoutMs: Cardinal;
begin
  FCommandLock.Enter;
  try
    if FCommandQueue.Count = 0 then Exit;
    PendingCmds := FCommandQueue.ToArray;
    FCommandQueue.Clear;
  finally
    FCommandLock.Leave;
  end;

  for i := 0 to High(PendingCmds) do
  begin
    if Terminated then Break;
    Cmd := PendingCmds[i];
    case Cmd.Kind of
      sckWrite:
        begin
          if Cmd.StrPayload = '' then Continue;
          Bytes := TEncoding.UTF8.GetBytes(Cmd.StrPayload);
          TotalSent := 0;
          WriteStartTick := TThread.GetTickCount64;
          if FOwner.ConnectionTimeoutMs > 0 then
            WriteTimeoutMs := FOwner.ConnectionTimeoutMs
          else
            WriteTimeoutMs := 10000;
          while (TotalSent < Length(Bytes)) and not Terminated do
          begin
            WriteLen := ssh2_channel_write_ex(FChannel, 0,
              PAnsiChar(@Bytes[0]) + TotalSent, Length(Bytes) - TotalSent);
            if WriteLen = LIBSSH2_ERROR_EAGAIN then
            begin
              if TThread.GetTickCount64 - WriteStartTick >= WriteTimeoutMs then
              begin
                FOwner.FErrorMessage := 'SSH write timed out';
                Terminate;
                Exit;
              end;
              Sleep(5);
              Continue;
            end;
            if WriteLen < 0 then
            begin
              FOwner.FErrorMessage := 'Write error: ' + GetLibLastError;
              Terminate;
              Exit;
            end;
            Inc(TotalSent, WriteLen);
          end;
        end;
      sckResize:
        begin
          if Assigned(ssh2_channel_request_pty_size_ex) then
            ssh2_channel_request_pty_size_ex(FChannel, Cmd.IntA, Cmd.IntB, 0, 0);
        end;
    end;
  end;
end;

function TSSHWorkerThread.GetLibLastError: string;
var
  ErrMsg: PAnsiChar;
  ErrLen, ErrCode: Integer;
begin
  Result := '';
  if (FSession = nil) or (not Assigned(ssh2_session_last_error)) then Exit;
  ErrMsg := nil;
  ErrLen := 0;
  ErrCode := ssh2_session_last_error(FSession, @ErrMsg, @ErrLen, 0);
  if (ErrMsg <> nil) and (ErrLen > 0) then
    Result := Format('[%d] %s', [ErrCode, string(AnsiString(ErrMsg))])
  else
    Result := Format('[%d] (no description)', [ErrCode]);
end;

function TSSHWorkerThread.ValidateKey(out ErrorMsg: string): Boolean;
var
  KeyText, PubText: string;
  L: TStringList;
begin
  Result := False;
  ErrorMsg := '';

  if Length(FOwner.FKeyData) > 0 then
  begin
    if not SSHLib_HasFromMemory then
    begin
      ErrorMsg := 'In-memory keys not supported by current libssh2 (missing ' +
                  'libssh2_userauth_publickey_frommemory). Update libssh2 or use KeyPath.';
      Exit;
    end;
    KeyText := string(FOwner.FKeyData);
    PubText := string(FOwner.FPubKeyData);
    Result := SSHValidatePrivateKeyContent(KeyText, PubText, ErrorMsg);
    Exit;
  end;

  if FOwner.KeyPath <> '' then
  begin
    if not FileExists(FOwner.KeyPath) then
    begin
      ErrorMsg := 'Key file not found: ' + FOwner.KeyPath;
      Exit;
    end;

    L := TStringList.Create;
    try
      try
        L.LoadFromFile(FOwner.KeyPath);
        KeyText := L.Text;
      except
        on E: Exception do
        begin
          ErrorMsg := 'Cannot read key file: ' + E.Message;
          Exit;
        end;
      end;
    finally
      L.Free;
    end;

    PubText := '';
    if FileExists(FOwner.KeyPath + '.pub') then
    begin
      L := TStringList.Create;
      try
        try
          L.LoadFromFile(FOwner.KeyPath + '.pub');
          PubText := L.Text;
        except
        end;
      finally
        L.Free;
      end;
    end;

    Result := SSHValidatePrivateKeyContent(KeyText, PubText, ErrorMsg);
    Exit;
  end;

  Result := True;
end;

procedure TSSHWorkerThread.Execute;
var
  Buf: TBytes;
  ReadLen: NativeInt;
  ReadErrLen: NativeInt;
  RC: Integer;
  KeyError: string;
  AnsiUser, AnsiPwd, AnsiPassphrase, AnsiKeyPath: AnsiString;
  PassphrasePtr: PAnsiChar;
  Cols, Rows: Integer;
  ReadAnything: Boolean;
  WakeCmd: TSSHCommand;
  KeepAliveRC, KeepAliveNext: Integer;
  NextKeepAliveTick: UInt64;
  KeepAliveBlockedSince: UInt64;
  KeepAliveTimeoutMs: Cardinal;
  CommandStartedAt: UInt64;
  Utf8ExecCommand: UTF8String;
  IsExecCommand: Boolean;
begin
  IsExecCommand := FIsExecCommand;
  FCommandEndedNormally := False;
  FCommandOutputBytes := 0;
  FOwner.FCommandExitStatus := -1;
  FSocket := nil;
  FSession := nil;
  FChannel := nil;
  SetLength(Buf, 32768);
  FCurrentStatus := ssConnecting;
  Synchronize(DoStatusChange);

  try
    try
      EnsureLibLoaded;
    except
      on E: Exception do
      begin
        FOwner.FErrorMessage := 'libssh2 load failed: ' + E.Message;
        FCurrentStatus := ssError;
        Synchronize(DoStatusChange);
        Exit;
      end;
    end;

    if not ValidateKey(KeyError) then
    begin
      FOwner.FErrorMessage := KeyError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    FSocket := TTCPBlockSocket.Create;
    if Terminated then
      Exit;
    if FOwner.ConnectionTimeoutMs > 0 then
    begin
      FSocket.ConnectionTimeout := FOwner.ConnectionTimeoutMs;
      FSocket.SetTimeout(FOwner.ConnectionTimeoutMs);
    end;
    FSocket.Connect(FOwner.Host, FOwner.Port);
    if Terminated then
      Exit;
    if FSocket.LastError <> 0 then
    begin
      FOwner.FErrorMessage := 'TCP connect failed: ' + FSocket.LastErrorDesc;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    FCurrentStatus := ssAuthenticating;
    Synchronize(DoStatusChange);

    FSession := ssh2_session_init_ex(nil, nil, nil, nil);
    if FSession = nil then
    begin
      FOwner.FErrorMessage := 'libssh2_session_init failed';
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    if FOwner.ConnectionTimeoutMs > 0 then
      ssh2_session_set_timeout(FSession, FOwner.ConnectionTimeoutMs);

    RC := ssh2_session_handshake(FSession, FSocket.Socket);
    if RC <> 0 then
    begin
      FOwner.FErrorMessage := 'SSH handshake failed: ' + GetLibLastError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    (* Проверка ключа хоста до аутентификации - чтобы не отдать
       пароль/ключ поддельному серверу *)
    if not VerifyHostKey(KeyError) then
    begin
      FOwner.FErrorMessage := KeyError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    AnsiUser := AnsiString(FOwner.User);
    AnsiPassphrase := AnsiString(FOwner.Passphrase);
    if AnsiPassphrase = '' then
      PassphrasePtr := nil
    else
      PassphrasePtr := PAnsiChar(AnsiPassphrase);

    if Length(FOwner.FKeyData) > 0 then
    begin
      RC := ssh2_userauth_publickey_frommemory(FSession,
        PAnsiChar(AnsiUser), Length(AnsiUser),
        PAnsiChar(FOwner.FPubKeyData), Length(FOwner.FPubKeyData),
        PAnsiChar(FOwner.FKeyData), Length(FOwner.FKeyData),
        PassphrasePtr);
    end
    else if FOwner.KeyPath <> '' then
    begin
      AnsiKeyPath := AnsiString(FOwner.KeyPath);
      RC := ssh2_userauth_publickey_fromfile_ex(FSession,
        PAnsiChar(AnsiUser), Length(AnsiUser),
        nil,
        PAnsiChar(AnsiKeyPath),
        PassphrasePtr);
    end
    else if FOwner.Password <> '' then
    begin
      AnsiPwd := AnsiString(FOwner.Password);
      RC := ssh2_userauth_password_ex(FSession,
        PAnsiChar(AnsiUser), Length(AnsiUser),
        PAnsiChar(AnsiPwd), Length(AnsiPwd),
        nil);
      SecureZero(AnsiPwd);
    end
    else
    begin
      FOwner.FErrorMessage := 'No authentication method (no key, no password)';
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    if RC <> 0 then
    begin
      FOwner.FErrorMessage := 'Authentication failed: ' + GetLibLastError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    FChannel := ssh2_channel_open_ex(FSession,
      'session', 7,
      LIBSSH2_CHANNEL_WINDOW_DEFAULT, LIBSSH2_CHANNEL_PACKET_DEFAULT,
      nil, 0);
    if FChannel = nil then
    begin
      FOwner.FErrorMessage := 'Channel open failed: ' + GetLibLastError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    if IsExecCommand then
    begin
      Utf8ExecCommand := UTF8String(FOwner.FExecCommand);
      RC := ssh2_channel_process_startup(FChannel, 'exec', 4,
        PAnsiChar(Utf8ExecCommand), Length(Utf8ExecCommand));
    end
    else
    begin
      Cols := FOwner.FInitialCols;
      Rows := FOwner.FInitialRows;
      if Cols <= 0 then Cols := 80;
      if Rows <= 0 then Rows := 24;

      RC := ssh2_channel_request_pty_ex(FChannel,
        'xterm-256color', 14,
        nil, 0,
        Cols, Rows, 0, 0);
      if RC = 0 then
      begin
        if Assigned(ssh2_channel_setenv_ex) then
          ssh2_channel_setenv_ex(FChannel, 'TERM', 4, 'xterm-256color', 14);
        RC := ssh2_channel_process_startup(FChannel, 'shell', 5, nil, 0);
      end;
    end;
    if RC <> 0 then
    begin
      if IsExecCommand then
        FOwner.FErrorMessage := 'Command start failed: ' + GetLibLastError
      else
        FOwner.FErrorMessage := 'Shell start failed: ' + GetLibLastError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    ssh2_session_set_blocking(FSession, 0);

    if Assigned(ssh2_keepalive_config) and Assigned(ssh2_keepalive_send) then
    begin
      ssh2_keepalive_config(FSession, 1, 10);
      NextKeepAliveTick := TThread.GetTickCount64 + 10000;
    end
    else
      NextKeepAliveTick := High(UInt64);

    KeepAliveBlockedSince := 0;
    if FOwner.ConnectionTimeoutMs > 0 then
      KeepAliveTimeoutMs := FOwner.ConnectionTimeoutMs
    else
      KeepAliveTimeoutMs := 10000;

    FCurrentStatus := ssConnected;
    Synchronize(DoStatusChange);
    CommandStartedAt := TThread.GetTickCount64;

    (* Будилка для bash на серверах где первый prompt не показывается *)
    if FOwner.WakeOnConnect and not IsExecCommand then
    begin
      WakeCmd.Kind := sckWrite;
      WakeCmd.StrPayload := #21;
      EnqueueCommand(WakeCmd);
    end;

    while not Terminated do
    begin
      if IsExecCommand and (FOwner.FCommandTimeoutMs > 0) and
        (TThread.GetTickCount64 - CommandStartedAt >=
          UInt64(FOwner.FCommandTimeoutMs)) then
      begin
        FOwner.FErrorMessage := Format('SSH command timed out after %d ms',
          [FOwner.FCommandTimeoutMs]);
        FCurrentStatus := ssError;
        Break;
      end;

      if TInterlocked.Exchange(FProbeRequested, 0) <> 0 then
        NextKeepAliveTick := 0;
      ReadAnything := False;
      repeat
        ReadLen := ssh2_channel_read_ex(FChannel, 0, PAnsiChar(@Buf[0]), Length(Buf));
        if ReadLen > 0 then
        begin
          ProcessIncoming(Buf, ReadLen);
          ReadAnything := True;
        end;
      until (ReadLen <= 0) or Terminated;

      if IsExecCommand and not Terminated then
      begin
        repeat
          ReadErrLen := ssh2_channel_read_ex(FChannel, 1,
            PAnsiChar(@Buf[0]), Length(Buf));
          if ReadErrLen > 0 then
          begin
            ProcessIncoming(Buf, ReadErrLen, True);
            ReadAnything := True;
          end;
        until (ReadErrLen <= 0) or Terminated;
        if (ReadErrLen < 0) and (ReadErrLen <> LIBSSH2_ERROR_EAGAIN) then
        begin
          if not Terminated then
          begin
            FOwner.FErrorMessage := 'SSH stderr read error: ' + GetLibLastError;
            FCurrentStatus := ssError;
          end;
          Break;
        end;
      end;

      if (ReadLen < 0) and (ReadLen <> LIBSSH2_ERROR_EAGAIN) then
      begin
        if not Terminated then
        begin
          FOwner.FErrorMessage := 'Read error: ' + GetLibLastError;
          FCurrentStatus := ssError;
        end;
        Break;
      end;

      if ssh2_channel_eof(FChannel) <> 0 then
      begin
        if IsExecCommand then
        begin
          RC := ssh2_channel_wait_closed(FChannel);
          if RC = 0 then
          begin
            FCommandEndedNormally := True;
            Break;
          end;
          if RC <> LIBSSH2_ERROR_EAGAIN then
          begin
            FOwner.FErrorMessage := 'SSH channel close failed: ' +
              GetLibLastError;
            FCurrentStatus := ssError;
            Break;
          end;
        end
        else
          Break;
      end;

      ProcessOutgoing;

      if TThread.GetTickCount64 >= NextKeepAliveTick then
      begin
        KeepAliveNext := 0;
        KeepAliveRC := ssh2_keepalive_send(FSession, @KeepAliveNext);
        if (KeepAliveRC <> 0) and (KeepAliveRC <> LIBSSH2_ERROR_EAGAIN) then
        begin
          FOwner.FErrorMessage := 'SSH keepalive failed: ' + GetLibLastError;
          FCurrentStatus := ssError;
          Break;
        end;
        if KeepAliveRC = LIBSSH2_ERROR_EAGAIN then
        begin
          if KeepAliveBlockedSince = 0 then
            KeepAliveBlockedSince := TThread.GetTickCount64
          else if TThread.GetTickCount64 - KeepAliveBlockedSince >=
            KeepAliveTimeoutMs then
          begin
            FOwner.FErrorMessage := 'SSH keepalive timed out';
            FCurrentStatus := ssError;
            Break;
          end;
        end
        else
          KeepAliveBlockedSince := 0;
        if KeepAliveNext <= 0 then
          KeepAliveNext := 1;
        NextKeepAliveTick := TThread.GetTickCount64 + UInt64(KeepAliveNext) * 1000;
      end;

      if not ReadAnything then
        Sleep(15);
    end;

  finally
    if IsExecCommand and FCommandEndedNormally and (FChannel <> nil) then
      FOwner.FCommandExitStatus := ssh2_channel_get_exit_status(FChannel);
    if FChannel <> nil then
    begin
      try ssh2_channel_close(FChannel); except end;
      try ssh2_channel_free(FChannel); except end;
      FChannel := nil;
    end;

    if FSession <> nil then
    begin
      try ssh2_session_disconnect_ex(FSession,
            LIBSSH2_DISCONNECT_BY_APPLICATION, 'bye', ''); except end;
      try ssh2_session_free(FSession); except end;
      FSession := nil;
    end;

    FSocketLock.Acquire;
    try
      FreeAndNil(FSocket);
    finally
      FSocketLock.Release;
    end;

    if FCurrentStatus = ssError then
      Synchronize(DoStatusChange);
    if IsExecCommand then
    begin
      FOwner.FCommandOutput := FCommandOutputBuilder.ToString;
      FOwner.FExecCommand := '';
    end;
  end;
end;

{ TnbSSHClient }

constructor TnbSSHClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStatus := ssIdle;
  FPort := '22';
  FInitialCols := 80;
  FInitialRows := 24;
  FConnectionTimeoutMs := 10000;
  FCommandTimeoutMs := 0;
  FCommandOutputLimitBytes := 16 * 1024 * 1024;
  FWakeOnConnect := True;
end;

destructor TnbSSHClient.Destroy;
begin
  FOnCommandCompleted := nil;
  Disconnect;
  ClearPrivateKeyData;
  inherited;
end;

procedure TnbSSHClient.SetStatus(Value: TSSHStatus);
var
  PrevStatus: TSSHStatus;
begin
  if FStatus = Value then Exit;

  PrevStatus := FStatus;
  FStatus := Value;

  (* Универсальное событие *)
  if Assigned(FOnStatusChange) then
    FOnStatusChange(Self, FStatus);

  (* Раздельные события *)
  case FStatus of
    ssConnecting:
      if Assigned(FOnConnecting) then
        FOnConnecting(Self);
    ssAuthenticating:
      if Assigned(FOnAuthenticating) then
        FOnAuthenticating(Self);
    ssConnected:
      if Assigned(FOnConnected) then
        FOnConnected(Self);
    ssError:
      if Assigned(FOnError) then
        FOnError(Self, FErrorMessage);
    ssIdle:
      (* OnDisconnected срабатывает только если до этого было реальное подключение,
         а не первый ssIdle при создании компонента *)
      if (PrevStatus in [ssConnected, ssAuthenticating]) and
         Assigned(FOnDisconnected) then
        FOnDisconnected(Self);
  end;
end;

procedure TnbSSHClient.DoCommandCompleted;
begin
  if Assigned(FOnCommandCompleted) then
    FOnCommandCompleted(Self, FCommandExitStatus);
end;

procedure TnbSSHClient.WorkerFinished;
var
  CompletedWorker: TSSHWorkerThread;
  WasExecCommand: Boolean;
begin
  if FDisconnecting or not Assigned(FWorker) then
    Exit;

  CompletedWorker := FWorker;
  WasExecCommand := CompletedWorker.FIsExecCommand;
  CompletedWorker.WaitFor;
  FWorker := nil;
  CompletedWorker.Free;

  SetStatus(ssIdle);
  if WasExecCommand then
    DoCommandCompleted;
end;

procedure TnbSSHClient.Connect;
begin
  if FStatus <> ssIdle then Exit;
  FErrorMessage := '';
  (* Подчищаем поток от предыдущего сеанса, если он завершился сам
     (сервер закрыл соединение). Без этого повторный Connect терял
     ссылку на старый объект потока. *)
  if Assigned(FWorker) then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FWorker := TSSHWorkerThread.Create(Self);
  FWorker.Start;
end;

procedure TnbSSHClient.ExecuteCommand(const ACommand: string);
begin
  if FStatus <> ssIdle then
    raise ESSHLibError.Create('SSH client is already busy.');
  if Trim(ACommand) = '' then
    raise EArgumentException.Create('SSH command is empty.');
  FExecCommand := ACommand;
  FCommandOutput := '';
  FCommandExitStatus := -1;
  Connect;
end;

procedure TnbSSHClient.Disconnect;
var
  StoppedWorker: TSSHWorkerThread;
  WasExecCommand: Boolean;
begin
  if Assigned(FWorker) then
  begin
    FDisconnecting := True;
    try
      StoppedWorker := FWorker;
      WasExecCommand := StoppedWorker.FIsExecCommand;
      StoppedWorker.RequestStop;
      if TThread.CurrentThread.ThreadID = MainThreadID then
        while not StoppedWorker.Finished do
        begin
          CheckSynchronize(10);
          Sleep(1);
        end;
      StoppedWorker.WaitFor;
      FWorker := nil;
      StoppedWorker.Free;
    finally
      FDisconnecting := False;
    end;
    SetStatus(ssIdle);
    if WasExecCommand then
      DoCommandCompleted;
  end;
end;

procedure TnbSSHClient.RequestStop;
begin
  if Assigned(FWorker) then
    FWorker.RequestStop;
end;

procedure TnbSSHClient.ProbeConnection;
begin
  if Assigned(FWorker) and (FStatus = ssConnected) then
    FWorker.RequestProbe;
end;

procedure TnbSSHClient.WriteString(const S: string);
var
  Cmd: TSSHCommand;
begin
  if S = '' then Exit;
  if not Assigned(FWorker) then Exit;
  if FStatus <> ssConnected then Exit;
  Cmd.Kind := sckWrite;
  Cmd.StrPayload := S;
  FWorker.EnqueueCommand(Cmd);
end;

procedure TnbSSHClient.ResizePTY(Cols, Rows: Integer);
var
  Cmd: TSSHCommand;
begin
  if (Cols <= 0) or (Rows <= 0) then Exit;
  FInitialCols := Cols;
  FInitialRows := Rows;
  if Assigned(FWorker) and (FStatus = ssConnected) then
  begin
    Cmd.Kind := sckResize;
    Cmd.IntA := Cols;
    Cmd.IntB := Rows;
    FWorker.EnqueueCommand(Cmd);
  end;
end;

procedure TnbSSHClient.SetPrivateKeyFromString(const APrivKeyPEM: AnsiString;
  const APubKey: AnsiString = '');
begin
  ClearPrivateKeyData;
  FKeyData := APrivKeyPEM;
  UniqueString(FKeyData);
  FPubKeyData := APubKey;
  if FPubKeyData <> '' then
    UniqueString(FPubKeyData);
end;

procedure TnbSSHClient.SetPrivateKeyFromBytes(const APrivKey: TBytes;
  const APubKey: TBytes = nil);
begin
  ClearPrivateKeyData;
  if Length(APrivKey) > 0 then
  begin
    SetLength(FKeyData, Length(APrivKey));
    Move(APrivKey[0], PAnsiChar(FKeyData)^, Length(APrivKey));
  end;
  if Length(APubKey) > 0 then
  begin
    SetLength(FPubKeyData, Length(APubKey));
    Move(APubKey[0], PAnsiChar(FPubKeyData)^, Length(APubKey));
  end;
end;

procedure TnbSSHClient.ClearPrivateKeyData;
begin
  SecureZero(FKeyData);
  SecureZero(FPubKeyData);
end;

end.
