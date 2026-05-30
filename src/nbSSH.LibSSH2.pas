unit nbSSH.LibSSH2;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs;

type
  PLIBSSH2_SESSION = type Pointer;
  PLIBSSH2_CHANNEL = type Pointer;

  ESSHLibError = class(Exception);

  Tlibssh2_init = function(flags: Integer): Integer; cdecl;
  Tlibssh2_exit = procedure; cdecl;
  Tlibssh2_version = function(required_version: Integer): PAnsiChar; cdecl;
  Tlibssh2_session_init_ex = function(myalloc, myfree, myrealloc,
    abstract: Pointer): PLIBSSH2_SESSION; cdecl;
  Tlibssh2_session_free = function(session: PLIBSSH2_SESSION): Integer; cdecl;
  Tlibssh2_session_handshake = function(session: PLIBSSH2_SESSION;
    sock: NativeInt): Integer; cdecl;
  Tlibssh2_hostkey_hash = function(session: PLIBSSH2_SESSION;
    hash_type: Integer): PAnsiChar; cdecl;
  Tlibssh2_session_disconnect_ex = function(session: PLIBSSH2_SESSION;
    reason: Integer; description: PAnsiChar; lang: PAnsiChar): Integer; cdecl;
  Tlibssh2_session_last_error = function(session: PLIBSSH2_SESSION;
    errmsg: PPAnsiChar; errmsg_len: PInteger; want_buf: Integer): Integer; cdecl;
  Tlibssh2_session_set_blocking = procedure(session: PLIBSSH2_SESSION;
    blocking: Integer); cdecl;
  Tlibssh2_session_supported_algs = function(session: PLIBSSH2_SESSION;
    method_type: Integer; algs: PPAnsiChar): Integer; cdecl;
  Tlibssh2_userauth_publickey_frommemory = function(session: PLIBSSH2_SESSION;
    username: PAnsiChar; username_len: NativeUInt;
    publickeydata: PAnsiChar; publickeydata_len: NativeUInt;
    privatekeydata: PAnsiChar; privatekeydata_len: NativeUInt;
    passphrase: PAnsiChar): Integer; cdecl;
  Tlibssh2_userauth_publickey_fromfile_ex = function(session: PLIBSSH2_SESSION;
    username: PAnsiChar; username_len: Cardinal;
    publickey: PAnsiChar; privatekey: PAnsiChar;
    passphrase: PAnsiChar): Integer; cdecl;
  Tlibssh2_userauth_password_ex = function(session: PLIBSSH2_SESSION;
    username: PAnsiChar; username_len: Cardinal;
    password: PAnsiChar; password_len: Cardinal;
    passwd_change_cb: Pointer): Integer; cdecl;
  Tlibssh2_channel_open_ex = function(session: PLIBSSH2_SESSION;
    channel_type: PAnsiChar; channel_type_len: Cardinal;
    window_size: Cardinal; packet_size: Cardinal;
    message: PAnsiChar; message_len: Cardinal): PLIBSSH2_CHANNEL; cdecl;
  Tlibssh2_channel_process_startup = function(channel: PLIBSSH2_CHANNEL;
    request: PAnsiChar; request_len: Cardinal;
    message: PAnsiChar; message_len: Cardinal): Integer; cdecl;
  Tlibssh2_channel_request_pty_ex = function(channel: PLIBSSH2_CHANNEL;
    term: PAnsiChar; term_len: Cardinal;
    modes: PAnsiChar; modes_len: Cardinal;
    width, height, width_px, height_px: Integer): Integer; cdecl;
  Tlibssh2_channel_request_pty_size_ex = function(channel: PLIBSSH2_CHANNEL;
    width, height, width_px, height_px: Integer): Integer; cdecl;
  Tlibssh2_channel_setenv_ex = function(channel: PLIBSSH2_CHANNEL;
    varname: PAnsiChar; varname_len: Cardinal;
    value: PAnsiChar; value_len: Cardinal): Integer; cdecl;
  Tlibssh2_channel_read_ex = function(channel: PLIBSSH2_CHANNEL;
    stream_id: Integer; buf: PAnsiChar; buflen: NativeUInt): NativeInt; cdecl;
  Tlibssh2_channel_write_ex = function(channel: PLIBSSH2_CHANNEL;
    stream_id: Integer; buf: PAnsiChar; buflen: NativeUInt): NativeInt; cdecl;
  Tlibssh2_channel_send_eof = function(channel: PLIBSSH2_CHANNEL): Integer; cdecl;
  Tlibssh2_channel_wait_closed = function(channel: PLIBSSH2_CHANNEL): Integer; cdecl;
  Tlibssh2_channel_get_exit_status = function(channel: PLIBSSH2_CHANNEL): Integer; cdecl;
  Tlibssh2_channel_close = function(channel: PLIBSSH2_CHANNEL): Integer; cdecl;
  Tlibssh2_channel_free = function(channel: PLIBSSH2_CHANNEL): Integer; cdecl;
  Tlibssh2_channel_eof = function(channel: PLIBSSH2_CHANNEL): Integer; cdecl;

const
  LIBSSH2_ERROR_EAGAIN = -37;
  LIBSSH2_METHOD_HOSTKEY = 1;
  LIBSSH2_CHANNEL_WINDOW_DEFAULT = 2 * 1024 * 1024;
  LIBSSH2_CHANNEL_PACKET_DEFAULT = 32768;
  LIBSSH2_DISCONNECT_BY_APPLICATION = 11;
  LIBSSH2_HOSTKEY_HASH_SHA256 = 3;
  HOSTKEY_HASH_SHA256_LEN = 32;

var
  ssh2_init: Tlibssh2_init = nil;
  ssh2_exit: Tlibssh2_exit = nil;
  ssh2_version: Tlibssh2_version = nil;
  ssh2_session_init_ex: Tlibssh2_session_init_ex = nil;
  ssh2_session_free: Tlibssh2_session_free = nil;
  ssh2_session_handshake: Tlibssh2_session_handshake = nil;
  ssh2_hostkey_hash: Tlibssh2_hostkey_hash = nil;
  ssh2_session_disconnect_ex: Tlibssh2_session_disconnect_ex = nil;
  ssh2_session_last_error: Tlibssh2_session_last_error = nil;
  ssh2_session_set_blocking: Tlibssh2_session_set_blocking = nil;
  ssh2_session_supported_algs: Tlibssh2_session_supported_algs = nil;
  ssh2_userauth_publickey_frommemory: Tlibssh2_userauth_publickey_frommemory = nil;
  ssh2_userauth_publickey_fromfile_ex: Tlibssh2_userauth_publickey_fromfile_ex = nil;
  ssh2_userauth_password_ex: Tlibssh2_userauth_password_ex = nil;
  ssh2_channel_open_ex: Tlibssh2_channel_open_ex = nil;
  ssh2_channel_process_startup: Tlibssh2_channel_process_startup = nil;
  ssh2_channel_request_pty_ex: Tlibssh2_channel_request_pty_ex = nil;
  ssh2_channel_request_pty_size_ex: Tlibssh2_channel_request_pty_size_ex = nil;
  ssh2_channel_setenv_ex: Tlibssh2_channel_setenv_ex = nil;
  ssh2_channel_read_ex: Tlibssh2_channel_read_ex = nil;
  ssh2_channel_write_ex: Tlibssh2_channel_write_ex = nil;
  ssh2_channel_send_eof: Tlibssh2_channel_send_eof = nil;
  ssh2_channel_wait_closed: Tlibssh2_channel_wait_closed = nil;
  ssh2_channel_get_exit_status: Tlibssh2_channel_get_exit_status = nil;
  ssh2_channel_close: Tlibssh2_channel_close = nil;
  ssh2_channel_free: Tlibssh2_channel_free = nil;
  ssh2_channel_eof: Tlibssh2_channel_eof = nil;

procedure EnsureLibLoaded;
procedure UnloadLib;
function LibSSH2_IsLoaded: Boolean;
function LibSSH2_Version: string;
function LibSSH2_LoadedFrom: string;
function LibSSH2_HasFromMemory: Boolean;
function LibSSH2_GetSupportedHostKeyAlgs: string;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}
{$IFDEF POSIX}
uses
  Posix.Dlfcn;
{$ENDIF}

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

var
  GLibLock: TCriticalSection = nil;
  GLibHandle: NativeUInt = 0;
  GLibLoadedFrom: string = '';
  GLibInited: Boolean = False;
  GSupportedHostKeyAlgs: string = '';
  GSupportedHostKeyAlgsLoaded: Boolean = False;

{$IFDEF MSWINDOWS}
function PlatformLoadLib(const Name: string): NativeUInt;
begin
  Result := SafeLoadLibrary(Name);
end;

function PlatformGetProc(LibHandle: NativeUInt; const Name: AnsiString): Pointer;
begin
  Result := GetProcAddress(LibHandle, PAnsiChar(Name));
end;

procedure PlatformFreeLib(LibHandle: NativeUInt);
begin
  if LibHandle <> 0 then
    FreeLibrary(LibHandle);
end;

function PlatformLibPath(LibHandle: NativeUInt): string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if LibHandle <> 0 then
    if GetModuleFileName(LibHandle, Buf, MAX_PATH) > 0 then
      Result := string(Buf);
end;
{$ENDIF}

{$IFDEF POSIX}
function PlatformLoadLib(const Name: string): NativeUInt;
begin
  Result := dlopen(MarshaledAString(UTF8String(Name)),
    RTLD_NOW or RTLD_GLOBAL);
end;

function PlatformGetProc(LibHandle: NativeUInt; const Name: AnsiString): Pointer;
begin
  Result := dlsym(LibHandle, MarshaledAString(Name));
end;

procedure PlatformFreeLib(LibHandle: NativeUInt);
begin
  if LibHandle <> 0 then
    dlclose(LibHandle);
end;

function PlatformLibPath(LibHandle: NativeUInt): string;
begin
  Result := GLibLoadedFrom;
end;
{$ENDIF}

function ResolveProc(const Name: AnsiString; Required: Boolean = True): Pointer;
begin
  Result := PlatformGetProc(GLibHandle, Name);
  if (Result = nil) and Required then
    raise ESSHLibError.CreateFmt(
      'libssh2 is missing required function: %s', [string(Name)]);
end;

procedure LoadAllProcs;
begin
  @ssh2_init                          := ResolveProc('libssh2_init');
  @ssh2_exit                          := ResolveProc('libssh2_exit');
  @ssh2_version                       := ResolveProc('libssh2_version');
  @ssh2_session_init_ex               := ResolveProc('libssh2_session_init_ex');
  @ssh2_session_free                  := ResolveProc('libssh2_session_free');
  @ssh2_session_handshake             := ResolveProc('libssh2_session_handshake');
  @ssh2_session_disconnect_ex         := ResolveProc('libssh2_session_disconnect_ex');
  @ssh2_session_last_error            := ResolveProc('libssh2_session_last_error');
  @ssh2_session_set_blocking          := ResolveProc('libssh2_session_set_blocking');
  @ssh2_session_supported_algs        := ResolveProc('libssh2_session_supported_algs');
  @ssh2_userauth_publickey_fromfile_ex:= ResolveProc('libssh2_userauth_publickey_fromfile_ex');
  @ssh2_userauth_password_ex          := ResolveProc('libssh2_userauth_password_ex');
  @ssh2_channel_open_ex               := ResolveProc('libssh2_channel_open_ex');
  @ssh2_channel_process_startup       := ResolveProc('libssh2_channel_process_startup');
  @ssh2_channel_request_pty_ex        := ResolveProc('libssh2_channel_request_pty_ex');
  @ssh2_channel_read_ex               := ResolveProc('libssh2_channel_read_ex');
  @ssh2_channel_write_ex              := ResolveProc('libssh2_channel_write_ex');
  @ssh2_channel_send_eof              := ResolveProc('libssh2_channel_send_eof');
  @ssh2_channel_wait_closed           := ResolveProc('libssh2_channel_wait_closed');
  @ssh2_channel_get_exit_status       := ResolveProc('libssh2_channel_get_exit_status');
  @ssh2_channel_close                 := ResolveProc('libssh2_channel_close');
  @ssh2_channel_free                  := ResolveProc('libssh2_channel_free');
  @ssh2_channel_eof                   := ResolveProc('libssh2_channel_eof');

  @ssh2_userauth_publickey_frommemory := ResolveProc('libssh2_userauth_publickey_frommemory', False);
  @ssh2_channel_request_pty_size_ex   := ResolveProc('libssh2_channel_request_pty_size_ex', False);
  @ssh2_channel_setenv_ex             := ResolveProc('libssh2_channel_setenv_ex', False);
  @ssh2_hostkey_hash                  := ResolveProc('libssh2_hostkey_hash', False);
end;

procedure EnsureLibLoaded;
var
  I: Integer;
  TriedNames: string;
begin
  if GLibInited then Exit;
  GLibLock.Enter;
  try
    if GLibInited then Exit;

    TriedNames := '';
    for I := Low(LIB_NAMES) to High(LIB_NAMES) do
    begin
      GLibHandle := PlatformLoadLib(LIB_NAMES[I]);
      if GLibHandle <> 0 then
      begin
        GLibLoadedFrom := LIB_NAMES[I];
        Break;
      end;
      if TriedNames <> '' then TriedNames := TriedNames + ', ';
      TriedNames := TriedNames + LIB_NAMES[I];
    end;

    if GLibHandle = 0 then
      raise ESSHLibError.CreateFmt(
        'Cannot load libssh2. Tried: %s.' + sLineBreak +
        'Windows: place libssh2.dll near the .exe.' + sLineBreak +
        'Linux:   sudo dnf install libssh2.' + sLineBreak +
        'macOS:   brew install libssh2.', [TriedNames]);

    try
      LoadAllProcs;
      if ssh2_init(0) <> 0 then
        raise ESSHLibError.Create('libssh2_init returned non-zero');
      GLibLoadedFrom := PlatformLibPath(GLibHandle);
      GLibInited := True;
    except
      PlatformFreeLib(GLibHandle);
      GLibHandle := 0;
      raise;
    end;
  finally
    GLibLock.Leave;
  end;
end;

procedure UnloadLib;
begin
  GLibLock.Enter;
  try
    if not GLibInited then Exit;
    if Assigned(ssh2_exit) then
      try ssh2_exit; except end;
    PlatformFreeLib(GLibHandle);
    GLibHandle := 0;
    GLibInited := False;
    GSupportedHostKeyAlgsLoaded := False;
    GSupportedHostKeyAlgs := '';
  finally
    GLibLock.Leave;
  end;
end;

function LibSSH2_IsLoaded: Boolean;
begin
  Result := GLibInited;
end;

function LibSSH2_Version: string;
begin
  if GLibInited and Assigned(ssh2_version) then
    Result := string(AnsiString(ssh2_version(0)))
  else
    Result := '';
end;

function LibSSH2_LoadedFrom: string;
begin
  Result := GLibLoadedFrom;
end;

function LibSSH2_HasFromMemory: Boolean;
begin
  Result := GLibInited and Assigned(ssh2_userauth_publickey_frommemory);
end;

function LibSSH2_GetSupportedHostKeyAlgs: string;
var
  Session: PLIBSSH2_SESSION;
  Algs: PPAnsiChar;
  Count, I: Integer;
  ArrPtr: PPAnsiChar;
begin
  if GSupportedHostKeyAlgsLoaded then
    Exit(GSupportedHostKeyAlgs);
  Result := '';
  try
    EnsureLibLoaded;
    Session := ssh2_session_init_ex(nil, nil, nil, nil);
    if Session = nil then
    begin
      GSupportedHostKeyAlgsLoaded := True;
      Exit;
    end;
    try
      Algs := nil;
      Count := ssh2_session_supported_algs(Session, LIBSSH2_METHOD_HOSTKEY, @Algs);
      if (Count > 0) and (Algs <> nil) then
      begin
        ArrPtr := Algs;
        for I := 0 to Count - 1 do
        begin
          if Result <> '' then Result := Result + ',';
          Result := Result + string(AnsiString(ArrPtr^));
          Inc(ArrPtr);
        end;
      end;
    finally
      ssh2_session_free(Session);
    end;
  except
    on E: Exception do
      Result := '';
  end;
  GSupportedHostKeyAlgs := Result;
  GSupportedHostKeyAlgsLoaded := True;
end;

initialization
  GLibLock := TCriticalSection.Create;

finalization
  UnloadLib;
  FreeAndNil(GLibLock);

end.
