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
  blcksock, nbSSH.LibSSH2, nbSSH.KeyValidation;

type
  TSSHStatus = (ssIdle, ssConnecting, ssAuthenticating, ssConnected, ssError);
  TSSHStatusEvent = procedure(Sender: TObject; Status: TSSHStatus) of object;
  TSSHReadEvent = procedure(Sender: TObject; const Data: string) of object;
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
    FSession: PLIBSSH2_SESSION;
    FChannel: PLIBSSH2_CHANNEL;
    FCurrentReadData: string;
    FCurrentStatus: TSSHStatus;
    FCommandQueue: TList<TSSHCommand>;
    FCommandLock: TCriticalSection;
    FUtf8Tail: TBytes;
    FCurrentFingerprint: string;
    FHostKeyAccepted: Boolean;
    procedure DoStatusChange;
    procedure DoSyncRead;
    procedure DoVerifyHostKey;
    function VerifyHostKey(out ErrorMsg: string): Boolean;
    procedure ProcessIncoming(const Bytes: TBytes; ByteCount: Integer);
    procedure ProcessOutgoing;
    function ValidateKey(out ErrorMsg: string): Boolean;
    function GetLibLastError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TnbSSHClient);
    destructor Destroy; override;
    procedure EnqueueCommand(const Cmd: TSSHCommand);
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
    FWorker: TSSHWorkerThread;
    FOnStatusChange: TSSHStatusEvent;
    FOnReadData: TSSHReadEvent;
    FStatus: TSSHStatus;
     FErrorMessage: string;
    FWakeOnConnect: Boolean;
    FOnConnecting: TNotifyEvent;
    FOnAuthenticating: TNotifyEvent;
    FOnConnected: TNotifyEvent;
    FOnDisconnected: TNotifyEvent;
    FOnError: TSSHErrorEvent;
    FOnVerifyHostKey: TSSHHostKeyEvent;
    procedure SetStatus(Value: TSSHStatus);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;

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

    (* Если True, после успешного коннекта в канал отправляется #21 (Ctrl+U)
       чтобы "разбудить" bash на серверах где первый prompt не показывается
       без ввода. На пустой command line это no-op, без видимых артефактов. *)
    property WakeOnConnect: Boolean read FWakeOnConnect write FWakeOnConnect default True;

    property OnStatusChange: TSSHStatusEvent read FOnStatusChange write FOnStatusChange;
    property OnReadData: TSSHReadEvent read FOnReadData write FOnReadData;
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
  SetLength(FUtf8Tail, 0);
  FreeOnTerminate := False;
end;

destructor TSSHWorkerThread.Destroy;
begin
  FCommandQueue.Free;
  FCommandLock.Free;
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

procedure TSSHWorkerThread.DoStatusChange;
begin
  FOwner.SetStatus(FCurrentStatus);
end;

procedure TSSHWorkerThread.DoSyncRead;
begin
  if Assigned(FOwner.FOnReadData) then
    FOwner.FOnReadData(FOwner, FCurrentReadData);
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

procedure TSSHWorkerThread.ProcessIncoming(const Bytes: TBytes; ByteCount: Integer);
var
  Combined: TBytes;
  CutAt, TailLen: Integer;
begin
  if ByteCount <= 0 then Exit;

  if Length(FUtf8Tail) > 0 then
  begin
    SetLength(Combined, Length(FUtf8Tail) + ByteCount);
    Move(FUtf8Tail[0], Combined[0], Length(FUtf8Tail));
    Move(Bytes[0], Combined[Length(FUtf8Tail)], ByteCount);
    SetLength(FUtf8Tail, 0);
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
    SetLength(FUtf8Tail, TailLen);
    Move(Combined[CutAt], FUtf8Tail[0], TailLen);
  end;

  if CutAt > 0 then
  begin
    FCurrentReadData := TEncoding.UTF8.GetString(Combined, 0, CutAt);
    if FCurrentReadData <> '' then
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
          while (TotalSent < Length(Bytes)) and not Terminated do
          begin
            WriteLen := ssh2_channel_write_ex(FChannel, 0,
              PAnsiChar(@Bytes[0]) + TotalSent, Length(Bytes) - TotalSent);
            if WriteLen = LIBSSH2_ERROR_EAGAIN then
            begin
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
  RC: Integer;
  KeyError: string;
  AnsiUser, AnsiPwd, AnsiPassphrase, AnsiKeyPath: AnsiString;
  PassphrasePtr: PAnsiChar;
  Cols, Rows: Integer;
  ReadAnything: Boolean;
  WakeCmd: TSSHCommand;
begin
  FCurrentStatus := ssConnecting;
  Synchronize(DoStatusChange);

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
  FSession := nil;
  FChannel := nil;
  SetLength(Buf, 32768);

  try
    if FOwner.ConnectionTimeoutMs > 0 then
      FSocket.ConnectionTimeout := FOwner.ConnectionTimeoutMs;
    FSocket.Connect(FOwner.Host, FOwner.Port);
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

    Cols := FOwner.FInitialCols;
    Rows := FOwner.FInitialRows;
    if Cols <= 0 then Cols := 80;
    if Rows <= 0 then Rows := 24;

    RC := ssh2_channel_request_pty_ex(FChannel,
      'xterm-256color', 14,
      nil, 0,
      Cols, Rows, 0, 0);
    if RC <> 0 then
    begin
      FOwner.FErrorMessage := 'PTY request failed: ' + GetLibLastError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    if Assigned(ssh2_channel_setenv_ex) then
      ssh2_channel_setenv_ex(FChannel, 'TERM', 4, 'xterm-256color', 14);

    RC := ssh2_channel_process_startup(FChannel, 'shell', 5, nil, 0);
    if RC <> 0 then
    begin
      FOwner.FErrorMessage := 'Shell start failed: ' + GetLibLastError;
      FCurrentStatus := ssError;
      Synchronize(DoStatusChange);
      Exit;
    end;

    ssh2_session_set_blocking(FSession, 0);

    FCurrentStatus := ssConnected;
    Synchronize(DoStatusChange);

    (* Будилка для bash на серверах где первый prompt не показывается *)
    if FOwner.WakeOnConnect then
    begin
      WakeCmd.Kind := sckWrite;
      WakeCmd.StrPayload := #21;
      EnqueueCommand(WakeCmd);
    end;

    while not Terminated do
    begin
      ReadAnything := False;
      repeat
        ReadLen := ssh2_channel_read_ex(FChannel, 0, PAnsiChar(@Buf[0]), Length(Buf));
        if ReadLen > 0 then
        begin
          ProcessIncoming(Buf, ReadLen);
          ReadAnything := True;
        end;
      until ReadLen <= 0;

      if (ReadLen < 0) and (ReadLen <> LIBSSH2_ERROR_EAGAIN) then
      begin
        FOwner.FErrorMessage := 'Read error: ' + GetLibLastError;
        Break;
      end;

      if ssh2_channel_eof(FChannel) <> 0 then
        Break;

      ProcessOutgoing;

      if not ReadAnything then
        Sleep(15);
    end;

  finally
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

    FSocket.Free;

    if FCurrentStatus = ssError then
      Synchronize(DoStatusChange);
    FCurrentStatus := ssIdle;
    Synchronize(DoStatusChange);
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
  FWakeOnConnect := True;
end;

destructor TnbSSHClient.Destroy;
begin
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
      if (PrevStatus in [ssConnected, ssAuthenticating, ssError]) and
         Assigned(FOnDisconnected) then
        FOnDisconnected(Self);
  end;
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

procedure TnbSSHClient.Disconnect;
begin
  if Assigned(FWorker) then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
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
