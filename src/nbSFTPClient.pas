unit nbSFTPClient;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, System.Generics.Collections,
  blcksock;

type
  PLIBSSH2_SESSION = type Pointer;
  PLIBSSH2_SFTP = type Pointer;
  PLIBSSH2_SFTP_HANDLE = type Pointer;

  TSFTPEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Permissions: Cardinal;
  end;

  TSFTPEntryArray = array of TSFTPEntry;

  TSFTPErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;
  TSFTPDirListingEvent = procedure(Sender: TObject; const APath: string;
    const AEntries: TSFTPEntryArray) of object;
  TSFTPProgressEvent = procedure(Sender: TObject; ADone, ATotal: Int64) of object;
  TSFTPTransferDoneEvent = procedure(Sender: TObject; const APath: string) of object;

  TnbSFTPClient = class;

  TSFTPCommandKind = (sckListDir, sckDownload, sckUpload, sckDelete, sckRemoveDir,
    sckMakeDir, sckRename);

  TSFTPCommand = record
    Kind: TSFTPCommandKind;
    Path1: string;
    Path2: string;
  end;

  TSFTPWorkerThread = class(TThread)
  private
    FOwner: TnbSFTPClient;
    FSocket: TTCPBlockSocket;
    FSession: PLIBSSH2_SESSION;
    FSFTP: PLIBSSH2_SFTP;
    FCommandQueue: TList<TSFTPCommand>;
    FCommandLock: TCriticalSection;
    FCurrentError: string;
    FCurrentPath: string;
    FCurrentEntries: TSFTPEntryArray;
    FCurrentDone: Int64;
    FCurrentTotal: Int64;
    procedure DoConnected;
    procedure DoDisconnected;
    procedure DoError;
    procedure DoDirListing;
    procedure DoProgress;
    procedure DoTransferDone;
    procedure DoOpDone;
    procedure EnqueueCommand(const ACmd: TSFTPCommand);
    function PopCommand(out ACmd: TSFTPCommand): Boolean;
    function GetSessionError: string;
    function WaitResult(const AFunc: TFunc<Integer>): Integer;
    function WaitPointer(const AFunc: TFunc<Pointer>): Pointer;
    function ConnectSession: Boolean;
    procedure CloseSession;
    procedure ProcessCommand(const ACmd: TSFTPCommand);
    procedure CmdListDir(const APath: string);
    procedure CmdDownload(const ARemotePath, ALocalPath: string);
    procedure CmdUpload(const ALocalPath, ARemotePath: string);
    procedure CmdDelete(const ARemotePath: string);
    procedure CmdRemoveDir(const ARemotePath: string);
    procedure CmdMakeDir(const ARemotePath: string);
    procedure CmdRename(const AOldPath, ANewPath: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TnbSFTPClient);
    destructor Destroy; override;
  end;

  TnbSFTPClient = class(TComponent)
  private
    FHost: string;
    FPort: string;
    FUser: string;
    FPassword: string;
    FPassphrase: string;
    FKeyData: AnsiString;
    FPubKeyData: AnsiString;
    FWorker: TSFTPWorkerThread;
    FOnConnected: TNotifyEvent;
    FOnDisconnected: TNotifyEvent;
    FOnError: TSFTPErrorEvent;
    FOnDirListing: TSFTPDirListingEvent;
    FOnProgress: TSFTPProgressEvent;
    FOnTransferDone: TSFTPTransferDoneEvent;
    FOnOpDone: TNotifyEvent;
    procedure QueueCommand(AKind: TSFTPCommandKind; const APath1: string;
      const APath2: string = '');
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;
    procedure SetPrivateKeyFromString(const APrivKeyPEM: AnsiString;
      const APubKey: AnsiString = '');
    procedure ClearPrivateKeyData;

    procedure ListDir(const APath: string);
    procedure Download(const ARemotePath, ALocalPath: string);
    procedure Upload(const ALocalPath, ARemotePath: string);
    procedure Delete(const ARemotePath: string);
    procedure RemoveDir(const ARemotePath: string);
    procedure MakeDir(const ARemotePath: string);
    procedure Rename(const AOldPath, ANewPath: string);

  published
    property Host: string read FHost write FHost;
    property Port: string read FPort write FPort;
    property User: string read FUser write FUser;
    property Password: string read FPassword write FPassword;
    property Passphrase: string read FPassphrase write FPassphrase;

    property OnConnected: TNotifyEvent read FOnConnected write FOnConnected;
    property OnDisconnected: TNotifyEvent read FOnDisconnected write FOnDisconnected;
    property OnError: TSFTPErrorEvent read FOnError write FOnError;
    property OnDirListing: TSFTPDirListingEvent read FOnDirListing write FOnDirListing;
    property OnProgress: TSFTPProgressEvent read FOnProgress write FOnProgress;
    property OnTransferDone: TSFTPTransferDoneEvent read FOnTransferDone write FOnTransferDone;
    property OnOpDone: TNotifyEvent read FOnOpDone write FOnOpDone;
  end;

implementation

uses
  System.DateUtils, System.IOUtils
{$IFDEF MSWINDOWS}
  , Winapi.Windows
{$ENDIF}
{$IFDEF POSIX}
  , Posix.Dlfcn
{$ENDIF}
  ;

const
  LIBSSH2_ERROR_EAGAIN = -37;
  LIBSSH2_DISCONNECT_BY_APPLICATION = 11;
  LIBSSH2_FXF_READ = $00000001;
  LIBSSH2_FXF_WRITE = $00000002;
  LIBSSH2_FXF_APPEND = $00000004;
  LIBSSH2_FXF_CREAT = $00000008;
  LIBSSH2_FXF_TRUNC = $00000010;
  LIBSSH2_FXF_EXCL = $00000020;
  LIBSSH2_SFTP_OPENFILE = 0;
  LIBSSH2_SFTP_OPENDIR = 2;
  LIBSSH2_SFTP_STAT = 0;
  LIBSSH2_SFTP_ATTR_SIZE = $00000001;
  LIBSSH2_SFTP_ATTR_PERMISSIONS = $00000004;
  LIBSSH2_SFTP_ATTR_ACMODTIME = $00000008;
  S_IFMT = $F000;
  S_IFDIR = $4000;

{$IFDEF MSWINDOWS}
const
  LIB_NAMES: array[0..0] of string = ('libssh2.dll');
{$ENDIF}
{$IFDEF LINUX}
const
  LIB_NAMES: array[0..2] of string = (
    'libssh2.so.1', 'libssh2.so', 'libssh2.so.1.0.1');
{$ENDIF}
{$IFDEF MACOS}
const
  LIB_NAMES: array[0..1] of string = (
    'libssh2.dylib', 'libssh2.1.dylib');
{$ENDIF}

type
  PLIBSSH2_SFTP_ATTRIBUTES = ^TLIBSSH2_SFTP_ATTRIBUTES;
  TLIBSSH2_SFTP_ATTRIBUTES = record
    flags: Cardinal;
    filesize: UInt64;
    uid: Cardinal;
    gid: Cardinal;
    permissions: Cardinal;
    atime: Cardinal;
    mtime: Cardinal;
  end;

  Tlibssh2_init = function(flags: Integer): Integer; cdecl;
  Tlibssh2_session_init_ex = function(myalloc, myfree, myrealloc,
    abstract: Pointer): PLIBSSH2_SESSION; cdecl;
  Tlibssh2_session_free = function(session: PLIBSSH2_SESSION): Integer; cdecl;
  Tlibssh2_session_handshake = function(session: PLIBSSH2_SESSION;
    sock: NativeInt): Integer; cdecl;
  Tlibssh2_session_disconnect_ex = function(session: PLIBSSH2_SESSION;
    reason: Integer; description: PAnsiChar; lang: PAnsiChar): Integer; cdecl;
  Tlibssh2_session_last_error = function(session: PLIBSSH2_SESSION;
    errmsg: PPAnsiChar; errmsg_len: PInteger; want_buf: Integer): Integer; cdecl;
  Tlibssh2_session_last_errno = function(session: PLIBSSH2_SESSION): Integer; cdecl;
  Tlibssh2_session_set_blocking = procedure(session: PLIBSSH2_SESSION;
    blocking: Integer); cdecl;
  Tlibssh2_userauth_publickey_frommemory = function(session: PLIBSSH2_SESSION;
    username: PAnsiChar; username_len: NativeUInt;
    publickeydata: PAnsiChar; publickeydata_len: NativeUInt;
    privatekeydata: PAnsiChar; privatekeydata_len: NativeUInt;
    passphrase: PAnsiChar): Integer; cdecl;
  Tlibssh2_userauth_password_ex = function(session: PLIBSSH2_SESSION;
    username: PAnsiChar; username_len: Cardinal;
    password: PAnsiChar; password_len: Cardinal;
    passwd_change_cb: Pointer): Integer; cdecl;
  Tlibssh2_sftp_init = function(session: PLIBSSH2_SESSION): PLIBSSH2_SFTP; cdecl;
  Tlibssh2_sftp_shutdown = function(sftp: PLIBSSH2_SFTP): Integer; cdecl;
  Tlibssh2_sftp_last_error = function(sftp: PLIBSSH2_SFTP): Cardinal; cdecl;
  Tlibssh2_sftp_open_ex = function(sftp: PLIBSSH2_SFTP; filename: PAnsiChar;
    filename_len: Cardinal; flags: Cardinal; mode: Integer;
    open_type: Integer): PLIBSSH2_SFTP_HANDLE; cdecl;
  Tlibssh2_sftp_close_handle = function(handle: PLIBSSH2_SFTP_HANDLE): Integer; cdecl;
  Tlibssh2_sftp_readdir_ex = function(handle: PLIBSSH2_SFTP_HANDLE;
    buffer: PAnsiChar; buffer_maxlen: NativeUInt; longentry: PAnsiChar;
    longentry_maxlen: NativeUInt; attrs: PLIBSSH2_SFTP_ATTRIBUTES): Integer; cdecl;
  Tlibssh2_sftp_read = function(handle: PLIBSSH2_SFTP_HANDLE; buffer: PAnsiChar;
    buffer_maxlen: NativeUInt): NativeInt; cdecl;
  Tlibssh2_sftp_write = function(handle: PLIBSSH2_SFTP_HANDLE; buffer: PAnsiChar;
    count: NativeUInt): NativeInt; cdecl;
  Tlibssh2_sftp_stat_ex = function(sftp: PLIBSSH2_SFTP; path: PAnsiChar;
    path_len: Cardinal; stat_type: Integer;
    attrs: PLIBSSH2_SFTP_ATTRIBUTES): Integer; cdecl;
  Tlibssh2_sftp_unlink_ex = function(sftp: PLIBSSH2_SFTP; filename: PAnsiChar;
    filename_len: Cardinal): Integer; cdecl;
  Tlibssh2_sftp_rename_ex = function(sftp: PLIBSSH2_SFTP; source: PAnsiChar;
    source_len: Cardinal; dest: PAnsiChar; dest_len: Cardinal;
    flags: Integer): Integer; cdecl;
  Tlibssh2_sftp_mkdir_ex = function(sftp: PLIBSSH2_SFTP; path: PAnsiChar;
    path_len: Cardinal; mode: Integer): Integer; cdecl;
  Tlibssh2_sftp_rmdir_ex = function(sftp: PLIBSSH2_SFTP; path: PAnsiChar;
    path_len: Cardinal): Integer; cdecl;

var
  GLibHandle: NativeUInt = 0;
  GLibInited: Boolean = False;
  GLibLock: TCriticalSection;
  ssh2_init: Tlibssh2_init;
  ssh2_session_init_ex: Tlibssh2_session_init_ex;
  ssh2_session_free: Tlibssh2_session_free;
  ssh2_session_handshake: Tlibssh2_session_handshake;
  ssh2_session_disconnect_ex: Tlibssh2_session_disconnect_ex;
  ssh2_session_last_error: Tlibssh2_session_last_error;
  ssh2_session_last_errno: Tlibssh2_session_last_errno;
  ssh2_session_set_blocking: Tlibssh2_session_set_blocking;
  ssh2_userauth_publickey_frommemory: Tlibssh2_userauth_publickey_frommemory;
  ssh2_userauth_password_ex: Tlibssh2_userauth_password_ex;
  ssh2_sftp_init: Tlibssh2_sftp_init;
  ssh2_sftp_shutdown: Tlibssh2_sftp_shutdown;
  ssh2_sftp_last_error: Tlibssh2_sftp_last_error;
  ssh2_sftp_open_ex: Tlibssh2_sftp_open_ex;
  ssh2_sftp_close_handle: Tlibssh2_sftp_close_handle;
  ssh2_sftp_readdir_ex: Tlibssh2_sftp_readdir_ex;
  ssh2_sftp_read: Tlibssh2_sftp_read;
  ssh2_sftp_write: Tlibssh2_sftp_write;
  ssh2_sftp_stat_ex: Tlibssh2_sftp_stat_ex;
  ssh2_sftp_unlink_ex: Tlibssh2_sftp_unlink_ex;
  ssh2_sftp_rename_ex: Tlibssh2_sftp_rename_ex;
  ssh2_sftp_mkdir_ex: Tlibssh2_sftp_mkdir_ex;
  ssh2_sftp_rmdir_ex: Tlibssh2_sftp_rmdir_ex;

{$IFDEF MSWINDOWS}
function PlatformLoadLib(const Name: string): NativeUInt;
begin
  Result := SafeLoadLibrary(Name);
end;

function PlatformGetProc(LibHandle: NativeUInt; const Name: AnsiString): Pointer;
begin
  Result := GetProcAddress(LibHandle, PAnsiChar(Name));
end;
{$ENDIF}

{$IFDEF POSIX}
function PlatformLoadLib(const Name: string): NativeUInt;
begin
  Result := dlopen(MarshaledAString(UTF8String(Name)), RTLD_NOW or RTLD_GLOBAL);
end;

function PlatformGetProc(LibHandle: NativeUInt; const Name: AnsiString): Pointer;
begin
  Result := dlsym(LibHandle, MarshaledAString(Name));
end;
{$ENDIF}

function ResolveProc(const Name: AnsiString): Pointer;
begin
  Result := PlatformGetProc(GLibHandle, Name);
  if Result = nil then
    raise Exception.CreateFmt('libssh2 is missing required function: %s', [string(Name)]);
end;

procedure EnsureSFTPLibLoaded;
var
  I: Integer;
begin
  if GLibInited then Exit;
  GLibLock.Enter;
  try
    if GLibInited then Exit;
    for I := Low(LIB_NAMES) to High(LIB_NAMES) do
    begin
      GLibHandle := PlatformLoadLib(LIB_NAMES[I]);
      if GLibHandle <> 0 then Break;
    end;
    if GLibHandle = 0 then
      raise Exception.Create('Unable to load libssh2');

    @ssh2_init := ResolveProc('libssh2_init');
    @ssh2_session_init_ex := ResolveProc('libssh2_session_init_ex');
    @ssh2_session_free := ResolveProc('libssh2_session_free');
    @ssh2_session_handshake := ResolveProc('libssh2_session_handshake');
    @ssh2_session_disconnect_ex := ResolveProc('libssh2_session_disconnect_ex');
    @ssh2_session_last_error := ResolveProc('libssh2_session_last_error');
    @ssh2_session_last_errno := ResolveProc('libssh2_session_last_errno');
    @ssh2_session_set_blocking := ResolveProc('libssh2_session_set_blocking');
    @ssh2_userauth_publickey_frommemory := ResolveProc('libssh2_userauth_publickey_frommemory');
    @ssh2_userauth_password_ex := ResolveProc('libssh2_userauth_password_ex');
    @ssh2_sftp_init := ResolveProc('libssh2_sftp_init');
    @ssh2_sftp_shutdown := ResolveProc('libssh2_sftp_shutdown');
    @ssh2_sftp_last_error := ResolveProc('libssh2_sftp_last_error');
    @ssh2_sftp_open_ex := ResolveProc('libssh2_sftp_open_ex');
    @ssh2_sftp_close_handle := ResolveProc('libssh2_sftp_close_handle');
    @ssh2_sftp_readdir_ex := ResolveProc('libssh2_sftp_readdir_ex');
    @ssh2_sftp_read := ResolveProc('libssh2_sftp_read');
    @ssh2_sftp_write := ResolveProc('libssh2_sftp_write');
    @ssh2_sftp_stat_ex := ResolveProc('libssh2_sftp_stat_ex');
    @ssh2_sftp_unlink_ex := ResolveProc('libssh2_sftp_unlink_ex');
    @ssh2_sftp_rename_ex := ResolveProc('libssh2_sftp_rename_ex');
    @ssh2_sftp_mkdir_ex := ResolveProc('libssh2_sftp_mkdir_ex');
    @ssh2_sftp_rmdir_ex := ResolveProc('libssh2_sftp_rmdir_ex');
    if ssh2_init(0) <> 0 then
      raise Exception.Create('libssh2_init failed');
    GLibInited := True;
  finally
    GLibLock.Leave;
  end;
end;

function ToUtf8Ansi(const S: string): AnsiString;
begin
  Result := AnsiString(UTF8String(S));
end;

function RemoteJoin(const ADir, AName: string): string;
begin
  if ADir = '' then Exit(AName);
  if ADir.EndsWith('/') then
    Result := ADir + AName
  else
    Result := ADir + '/' + AName;
end;

{ TSFTPWorkerThread }

constructor TSFTPWorkerThread.Create(AOwner: TnbSFTPClient);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FCommandQueue := TList<TSFTPCommand>.Create;
  FCommandLock := TCriticalSection.Create;
end;

destructor TSFTPWorkerThread.Destroy;
begin
  FCommandLock.Free;
  FCommandQueue.Free;
  inherited;
end;

procedure TSFTPWorkerThread.EnqueueCommand(const ACmd: TSFTPCommand);
begin
  FCommandLock.Enter;
  try
    FCommandQueue.Add(ACmd);
  finally
    FCommandLock.Leave;
  end;
end;

function TSFTPWorkerThread.PopCommand(out ACmd: TSFTPCommand): Boolean;
begin
  FCommandLock.Enter;
  try
    Result := FCommandQueue.Count > 0;
    if Result then
    begin
      ACmd := FCommandQueue[0];
      FCommandQueue.Delete(0);
    end;
  finally
    FCommandLock.Leave;
  end;
end;

procedure TSFTPWorkerThread.DoConnected;
begin
  if Assigned(FOwner.FOnConnected) then FOwner.FOnConnected(FOwner);
end;

procedure TSFTPWorkerThread.DoDisconnected;
begin
  if Assigned(FOwner.FOnDisconnected) then FOwner.FOnDisconnected(FOwner);
end;

procedure TSFTPWorkerThread.DoError;
begin
  if Assigned(FOwner.FOnError) then FOwner.FOnError(FOwner, FCurrentError);
end;

procedure TSFTPWorkerThread.DoDirListing;
begin
  if Assigned(FOwner.FOnDirListing) then
    FOwner.FOnDirListing(FOwner, FCurrentPath, FCurrentEntries);
end;

procedure TSFTPWorkerThread.DoProgress;
begin
  if Assigned(FOwner.FOnProgress) then
    FOwner.FOnProgress(FOwner, FCurrentDone, FCurrentTotal);
end;

procedure TSFTPWorkerThread.DoTransferDone;
begin
  if Assigned(FOwner.FOnTransferDone) then
    FOwner.FOnTransferDone(FOwner, FCurrentPath);
end;

procedure TSFTPWorkerThread.DoOpDone;
begin
  if Assigned(FOwner.FOnOpDone) then FOwner.FOnOpDone(FOwner);
end;

function TSFTPWorkerThread.GetSessionError: string;
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

function TSFTPWorkerThread.WaitResult(const AFunc: TFunc<Integer>): Integer;
begin
  repeat
    Result := AFunc();
    if Result <> LIBSSH2_ERROR_EAGAIN then Exit;
    Sleep(10);
  until Terminated;
end;

function TSFTPWorkerThread.WaitPointer(const AFunc: TFunc<Pointer>): Pointer;
begin
  repeat
    Result := AFunc();
    if Result <> nil then Exit;
    if (FSession = nil) or (ssh2_session_last_errno(FSession) <> LIBSSH2_ERROR_EAGAIN) then
      Exit;
    Sleep(10);
  until Terminated;
end;

function TSFTPWorkerThread.ConnectSession: Boolean;
var
  RC: Integer;
  AnsiUser, AnsiPwd, AnsiPassphrase: AnsiString;
  PassphrasePtr: PAnsiChar;
begin
  Result := False;
  EnsureSFTPLibLoaded;
  FSocket := TTCPBlockSocket.Create;
  FSocket.Connect(FOwner.Host, FOwner.Port);
  if FSocket.LastError <> 0 then
  begin
    FCurrentError := 'TCP connect failed: ' + FSocket.LastErrorDesc;
    Synchronize(DoError);
    Exit;
  end;

  FSession := ssh2_session_init_ex(nil, nil, nil, nil);
  if FSession = nil then
  begin
    FCurrentError := 'libssh2_session_init failed';
    Synchronize(DoError);
    Exit;
  end;

  RC := ssh2_session_handshake(FSession, FSocket.Socket);
  if RC <> 0 then
  begin
    FCurrentError := 'SSH handshake failed: ' + GetSessionError;
    Synchronize(DoError);
    Exit;
  end;

  AnsiUser := AnsiString(FOwner.User);
  AnsiPassphrase := AnsiString(FOwner.Passphrase);
  if AnsiPassphrase = '' then PassphrasePtr := nil
  else PassphrasePtr := PAnsiChar(AnsiPassphrase);

  if Length(FOwner.FKeyData) > 0 then
    RC := ssh2_userauth_publickey_frommemory(FSession,
      PAnsiChar(AnsiUser), Length(AnsiUser),
      PAnsiChar(FOwner.FPubKeyData), Length(FOwner.FPubKeyData),
      PAnsiChar(FOwner.FKeyData), Length(FOwner.FKeyData),
      PassphrasePtr)
  else if FOwner.Password <> '' then
  begin
    AnsiPwd := AnsiString(FOwner.Password);
    RC := ssh2_userauth_password_ex(FSession, PAnsiChar(AnsiUser),
      Length(AnsiUser), PAnsiChar(AnsiPwd), Length(AnsiPwd), nil);
  end
  else
  begin
    FCurrentError := 'No authentication method';
    Synchronize(DoError);
    Exit;
  end;

  if RC <> 0 then
  begin
    FCurrentError := 'Authentication failed: ' + GetSessionError;
    Synchronize(DoError);
    Exit;
  end;

  ssh2_session_set_blocking(FSession, 0);
  FSFTP := PLIBSSH2_SFTP(WaitPointer(
    function: Pointer
    begin
      Result := ssh2_sftp_init(FSession);
    end));
  if FSFTP = nil then
  begin
    FCurrentError := 'SFTP init failed: ' + GetSessionError;
    Synchronize(DoError);
    Exit;
  end;

  Result := True;
  Synchronize(DoConnected);
end;

procedure TSFTPWorkerThread.CloseSession;
begin
  if FSFTP <> nil then
  begin
    try ssh2_sftp_shutdown(FSFTP); except end;
    FSFTP := nil;
  end;
  if FSession <> nil then
  begin
    try ssh2_session_disconnect_ex(FSession, LIBSSH2_DISCONNECT_BY_APPLICATION,
      'bye', ''); except end;
    try ssh2_session_free(FSession); except end;
    FSession := nil;
  end;
  FreeAndNil(FSocket);
end;

procedure TSFTPWorkerThread.Execute;
var
  Cmd: TSFTPCommand;
begin
  try
    if not ConnectSession then Exit;
    while not Terminated do
    begin
      if PopCommand(Cmd) then
      begin
        try
          ProcessCommand(Cmd);
        except
          on E: Exception do
          begin
            FCurrentError := E.Message;
            Synchronize(DoError);
          end;
        end;
      end
      else
        Sleep(25);
    end;
  finally
    CloseSession;
    Synchronize(DoDisconnected);
  end;
end;

procedure TSFTPWorkerThread.ProcessCommand(const ACmd: TSFTPCommand);
begin
  case ACmd.Kind of
    sckListDir: CmdListDir(ACmd.Path1);
    sckDownload: CmdDownload(ACmd.Path1, ACmd.Path2);
    sckUpload: CmdUpload(ACmd.Path1, ACmd.Path2);
    sckDelete: CmdDelete(ACmd.Path1);
    sckRemoveDir: CmdRemoveDir(ACmd.Path1);
    sckMakeDir: CmdMakeDir(ACmd.Path1);
    sckRename: CmdRename(ACmd.Path1, ACmd.Path2);
  end;
end;

procedure TSFTPWorkerThread.CmdListDir(const APath: string);
var
  PathA, NameA: AnsiString;
  Handle: PLIBSSH2_SFTP_HANDLE;
  Buf, LongBuf: TBytes;
  Attrs: TLIBSSH2_SFTP_ATTRIBUTES;
  ReadLen: Integer;
  Entries: TList<TSFTPEntry>;
  Entry: TSFTPEntry;
begin
  PathA := ToUtf8Ansi(APath);
  Handle := PLIBSSH2_SFTP_HANDLE(WaitPointer(
    function: Pointer
    begin
      Result := ssh2_sftp_open_ex(FSFTP, PAnsiChar(PathA), Length(PathA),
        0, 0, LIBSSH2_SFTP_OPENDIR);
    end));
  if Handle = nil then
    raise Exception.Create('Open dir failed: ' + GetSessionError);

  SetLength(Buf, 1024);
  SetLength(LongBuf, 2048);
  Entries := TList<TSFTPEntry>.Create;
  try
    while not Terminated do
    begin
      FillChar(Attrs, SizeOf(Attrs), 0);
      ReadLen := WaitResult(
        function: Integer
        begin
          Result := ssh2_sftp_readdir_ex(Handle, PAnsiChar(@Buf[0]), Length(Buf),
            PAnsiChar(@LongBuf[0]), Length(LongBuf), @Attrs);
        end);
      if ReadLen = 0 then Break;
      if ReadLen < 0 then
        raise Exception.Create('Read dir failed: ' + GetSessionError);
      SetString(NameA, PAnsiChar(@Buf[0]), ReadLen);
      if (NameA = '.') or (NameA = '..') then Continue;
      Entry := Default(TSFTPEntry);
      Entry.Name := string(UTF8String(NameA));
      Entry.Size := Attrs.filesize;
      Entry.Permissions := Attrs.permissions;
      Entry.IsDir := (Attrs.permissions and S_IFMT) = S_IFDIR;
      if (Attrs.flags and LIBSSH2_SFTP_ATTR_ACMODTIME) <> 0 then
        Entry.Modified := UnixToDateTime(Attrs.mtime, False);
      Entries.Add(Entry);
    end;
    FCurrentPath := APath;
    SetLength(FCurrentEntries, Entries.Count);
    for ReadLen := 0 to Entries.Count - 1 do
      FCurrentEntries[ReadLen] := Entries[ReadLen];
    Synchronize(DoDirListing);
  finally
    Entries.Free;
    ssh2_sftp_close_handle(Handle);
  end;
end;

procedure TSFTPWorkerThread.CmdDownload(const ARemotePath, ALocalPath: string);
var
  PathA: AnsiString;
  Handle: PLIBSSH2_SFTP_HANDLE;
  Buf: TBytes;
  ReadLen: NativeInt;
  Stream: TFileStream;
  Attrs: TLIBSSH2_SFTP_ATTRIBUTES;
begin
  PathA := ToUtf8Ansi(ARemotePath);
  FillChar(Attrs, SizeOf(Attrs), 0);
  WaitResult(
    function: Integer
    begin
      Result := ssh2_sftp_stat_ex(FSFTP, PAnsiChar(PathA), Length(PathA),
        LIBSSH2_SFTP_STAT, @Attrs);
    end);
  Handle := PLIBSSH2_SFTP_HANDLE(WaitPointer(
    function: Pointer
    begin
      Result := ssh2_sftp_open_ex(FSFTP, PAnsiChar(PathA), Length(PathA),
        LIBSSH2_FXF_READ, 0, LIBSSH2_SFTP_OPENFILE);
    end));
  if Handle = nil then raise Exception.Create('Open remote file failed');

  TDirectory.CreateDirectory(TPath.GetDirectoryName(ALocalPath));
  Stream := TFileStream.Create(ALocalPath, fmCreate);
  try
    SetLength(Buf, 32768);
    FCurrentDone := 0;
    FCurrentTotal := Attrs.filesize;
    repeat
      ReadLen := WaitResult(
        function: Integer
        begin
          Result := ssh2_sftp_read(Handle, PAnsiChar(@Buf[0]), Length(Buf));
        end);
      if ReadLen > 0 then
      begin
        Stream.WriteBuffer(Buf[0], ReadLen);
        Inc(FCurrentDone, ReadLen);
        Synchronize(DoProgress);
      end;
    until (ReadLen <= 0) or Terminated;
    if ReadLen < 0 then raise Exception.Create('Download failed');
    FCurrentPath := ARemotePath;
    Synchronize(DoTransferDone);
  finally
    Stream.Free;
    ssh2_sftp_close_handle(Handle);
  end;
end;

procedure TSFTPWorkerThread.CmdUpload(const ALocalPath, ARemotePath: string);
var
  PathA: AnsiString;
  Handle: PLIBSSH2_SFTP_HANDLE;
  Buf: TBytes;
  ReadLen: Integer;
  WriteLen, Offset: NativeInt;
  Stream: TFileStream;
begin
  PathA := ToUtf8Ansi(ARemotePath);
  Handle := PLIBSSH2_SFTP_HANDLE(WaitPointer(
    function: Pointer
    begin
      Result := ssh2_sftp_open_ex(FSFTP, PAnsiChar(PathA), Length(PathA),
        LIBSSH2_FXF_WRITE or LIBSSH2_FXF_CREAT or LIBSSH2_FXF_TRUNC,
        $1A4, LIBSSH2_SFTP_OPENFILE);
    end));
  if Handle = nil then raise Exception.Create('Open remote file failed');

  Stream := TFileStream.Create(ALocalPath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Buf, 32768);
    FCurrentDone := 0;
    FCurrentTotal := Stream.Size;
    repeat
      ReadLen := Stream.Read(Buf[0], Length(Buf));
      Offset := 0;
      while (Offset < ReadLen) and not Terminated do
      begin
        WriteLen := WaitResult(
          function: Integer
          begin
            Result := ssh2_sftp_write(Handle, PAnsiChar(@Buf[Offset]),
              ReadLen - Offset);
          end);
        if WriteLen <= 0 then
        begin
          if Terminated then Break;
          raise Exception.Create('Upload failed');
        end;
        Inc(Offset, WriteLen);
        Inc(FCurrentDone, WriteLen);
        Synchronize(DoProgress);
      end;
    until (ReadLen = 0) or Terminated;
    FCurrentPath := ARemotePath;
    Synchronize(DoTransferDone);
  finally
    Stream.Free;
    ssh2_sftp_close_handle(Handle);
  end;
end;

procedure TSFTPWorkerThread.CmdDelete(const ARemotePath: string);
var
  PathA: AnsiString;
begin
  PathA := ToUtf8Ansi(ARemotePath);
  if WaitResult(
    function: Integer
    begin
      Result := ssh2_sftp_unlink_ex(FSFTP, PAnsiChar(PathA), Length(PathA));
    end) <> 0 then
    raise Exception.Create('Delete failed');
  Synchronize(DoOpDone);
end;

procedure TSFTPWorkerThread.CmdRemoveDir(const ARemotePath: string);
var
  PathA: AnsiString;
begin
  PathA := ToUtf8Ansi(ARemotePath);
  if WaitResult(
    function: Integer
    begin
      Result := ssh2_sftp_rmdir_ex(FSFTP, PAnsiChar(PathA), Length(PathA));
    end) <> 0 then
    raise Exception.Create('Remove dir failed');
  Synchronize(DoOpDone);
end;

procedure TSFTPWorkerThread.CmdMakeDir(const ARemotePath: string);
var
  PathA: AnsiString;
begin
  PathA := ToUtf8Ansi(ARemotePath);
  if WaitResult(
    function: Integer
    begin
      Result := ssh2_sftp_mkdir_ex(FSFTP, PAnsiChar(PathA), Length(PathA), $1ED);
    end) <> 0 then
    raise Exception.Create('Make dir failed');
  Synchronize(DoOpDone);
end;

procedure TSFTPWorkerThread.CmdRename(const AOldPath, ANewPath: string);
var
  OldA, NewA: AnsiString;
begin
  OldA := ToUtf8Ansi(AOldPath);
  NewA := ToUtf8Ansi(ANewPath);
  if WaitResult(
    function: Integer
    begin
      Result := ssh2_sftp_rename_ex(FSFTP, PAnsiChar(OldA), Length(OldA),
        PAnsiChar(NewA), Length(NewA), 0);
    end) <> 0 then
    raise Exception.Create('Rename failed');
  Synchronize(DoOpDone);
end;

{ TnbSFTPClient }

constructor TnbSFTPClient.Create(AOwner: TComponent);
begin
  inherited;
  FPort := '22';
end;

destructor TnbSFTPClient.Destroy;
begin
  Disconnect;
  inherited;
end;

procedure TnbSFTPClient.Connect;
begin
  Disconnect;
  FWorker := TSFTPWorkerThread.Create(Self);
  FWorker.Start;
end;

procedure TnbSFTPClient.Disconnect;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
end;

procedure TnbSFTPClient.SetPrivateKeyFromString(const APrivKeyPEM: AnsiString;
  const APubKey: AnsiString);
begin
  FKeyData := APrivKeyPEM;
  FPubKeyData := APubKey;
end;

procedure TnbSFTPClient.ClearPrivateKeyData;
begin
  FKeyData := '';
  FPubKeyData := '';
end;

procedure TnbSFTPClient.QueueCommand(AKind: TSFTPCommandKind; const APath1,
  APath2: string);
var
  Cmd: TSFTPCommand;
begin
  if FWorker = nil then Exit;
  Cmd.Kind := AKind;
  Cmd.Path1 := APath1;
  Cmd.Path2 := APath2;
  FWorker.EnqueueCommand(Cmd);
end;

procedure TnbSFTPClient.ListDir(const APath: string);
begin
  QueueCommand(sckListDir, APath);
end;

procedure TnbSFTPClient.Download(const ARemotePath, ALocalPath: string);
begin
  QueueCommand(sckDownload, ARemotePath, ALocalPath);
end;

procedure TnbSFTPClient.Upload(const ALocalPath, ARemotePath: string);
begin
  QueueCommand(sckUpload, ALocalPath, ARemotePath);
end;

procedure TnbSFTPClient.Delete(const ARemotePath: string);
begin
  QueueCommand(sckDelete, ARemotePath);
end;

procedure TnbSFTPClient.RemoveDir(const ARemotePath: string);
begin
  QueueCommand(sckRemoveDir, ARemotePath);
end;

procedure TnbSFTPClient.MakeDir(const ARemotePath: string);
begin
  QueueCommand(sckMakeDir, ARemotePath);
end;

procedure TnbSFTPClient.Rename(const AOldPath, ANewPath: string);
begin
  QueueCommand(sckRename, AOldPath, ANewPath);
end;

initialization
  GLibLock := TCriticalSection.Create;

finalization
  GLibLock.Free;

end.
