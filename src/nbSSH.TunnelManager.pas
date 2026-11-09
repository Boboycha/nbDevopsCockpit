unit nbSSH.TunnelManager;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, System.Generics.Collections,
  System.NetEncoding,
  blcksock, synsock, nbSSH.LibSSH2;

type
  TnbSSHBridgeRole = (sbrMaster, sbrReplica);
  TnbSSHBridgeStatus = (sbsStopped, sbsStarting, sbsListening, sbsActive,
    sbsReconnecting, sbsError);
  TnbSSHSessionOperationKind = (sokDirectOpen, sokChannelWrite,
    sokChannelEOF, sokChannelClose, sokKeepAlive);

  TnbSSHSessionOperationGate = class
  private
    FPending: Boolean;
    FOwner: Pointer;
    FKind: TnbSSHSessionOperationKind;
  public
    function TryEnter(AOwner: Pointer;
      AKind: TnbSSHSessionOperationKind): Boolean;
    procedure Complete(AOwner: Pointer; AKind: TnbSSHSessionOperationKind;
      AResult, AEAgain: NativeInt; APreserveOnEAgain: Boolean = True);
    procedure ReleaseOwner(AOwner: Pointer);
    procedure Reset;
    function IsPending: Boolean;
    function IsPendingFor(AOwner: Pointer;
      AKind: TnbSSHSessionOperationKind): Boolean;
  end;

  TnbSSHBridgeEndpoint = class(TPersistent)
  private
    FHost: string;
    FPort: Integer;
    FUser: string;
    FPassword: string;
    FKeyPath: string;
    FPassphrase: string;
    FPrivateKeyData: AnsiString;
    FPublicKeyData: AnsiString;
    FHostKeyFingerprint: string;
    FConnectionTimeoutMs: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure SetPrivateKeyFromString(const APrivateKey: AnsiString;
      const APublicKey: AnsiString = '');
    procedure ClearPrivateKeyData;
    procedure ClearSecrets;

    // Secret properties are intentionally not published into FMX resources.
    property Password: string read FPassword write FPassword;
    property Passphrase: string read FPassphrase write FPassphrase;
  published
    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort default 22;
    property User: string read FUser write FUser;
    property KeyPath: string read FKeyPath write FKeyPath;
    property HostKeyFingerprint: string read FHostKeyFingerprint
      write FHostKeyFingerprint;
    property ConnectionTimeoutMs: Integer read FConnectionTimeoutMs
      write FConnectionTimeoutMs default 10000;
  end;

  TnbSSHBridgeProfile = class(TPersistent)
  private
    FMaster: TnbSSHBridgeEndpoint;
    FReplica: TnbSSHBridgeEndpoint;
    FTargetHost: string;
    FTargetPort: Integer;
    FRemoteListenHost: string;
    FRemoteListenPort: Integer;
    FForwardQueueSize: Integer;
    FKeepAliveSeconds: Integer;
    FKeepAliveTimeoutMs: Integer;
    FReconnectMinMs: Integer;
    FReconnectMaxMs: Integer;
    FBufferSize: Integer;
    FIdleWaitMs: Integer;
    procedure SetMaster(const Value: TnbSSHBridgeEndpoint);
    procedure SetReplica(const Value: TnbSSHBridgeEndpoint);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Master: TnbSSHBridgeEndpoint read FMaster write SetMaster;
    property Replica: TnbSSHBridgeEndpoint read FReplica write SetReplica;
    property TargetHost: string read FTargetHost write FTargetHost;
    property TargetPort: Integer read FTargetPort write FTargetPort default 5432;
    property RemoteListenHost: string read FRemoteListenHost
      write FRemoteListenHost;
    property RemoteListenPort: Integer read FRemoteListenPort
      write FRemoteListenPort default 15432;
    property ForwardQueueSize: Integer read FForwardQueueSize
      write FForwardQueueSize default 16;
    property KeepAliveSeconds: Integer read FKeepAliveSeconds
      write FKeepAliveSeconds default 10;
    property KeepAliveTimeoutMs: Integer read FKeepAliveTimeoutMs
      write FKeepAliveTimeoutMs default 60000;
    property ReconnectMinMs: Integer read FReconnectMinMs
      write FReconnectMinMs default 1000;
    property ReconnectMaxMs: Integer read FReconnectMaxMs
      write FReconnectMaxMs default 30000;
    property BufferSize: Integer read FBufferSize write FBufferSize default 1048576;
    property IdleWaitMs: Integer read FIdleWaitMs write FIdleWaitMs default 1;
  end;

  TnbSSHBridgeStatusEvent = procedure(Sender: TObject;
    AStatus: TnbSSHBridgeStatus) of object;
  TnbSSHBridgeStatisticsEvent = procedure(Sender: TObject;
    AActiveChannels: Integer; ARxBytes, ATxBytes: Int64) of object;
  TnbSSHBridgeErrorEvent = procedure(Sender: TObject;
    const AMessage: string) of object;
  TnbSSHBridgeVerifyHostKeyEvent = procedure(Sender: TObject;
    ARole: TnbSSHBridgeRole; const AHost, AFingerprint: string;
    var AAccept: Boolean) of object;

  TnbSSHTunnelManager = class(TComponent)
  private
    FProfile: TnbSSHBridgeProfile;
    FWorker: TThread;
    FStatus: TnbSSHBridgeStatus;
    FMasterConnected: Boolean;
    FReplicaConnected: Boolean;
    FActiveChannels: Integer;
    FRxBytes: Int64;
    FTxBytes: Int64;
    FConnectedSinceTick: UInt64;
    FLastError: string;
    FChannelDiagnostics: string;
    FOnStatusChange: TnbSSHBridgeStatusEvent;
    FOnStatistics: TnbSSHBridgeStatisticsEvent;
    FOnError: TnbSSHBridgeErrorEvent;
    FOnVerifyHostKey: TnbSSHBridgeVerifyHostKeyEvent;
    procedure SetProfile(const Value: TnbSSHBridgeProfile);
    procedure ApplyWorkerUpdate(AWorker: TObject);
    function VerifyHostKey(ARole: TnbSSHBridgeRole; const AHost,
      AFingerprint: string): Boolean;
    procedure ValidateProfile;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Status: TnbSSHBridgeStatus read FStatus;
    property MasterConnected: Boolean read FMasterConnected;
    property ReplicaConnected: Boolean read FReplicaConnected;
    property ActiveChannels: Integer read FActiveChannels;
    property RxBytes: Int64 read FRxBytes;
    property TxBytes: Int64 read FTxBytes;
    property ConnectedSinceTick: UInt64 read FConnectedSinceTick;
    property LastError: string read FLastError;
    property ChannelDiagnostics: string read FChannelDiagnostics;
  published
    property Profile: TnbSSHBridgeProfile read FProfile write SetProfile;
    property OnStatusChange: TnbSSHBridgeStatusEvent read FOnStatusChange
      write FOnStatusChange;
    property OnStatistics: TnbSSHBridgeStatisticsEvent read FOnStatistics
      write FOnStatistics;
    property OnError: TnbSSHBridgeErrorEvent read FOnError write FOnError;
    property OnVerifyHostKey: TnbSSHBridgeVerifyHostKeyEvent
      read FOnVerifyHostKey write FOnVerifyHostKey;
  end;

function SSHBridgeStatusToString(AStatus: TnbSSHBridgeStatus): string;

implementation

{$IF Defined(MSWINDOWS)}
uses
  Winapi.WinSock2;
{$ENDIF}

type
  ESSHBridgeSessionError = class(ESSHLibError);

  TnbSSHBridgeWorker = class;

  TnbSSHBridgeSession = class
  private
    FWorker: TnbSSHBridgeWorker;
    FRole: TnbSSHBridgeRole;
    FEndpoint: TnbSSHBridgeEndpoint;
    FSocket: TTCPBlockSocket;
    FSocketLock: TCriticalSection;
    FSession: PLIBSSH2_SESSION;
    FOperationGate: TnbSSHSessionOperationGate;
    FKeepAliveSecondsToNext: Integer;
    function GetLastError: string;
    function GetLastErrorCode: Integer;
    function DescribeTransportError(AResult: NativeInt): string;
    function Fingerprint: string;
    procedure Authenticate;
  public
    constructor Create(AWorker: TnbSSHBridgeWorker; ARole: TnbSSHBridgeRole;
      AEndpoint: TnbSSHBridgeEndpoint);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    procedure Interrupt;
    procedure SetNonBlocking;
    procedure SetBlocking(ATimeoutMs: Integer);
    function TryOperation(AOwner: Pointer;
      AKind: TnbSSHSessionOperationKind): Boolean;
    procedure CompleteOperation(AOwner: Pointer;
      AKind: TnbSSHSessionOperationKind; AResult: NativeInt;
      APreserveOnEAgain: Boolean = True);
    procedure ReleaseOperationOwner(AOwner: Pointer);
    function CanRunUntrackedOperation: Boolean;
    function TryKeepAlive(AOwner: Pointer; out AResult: Integer): Boolean;
    property Session: PLIBSSH2_SESSION read FSession;
  end;

  TnbSSHBridgeChannelPair = class
  private
    FReplicaChannel: PLIBSSH2_CHANNEL;
    FMasterChannel: PLIBSSH2_CHANNEL;
    FReplicaSession: TnbSSHBridgeSession;
    FMasterSession: TnbSSHBridgeSession;
    FReplicaToMaster: TBytes;
    FMasterToReplica: TBytes;
    FReplicaToMasterOffset: Integer;
    FMasterToReplicaOffset: Integer;
    FReplicaToMasterCount: Integer;
    FMasterToReplicaCount: Integer;
    FReplicaEOF: Boolean;
    FMasterEOF: Boolean;
    FReplicaEOFSent: Boolean;
    FMasterEOFSent: Boolean;
    FReplicaClosed: Boolean;
    FMasterClosed: Boolean;
    FId: Integer;
    FCreatedTick: UInt64;
    FLastProgressTick: UInt64;
    FFirstEOFTick: UInt64;
    FReplicaToMasterBytes: Int64;
    FMasterToReplicaBytes: Int64;
    FReplicaReadResult: NativeInt;
    FMasterReadResult: NativeInt;
    FReplicaWriteResult: NativeInt;
    FMasterWriteResult: NativeInt;
    procedure CloseChannel(var AChannel: PLIBSSH2_CHANNEL;
      AAlreadyClosed: Boolean);
    function PumpDirection(ASource, ADestination: PLIBSSH2_CHANNEL;
      ASourceSession, ADestinationSession: TnbSSHBridgeSession;
      const ASourceName, ADestinationName: string;
      var ABuffer: TBytes; var AOffset, ACount: Integer; var ASourceEOF,
      ADestinationEOFSent: Boolean; ABufferSize: Integer;
      out ATransferred: Int64): Boolean;
  public
    constructor Create(AId: Integer; AReplicaSession,
      AMasterSession: TnbSSHBridgeSession; AReplicaChannel,
      AMasterChannel: PLIBSSH2_CHANNEL);
    destructor Destroy; override;
    function Pump(ABufferSize: Integer; out ARxBytes,
      ATxBytes: Int64): Boolean;
    function Finished: Boolean;
    function EOFDrainTimedOut(ATimeoutMs: UInt64): Boolean;
    function DiagnosticText: string;
  end;

  TnbSSHBridgeWorker = class(TThread)
  private
    FOwner: TnbSSHTunnelManager;
    FProfile: TnbSSHBridgeProfile;
    FMaster: TnbSSHBridgeSession;
    FReplica: TnbSSHBridgeSession;
    FListener: PLIBSSH2_LISTENER;
    FPendingReplicaChannel: PLIBSSH2_CHANNEL;
    FChannels: TObjectList<TnbSSHBridgeChannelPair>;
    FStateLock: TCriticalSection;
    FStatus: TnbSSHBridgeStatus;
    FMasterConnected: Boolean;
    FReplicaConnected: Boolean;
    FActiveChannels: Integer;
    FRxBytes: Int64;
    FTxBytes: Int64;
    FConnectedSinceTick: UInt64;
    FLastError: string;
    FChannelDiagnostics: string;
    FNextChannelId: Integer;
    FUpdateQueued: Integer;
    FVerifyRole: TnbSSHBridgeRole;
    FVerifyHost: string;
    FVerifyFingerprint: string;
    FVerifyAccepted: Boolean;
    procedure QueueUpdate;
    procedure DeliverUpdate;
    procedure DoVerifyHostKey;
    function VerifyHostKey(ARole: TnbSSHBridgeRole; const AHost,
      AFingerprint: string): Boolean;
    procedure SetStatus(AStatus: TnbSSHBridgeStatus;
      const AError: string = '');
    procedure SetConnections(AMaster, AReplica: Boolean);
    procedure UpdateStatistics;
    procedure UpdateChannelDiagnostics;
    procedure CloseForwarding;
    procedure ConnectAndListen;
    procedure RunForwarding;
    function WaitForReconnect(ADelayMs: Integer): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TnbSSHTunnelManager;
      AProfile: TnbSSHBridgeProfile);
    destructor Destroy; override;
    procedure RequestStop;
    procedure Snapshot(out AStatus: TnbSSHBridgeStatus;
      out AMasterConnected, AReplicaConnected: Boolean;
      out AActiveChannels: Integer; out ARxBytes, ATxBytes: Int64;
      out AConnectedSinceTick: UInt64; out ALastError,
      AChannelDiagnostics: string);
  end;

procedure SecureZeroAnsi(var AValue: AnsiString);
begin
  if Length(AValue) > 0 then
  begin
    AValue := Copy(AValue, 1, Length(AValue));
    FillChar(PAnsiChar(AValue)^, Length(AValue), 0);
  end;
  AValue := '';
end;

function IsSSHSessionError(AErrorCode: Integer): Boolean;
begin
  Result := (AErrorCode = LIBSSH2_ERROR_SOCKET_SEND) or
    (AErrorCode = LIBSSH2_ERROR_SOCKET_DISCONNECT) or
    (AErrorCode = LIBSSH2_ERROR_SOCKET_TIMEOUT) or
    (AErrorCode = LIBSSH2_ERROR_SOCKET_RECV) or
    (AErrorCode = LIBSSH2_ERROR_BAD_SOCKET);
end;

procedure SecureZeroString(var AValue: string);
begin
  if Length(AValue) > 0 then
  begin
    UniqueString(AValue);
    FillChar(PChar(AValue)^, Length(AValue) * SizeOf(Char), 0);
  end;
  AValue := '';
end;

procedure SecureZeroUTF8(var AValue: UTF8String);
begin
  if Length(AValue) > 0 then
  begin
    AValue := Copy(AValue, 1, Length(AValue));
    FillChar(PAnsiChar(AValue)^, Length(AValue), 0);
  end;
  AValue := '';
end;

function SSHBridgeStatusToString(AStatus: TnbSSHBridgeStatus): string;
begin
  case AStatus of
    sbsStopped: Result := 'Stopped';
    sbsStarting: Result := 'Starting';
    sbsListening: Result := 'Listening';
    sbsActive: Result := 'Active';
    sbsReconnecting: Result := 'Reconnecting';
    sbsError: Result := 'Error';
  else
    Result := 'Unknown';
  end;
end;

{ TnbSSHSessionOperationGate }

function TnbSSHSessionOperationGate.TryEnter(AOwner: Pointer;
  AKind: TnbSSHSessionOperationKind): Boolean;
begin
  Result := not FPending or ((FOwner = AOwner) and (FKind = AKind));
end;

procedure TnbSSHSessionOperationGate.Complete(AOwner: Pointer;
  AKind: TnbSSHSessionOperationKind; AResult, AEAgain: NativeInt;
  APreserveOnEAgain: Boolean);
begin
  if (AResult = AEAgain) and APreserveOnEAgain then
  begin
    if FPending and ((FOwner <> AOwner) or (FKind <> AKind)) then
      raise EInvalidOperation.Create(
        'SSH session operation interleaved while EAGAIN is pending');
    FPending := True;
    FOwner := AOwner;
    FKind := AKind;
  end
  else if FPending and (FOwner = AOwner) and (FKind = AKind) then
    Reset;
end;

procedure TnbSSHSessionOperationGate.ReleaseOwner(AOwner: Pointer);
begin
  if FPending and (FOwner = AOwner) then
    Reset;
end;

procedure TnbSSHSessionOperationGate.Reset;
begin
  FPending := False;
  FOwner := nil;
  FKind := sokDirectOpen;
end;

function TnbSSHSessionOperationGate.IsPending: Boolean;
begin
  Result := FPending;
end;

function TnbSSHSessionOperationGate.IsPendingFor(AOwner: Pointer;
  AKind: TnbSSHSessionOperationKind): Boolean;
begin
  Result := FPending and (FOwner = AOwner) and (FKind = AKind);
end;

{ TnbSSHBridgeEndpoint }

constructor TnbSSHBridgeEndpoint.Create;
begin
  inherited Create;
  FPort := 22;
  FConnectionTimeoutMs := 10000;
end;

destructor TnbSSHBridgeEndpoint.Destroy;
begin
  ClearPrivateKeyData;
  SecureZeroString(FPassword);
  SecureZeroString(FPassphrase);
  inherited;
end;

procedure TnbSSHBridgeEndpoint.Assign(Source: TPersistent);
var
  Endpoint: TnbSSHBridgeEndpoint;
begin
  if Source is TnbSSHBridgeEndpoint then
  begin
    Endpoint := TnbSSHBridgeEndpoint(Source);
    ClearSecrets;
    FHost := Endpoint.FHost;
    FPort := Endpoint.FPort;
    FUser := Endpoint.FUser;
    FPassword := Endpoint.FPassword;
    FKeyPath := Endpoint.FKeyPath;
    FPassphrase := Endpoint.FPassphrase;
    FPrivateKeyData := Endpoint.FPrivateKeyData;
    FPublicKeyData := Endpoint.FPublicKeyData;
    FHostKeyFingerprint := Endpoint.FHostKeyFingerprint;
    FConnectionTimeoutMs := Endpoint.FConnectionTimeoutMs;
  end
  else
    inherited;
end;

procedure TnbSSHBridgeEndpoint.SetPrivateKeyFromString(
  const APrivateKey, APublicKey: AnsiString);
begin
  ClearPrivateKeyData;
  FPrivateKeyData := APrivateKey;
  FPublicKeyData := APublicKey;
end;

procedure TnbSSHBridgeEndpoint.ClearPrivateKeyData;
begin
  SecureZeroAnsi(FPrivateKeyData);
  SecureZeroAnsi(FPublicKeyData);
end;

procedure TnbSSHBridgeEndpoint.ClearSecrets;
begin
  SecureZeroString(FPassword);
  SecureZeroString(FPassphrase);
  ClearPrivateKeyData;
end;

{ TnbSSHBridgeProfile }

constructor TnbSSHBridgeProfile.Create;
begin
  inherited Create;
  FMaster := TnbSSHBridgeEndpoint.Create;
  FReplica := TnbSSHBridgeEndpoint.Create;
  FTargetHost := '127.0.0.1';
  FTargetPort := 5432;
  FRemoteListenHost := '127.0.0.1';
  FRemoteListenPort := 15432;
  FForwardQueueSize := 16;
  FKeepAliveSeconds := 10;
  FKeepAliveTimeoutMs := 60000;
  FReconnectMinMs := 1000;
  FReconnectMaxMs := 30000;
  FBufferSize := 1024 * 1024;
  FIdleWaitMs := 1;
end;

destructor TnbSSHBridgeProfile.Destroy;
begin
  FReplica.Free;
  FMaster.Free;
  inherited;
end;

procedure TnbSSHBridgeProfile.Assign(Source: TPersistent);
var
  Profile: TnbSSHBridgeProfile;
begin
  if Source is TnbSSHBridgeProfile then
  begin
    Profile := TnbSSHBridgeProfile(Source);
    FMaster.Assign(Profile.FMaster);
    FReplica.Assign(Profile.FReplica);
    FTargetHost := Profile.FTargetHost;
    FTargetPort := Profile.FTargetPort;
    FRemoteListenHost := Profile.FRemoteListenHost;
    FRemoteListenPort := Profile.FRemoteListenPort;
    FForwardQueueSize := Profile.FForwardQueueSize;
    FKeepAliveSeconds := Profile.FKeepAliveSeconds;
    FKeepAliveTimeoutMs := Profile.FKeepAliveTimeoutMs;
    FReconnectMinMs := Profile.FReconnectMinMs;
    FReconnectMaxMs := Profile.FReconnectMaxMs;
    FBufferSize := Profile.FBufferSize;
    FIdleWaitMs := Profile.FIdleWaitMs;
  end
  else
    inherited;
end;

procedure TnbSSHBridgeProfile.SetMaster(const Value: TnbSSHBridgeEndpoint);
begin
  FMaster.Assign(Value);
end;

procedure TnbSSHBridgeProfile.SetReplica(const Value: TnbSSHBridgeEndpoint);
begin
  FReplica.Assign(Value);
end;

{ TnbSSHTunnelManager }

constructor TnbSSHTunnelManager.Create(AOwner: TComponent);
begin
  inherited;
  FProfile := TnbSSHBridgeProfile.Create;
  FStatus := sbsStopped;
end;

destructor TnbSSHTunnelManager.Destroy;
begin
  Stop;
  FProfile.Free;
  inherited;
end;

procedure TnbSSHTunnelManager.SetProfile(const Value: TnbSSHBridgeProfile);
begin
  if FWorker <> nil then
    raise EInvalidOperation.Create('Cannot change SSH bridge profile while running');
  FProfile.Assign(Value);
end;

procedure TnbSSHTunnelManager.ValidateProfile;

  procedure ValidateEndpoint(const AName: string; AEndpoint: TnbSSHBridgeEndpoint);
  begin
    if Trim(AEndpoint.Host) = '' then
      raise EArgumentException.Create(AName + ' SSH host is required');
    if (AEndpoint.Port < 1) or (AEndpoint.Port > 65535) then
      raise EArgumentOutOfRangeException.Create(AName + ' SSH port is invalid');
    if Trim(AEndpoint.User) = '' then
      raise EArgumentException.Create(AName + ' SSH user is required');
    if (AEndpoint.Password = '') and (AEndpoint.KeyPath = '') and
      (Length(AEndpoint.FPrivateKeyData) = 0) then
      raise EArgumentException.Create(AName + ' SSH credentials are required');
    if AEndpoint.ConnectionTimeoutMs < 100 then
      raise EArgumentOutOfRangeException.Create(AName +
        ' connection timeout must be at least 100 ms');
    if (Trim(AEndpoint.HostKeyFingerprint) = '') and
      not Assigned(FOnVerifyHostKey) then
      raise EArgumentException.Create(AName +
        ' host key fingerprint or OnVerifyHostKey handler is required');
  end;

begin
  ValidateEndpoint('Master', FProfile.Master);
  ValidateEndpoint('Replica', FProfile.Replica);
  if Trim(FProfile.TargetHost) = '' then
    raise EArgumentException.Create('Target host is required');
  if (FProfile.TargetPort < 1) or (FProfile.TargetPort > 65535) then
    raise EArgumentOutOfRangeException.Create('Target port is invalid');
  if Trim(FProfile.RemoteListenHost) = '' then
    raise EArgumentException.Create('Remote listen host is required');
  if (FProfile.RemoteListenPort < 1) or
    (FProfile.RemoteListenPort > 65535) then
    raise EArgumentOutOfRangeException.Create('Remote listen port is invalid');
  if FProfile.ForwardQueueSize < 1 then
    raise EArgumentOutOfRangeException.Create('Forward queue size must be positive');
  if FProfile.ForwardQueueSize > 1024 then
    raise EArgumentOutOfRangeException.Create('Forward queue size is too large');
  if (FProfile.BufferSize < 4096) or
    (FProfile.BufferSize > 16 * 1024 * 1024) then
    raise EArgumentOutOfRangeException.Create(
      'Bridge buffer size must be between 4096 and 16777216');
  if (FProfile.IdleWaitMs < 0) or (FProfile.IdleWaitMs > 1000) then
    raise EArgumentOutOfRangeException.Create(
      'Bridge idle wait must be between 0 and 1000 ms');
  if FProfile.KeepAliveSeconds < 0 then
    raise EArgumentOutOfRangeException.Create('Keepalive interval cannot be negative');
  if FProfile.KeepAliveTimeoutMs < 1000 then
    raise EArgumentOutOfRangeException.Create(
      'Keepalive timeout must be at least 1000 ms');
  if FProfile.ReconnectMinMs < 100 then
    raise EArgumentOutOfRangeException.Create('Reconnect minimum must be at least 100 ms');
  if FProfile.ReconnectMaxMs < FProfile.ReconnectMinMs then
    raise EArgumentOutOfRangeException.Create('Reconnect maximum is below minimum');
  if FProfile.ReconnectMaxMs > 3600000 then
    raise EArgumentOutOfRangeException.Create('Reconnect maximum is too large');
end;

procedure TnbSSHTunnelManager.Start;
var
  ProfileCopy: TnbSSHBridgeProfile;
begin
  Stop;
  ValidateProfile;
  ProfileCopy := TnbSSHBridgeProfile.Create;
  try
    ProfileCopy.Assign(FProfile);
    FLastError := '';
    FActiveChannels := 0;
    FRxBytes := 0;
    FTxBytes := 0;
    FConnectedSinceTick := 0;
    FChannelDiagnostics := '';
    FWorker := TnbSSHBridgeWorker.Create(Self, ProfileCopy);
    ProfileCopy := nil;
    FWorker.Start;
  finally
    ProfileCopy.Free;
  end;
end;

procedure TnbSSHTunnelManager.Stop;
var
  Worker: TnbSSHBridgeWorker;
begin
  Worker := TnbSSHBridgeWorker(FWorker);
  if Worker <> nil then
  begin
    FWorker := nil;
    Worker.RequestStop;
    Worker.WaitFor;
    TThread.RemoveQueuedEvents(Worker);
    Worker.Free;
  end;
  FMasterConnected := False;
  FReplicaConnected := False;
  FActiveChannels := 0;
  FConnectedSinceTick := 0;
  FChannelDiagnostics := '';
  if FStatus <> sbsStopped then
  begin
    FStatus := sbsStopped;
    if Assigned(FOnStatusChange) then
      FOnStatusChange(Self, FStatus);
  end;
end;

procedure TnbSSHTunnelManager.ApplyWorkerUpdate(AWorker: TObject);
var
  Worker: TnbSSHBridgeWorker;
  NewStatus: TnbSSHBridgeStatus;
  NewMasterConnected, NewReplicaConnected: Boolean;
  NewActiveChannels: Integer;
  NewRxBytes, NewTxBytes: Int64;
  NewConnectedSinceTick: UInt64;
  NewError, NewChannelDiagnostics: string;
  StatusChanged, StatsChanged, ErrorChanged: Boolean;
begin
  if AWorker <> FWorker then
    Exit;
  Worker := TnbSSHBridgeWorker(AWorker);
  Worker.Snapshot(NewStatus, NewMasterConnected, NewReplicaConnected,
    NewActiveChannels, NewRxBytes, NewTxBytes, NewConnectedSinceTick, NewError,
    NewChannelDiagnostics);
  StatusChanged := FStatus <> NewStatus;
  StatsChanged := (FActiveChannels <> NewActiveChannels) or
    (FRxBytes <> NewRxBytes) or (FTxBytes <> NewTxBytes);
  ErrorChanged := FLastError <> NewError;
  FStatus := NewStatus;
  FMasterConnected := NewMasterConnected;
  FReplicaConnected := NewReplicaConnected;
  FActiveChannels := NewActiveChannels;
  FRxBytes := NewRxBytes;
  FTxBytes := NewTxBytes;
  FConnectedSinceTick := NewConnectedSinceTick;
  FLastError := NewError;
  FChannelDiagnostics := NewChannelDiagnostics;
  if StatusChanged and Assigned(FOnStatusChange) then
    FOnStatusChange(Self, FStatus);
  if StatsChanged and Assigned(FOnStatistics) then
    FOnStatistics(Self, FActiveChannels, FRxBytes, FTxBytes);
  if ErrorChanged and (FLastError <> '') and Assigned(FOnError) then
    FOnError(Self, FLastError);
end;

function TnbSSHTunnelManager.VerifyHostKey(ARole: TnbSSHBridgeRole;
  const AHost, AFingerprint: string): Boolean;
begin
  Result := False;
  if Assigned(FOnVerifyHostKey) then
    FOnVerifyHostKey(Self, ARole, AHost, AFingerprint, Result);
end;

{ TnbSSHBridgeSession }

constructor TnbSSHBridgeSession.Create(AWorker: TnbSSHBridgeWorker;
  ARole: TnbSSHBridgeRole; AEndpoint: TnbSSHBridgeEndpoint);
begin
  inherited Create;
  FWorker := AWorker;
  FRole := ARole;
  FEndpoint := AEndpoint;
  FSocketLock := TCriticalSection.Create;
  FOperationGate := TnbSSHSessionOperationGate.Create;
end;

destructor TnbSSHBridgeSession.Destroy;
begin
  Disconnect;
  FOperationGate.Free;
  FSocketLock.Free;
  inherited;
end;

function TnbSSHBridgeSession.GetLastErrorCode: Integer;
var
  ErrorMessage: PAnsiChar;
  ErrorLength: Integer;
begin
  if (FSession = nil) or not Assigned(ssh2_session_last_error) then
    Exit(0);
  ErrorMessage := nil;
  ErrorLength := 0;
  Result := ssh2_session_last_error(FSession, @ErrorMessage, @ErrorLength, 0);
end;

function TnbSSHBridgeSession.GetLastError: string;
var
  ErrorMessage: PAnsiChar;
  ErrorLength, ErrorCode: Integer;
begin
  if (FSession = nil) or not Assigned(ssh2_session_last_error) then
    Exit('no libssh2 error information');
  ErrorMessage := nil;
  ErrorLength := 0;
  ErrorCode := ssh2_session_last_error(FSession, @ErrorMessage, @ErrorLength, 0);
  if (ErrorMessage <> nil) and (ErrorLength > 0) then
    Result := Format('[%d] %s', [ErrorCode,
      string(AnsiString(ErrorMessage))])
  else
    Result := Format('[%d] no description', [ErrorCode]);
end;

function TnbSSHBridgeSession.DescribeTransportError(
  AResult: NativeInt): string;
var
  BlockDirections: Integer;
  SessionError: string;
{$IF Defined(MSWINDOWS)}
  SocketError: Integer;
  SocketErrorText: string;
{$ENDIF}
begin
  // Capture the thread-local socket error before another API call can replace it.
{$IF Defined(MSWINDOWS)}
  SocketError := Winapi.WinSock2.WSAGetLastError;
  if SocketError <> 0 then
    SocketErrorText := SysErrorMessage(SocketError)
  else
    SocketErrorText := '';
{$ENDIF}

  BlockDirections := 0;
  if (FSession <> nil) and Assigned(ssh2_session_block_directions) then
    BlockDirections := ssh2_session_block_directions(FSession);
  SessionError := GetLastError;

{$IF Defined(MSWINDOWS)}
  Result := Format('code=%d, socket_error=%d (%s), block_directions=%d, ' +
    'libssh2=%s', [AResult, SocketError, SocketErrorText, BlockDirections,
    SessionError]);
{$ELSE}
  Result := Format('code=%d, block_directions=%d, libssh2=%s',
    [AResult, BlockDirections, SessionError]);
{$ENDIF}
end;

function TnbSSHBridgeSession.Fingerprint: string;
var
  Hash: PAnsiChar;
  Raw: TBytes;
begin
  if not Assigned(ssh2_hostkey_hash) then
    raise ESSHLibError.Create('libssh2_hostkey_hash is unavailable');
  Hash := ssh2_hostkey_hash(FSession, LIBSSH2_HOSTKEY_HASH_SHA256);
  if Hash = nil then
    raise ESSHLibError.Create('Cannot obtain SSH host key fingerprint');
  SetLength(Raw, HOSTKEY_HASH_SHA256_LEN);
  Move(Hash^, Raw[0], Length(Raw));
  Result := 'SHA256:' +
    TNetEncoding.Base64.EncodeBytesToString(Raw).TrimRight(['=']);
end;

procedure TnbSSHBridgeSession.Authenticate;
var
  RC: Integer;
  UserName, Password, Passphrase, KeyPath: UTF8String;
  PassphrasePtr: PAnsiChar;
begin
  UserName := UTF8String(FEndpoint.User);
  Passphrase := UTF8String(FEndpoint.Passphrase);
  if Passphrase = '' then
    PassphrasePtr := nil
  else
    PassphrasePtr := PAnsiChar(Passphrase);
  try
    if Length(FEndpoint.FPrivateKeyData) > 0 then
    begin
      if not Assigned(ssh2_userauth_publickey_frommemory) then
        raise ESSHLibError.Create('In-memory SSH keys are unavailable');
      RC := ssh2_userauth_publickey_frommemory(FSession,
        PAnsiChar(UserName), Length(UserName),
        PAnsiChar(FEndpoint.FPublicKeyData), Length(FEndpoint.FPublicKeyData),
        PAnsiChar(FEndpoint.FPrivateKeyData), Length(FEndpoint.FPrivateKeyData),
        PassphrasePtr);
    end
    else if FEndpoint.KeyPath <> '' then
    begin
      KeyPath := UTF8String(FEndpoint.KeyPath);
      RC := ssh2_userauth_publickey_fromfile_ex(FSession,
        PAnsiChar(UserName), Length(UserName), nil, PAnsiChar(KeyPath),
        PassphrasePtr);
    end
    else
    begin
      Password := UTF8String(FEndpoint.Password);
      try
        RC := ssh2_userauth_password_ex(FSession,
          PAnsiChar(UserName), Length(UserName), PAnsiChar(Password),
          Length(Password), nil);
      finally
        SecureZeroUTF8(Password);
      end;
    end;
  finally
    SecureZeroUTF8(Passphrase);
  end;
  if RC <> 0 then
    raise ESSHLibError.Create('SSH authentication failed: ' + GetLastError);
end;

procedure TnbSSHBridgeSession.Connect;
var
  RC: Integer;
  ActualFingerprint, ExpectedFingerprint: string;
begin
  Disconnect;
  FSocketLock.Acquire;
  try
    FSocket := TTCPBlockSocket.Create;
  finally
    FSocketLock.Release;
  end;
  FSocket.ConnectionTimeout := FEndpoint.ConnectionTimeoutMs;
  FSocket.SetTimeout(FEndpoint.ConnectionTimeoutMs);
  FSocket.Connect(FEndpoint.Host, IntToStr(FEndpoint.Port));
  if FSocket.LastError <> 0 then
    raise ESSHLibError.Create('TCP connect failed: ' + FSocket.LastErrorDesc);
  FSession := ssh2_session_init_ex(nil, nil, nil, nil);
  if FSession = nil then
    raise ESSHLibError.Create('libssh2_session_init_ex failed');
  ssh2_session_set_timeout(FSession, FEndpoint.ConnectionTimeoutMs);
  RC := ssh2_session_handshake(FSession, FSocket.Socket);
  if RC <> 0 then
    raise ESSHLibError.Create('SSH handshake failed: ' + GetLastError);

  ActualFingerprint := Fingerprint;
  ExpectedFingerprint := Trim(FEndpoint.HostKeyFingerprint);
  if ExpectedFingerprint <> '' then
  begin
    if not SameStr(ExpectedFingerprint, ActualFingerprint) then
      raise ESSHLibError.CreateFmt(
        'SSH host key mismatch for %s (expected %s, received %s)',
        [FEndpoint.Host, ExpectedFingerprint, ActualFingerprint]);
  end
  else if not FWorker.VerifyHostKey(FRole, FEndpoint.Host,
    ActualFingerprint) then
    raise ESSHLibError.CreateFmt('SSH host key rejected for %s: %s',
      [FEndpoint.Host, ActualFingerprint]);

  Authenticate;
  if Assigned(ssh2_keepalive_config) then
    ssh2_keepalive_config(FSession, 1, FWorker.FProfile.KeepAliveSeconds);
end;

procedure TnbSSHBridgeSession.Disconnect;
begin
  FOperationGate.Reset;
  if FSession <> nil then
  begin
    try
      SetBlocking(1000);
      ssh2_session_disconnect_ex(FSession,
        LIBSSH2_DISCONNECT_BY_APPLICATION, 'bridge stopped', '');
    except
    end;
    try
      ssh2_session_free(FSession);
    except
    end;
    FSession := nil;
  end;
  FSocketLock.Acquire;
  try
    FreeAndNil(FSocket);
  finally
    FSocketLock.Release;
  end;
end;

function TnbSSHBridgeSession.TryOperation(AOwner: Pointer;
  AKind: TnbSSHSessionOperationKind): Boolean;
begin
  Result := FOperationGate.TryEnter(AOwner, AKind);
end;

procedure TnbSSHBridgeSession.CompleteOperation(AOwner: Pointer;
  AKind: TnbSSHSessionOperationKind; AResult: NativeInt;
  APreserveOnEAgain: Boolean);
begin
  FOperationGate.Complete(AOwner, AKind, AResult, LIBSSH2_ERROR_EAGAIN,
    APreserveOnEAgain);
end;

procedure TnbSSHBridgeSession.ReleaseOperationOwner(AOwner: Pointer);
begin
  FOperationGate.ReleaseOwner(AOwner);
end;

function TnbSSHBridgeSession.CanRunUntrackedOperation: Boolean;
begin
  Result := not FOperationGate.IsPending;
end;

function TnbSSHBridgeSession.TryKeepAlive(AOwner: Pointer;
  out AResult: Integer): Boolean;
begin
  Result := TryOperation(AOwner, sokKeepAlive);
  if not Result then
  begin
    AResult := LIBSSH2_ERROR_EAGAIN;
    Exit;
  end;
  if not Assigned(ssh2_keepalive_send) then
    AResult := 0
  else
    AResult := ssh2_keepalive_send(FSession, @FKeepAliveSecondsToNext);
  CompleteOperation(AOwner, sokKeepAlive, AResult);
end;

procedure TnbSSHBridgeSession.SetNonBlocking;
begin
  FSocketLock.Acquire;
  try
    if Assigned(FSocket) then
    begin
      FSocket.SetTimeout(0);
      FSocket.NonBlockMode := True;
    end;
  finally
    FSocketLock.Release;
  end;
  if FSession <> nil then
  begin
    ssh2_session_set_timeout(FSession, 0);
    ssh2_session_set_blocking(FSession, 0);
  end;
end;

procedure TnbSSHBridgeSession.SetBlocking(ATimeoutMs: Integer);
begin
  FSocketLock.Acquire;
  try
    if Assigned(FSocket) then
    begin
      FSocket.NonBlockMode := False;
      FSocket.SetTimeout(ATimeoutMs);
    end;
  finally
    FSocketLock.Release;
  end;
  if FSession <> nil then
  begin
    ssh2_session_set_timeout(FSession, ATimeoutMs);
    ssh2_session_set_blocking(FSession, 1);
  end;
end;

procedure TnbSSHBridgeSession.Interrupt;
begin
  FSocketLock.Acquire;
  try
    if Assigned(FSocket) and (FSocket.Socket <> INVALID_SOCKET) then
      Synsock.Shutdown(FSocket.Socket, 2);
  finally
    FSocketLock.Release;
  end;
end;

{ TnbSSHBridgeChannelPair }

constructor TnbSSHBridgeChannelPair.Create(AId: Integer; AReplicaSession,
  AMasterSession: TnbSSHBridgeSession; AReplicaChannel,
  AMasterChannel: PLIBSSH2_CHANNEL);
begin
  inherited Create;
  FId := AId;
  FReplicaSession := AReplicaSession;
  FMasterSession := AMasterSession;
  FReplicaChannel := AReplicaChannel;
  FMasterChannel := AMasterChannel;
  FCreatedTick := TThread.GetTickCount64;
  FLastProgressTick := FCreatedTick;
end;

destructor TnbSSHBridgeChannelPair.Destroy;
begin
  FReplicaSession.ReleaseOperationOwner(Self);
  FMasterSession.ReleaseOperationOwner(Self);
  CloseChannel(FReplicaChannel, FReplicaClosed);
  CloseChannel(FMasterChannel, FMasterClosed);
  inherited;
end;

procedure TnbSSHBridgeChannelPair.CloseChannel(
  var AChannel: PLIBSSH2_CHANNEL; AAlreadyClosed: Boolean);
begin
  if AChannel = nil then
    Exit;
  if not AAlreadyClosed then
    try
      ssh2_channel_close(AChannel);
    except
    end;
  try
    ssh2_channel_free(AChannel);
  except
  end;
  AChannel := nil;
end;

function TnbSSHBridgeChannelPair.PumpDirection(ASource,
  ADestination: PLIBSSH2_CHANNEL; ASourceSession,
  ADestinationSession: TnbSSHBridgeSession; const ASourceName,
  ADestinationName: string; var ABuffer: TBytes; var AOffset, ACount: Integer;
  var ASourceEOF, ADestinationEOFSent: Boolean; ABufferSize: Integer;
  out ATransferred: Int64): Boolean;
var
  Count: NativeInt;
  WriteWindowBefore, WriteWindowAfter: TLibSSH2ULong;
  PreserveWriteRetry: Boolean;
begin
  Result := False;
  ATransferred := 0;
  if (ACount = 0) and not ASourceEOF and
    ASourceSession.CanRunUntrackedOperation then
  begin
    if Length(ABuffer) <> ABufferSize then
      SetLength(ABuffer, ABufferSize);
    Count := ssh2_channel_read_ex(ASource, 0, PAnsiChar(@ABuffer[0]),
      Length(ABuffer));
    if ASource = FReplicaChannel then
      FReplicaReadResult := Count
    else
      FMasterReadResult := Count;
    if Count > 0 then
    begin
      ACount := Count;
      AOffset := 0;
      Result := True;
    end
    else
    begin
      if (Count < 0) and (Count <> LIBSSH2_ERROR_EAGAIN) then
      begin
        if IsSSHSessionError(Count) then
          raise ESSHBridgeSessionError.CreateFmt(
            '%s SSH transport read failed: %s', [ASourceName,
            ASourceSession.DescribeTransportError(Count)]);
        raise ESSHLibError.CreateFmt(
          '%s SSH forwarded channel read failed: %d', [ASourceName, Count]);
      end;
      if ssh2_channel_eof(ASource) <> 0 then
        ASourceEOF := True;
    end;
  end;

  if (ACount > 0) and
    ADestinationSession.TryOperation(Self, sokChannelWrite) then
  begin
    WriteWindowBefore := 1;
    if Assigned(ssh2_channel_window_write_ex) then
      WriteWindowBefore := ssh2_channel_window_write_ex(ADestination, nil);
    Count := ssh2_channel_write_ex(ADestination, 0,
      PAnsiChar(@ABuffer[0]) + AOffset, ACount - AOffset);
    WriteWindowAfter := WriteWindowBefore;
    if Assigned(ssh2_channel_window_write_ex) then
      WriteWindowAfter := ssh2_channel_window_write_ex(ADestination, nil);
    // With a zero window libssh2 has not created a transport packet yet. Its
    // EAGAIN only asks the caller to keep reading for WINDOW_ADJUST, so it must
    // not lock every other channel on the same session.
    PreserveWriteRetry := not ((Count = LIBSSH2_ERROR_EAGAIN) and
      (WriteWindowBefore = 0) and (WriteWindowAfter = 0));
    ADestinationSession.CompleteOperation(Self, sokChannelWrite, Count,
      PreserveWriteRetry);
    if ADestination = FReplicaChannel then
      FReplicaWriteResult := Count
    else
      FMasterWriteResult := Count;
    if Count > 0 then
    begin
      Inc(AOffset, Count);
      Inc(ATransferred, Count);
      FLastProgressTick := TThread.GetTickCount64;
      if ASource = FReplicaChannel then
        Inc(FReplicaToMasterBytes, Count)
      else
        Inc(FMasterToReplicaBytes, Count);
      Result := True;
      if AOffset >= ACount then
      begin
        ACount := 0;
        AOffset := 0;
      end;
    end
    else if (Count < 0) and (Count <> LIBSSH2_ERROR_EAGAIN) then
    begin
      if IsSSHSessionError(Count) then
        raise ESSHBridgeSessionError.CreateFmt(
          '%s SSH transport write failed: %s', [ADestinationName,
          ADestinationSession.DescribeTransportError(Count)]);
      raise ESSHLibError.CreateFmt(
        '%s SSH forwarded channel write failed: %d',
        [ADestinationName, Count]);
    end;
  end;

  if ASourceEOF and (ACount = 0) and not ADestinationEOFSent then
  begin
    if not ADestinationSession.TryOperation(Self, sokChannelEOF) then
      Exit;
  end;
  if ASourceEOF and (ACount = 0) and not ADestinationEOFSent then
  begin
    Count := ssh2_channel_send_eof(ADestination);
    ADestinationSession.CompleteOperation(Self, sokChannelEOF, Count);
    if Count = 0 then
    begin
      ADestinationEOFSent := True;
      Result := True;
    end
    else if Count <> LIBSSH2_ERROR_EAGAIN then
    begin
      if IsSSHSessionError(Count) then
        raise ESSHBridgeSessionError.CreateFmt(
          '%s SSH transport EOF failed: %s', [ADestinationName,
          ADestinationSession.DescribeTransportError(Count)]);
      raise ESSHLibError.CreateFmt('%s SSH forwarded channel EOF failed: %d',
        [ADestinationName, Count]);
    end;
  end;
end;

function TnbSSHBridgeChannelPair.Pump(ABufferSize: Integer;
  out ARxBytes, ATxBytes: Int64): Boolean;
var
  Moved: Int64;
  CloseResult: Integer;
  HadEOF: Boolean;
begin
  ARxBytes := 0;
  ATxBytes := 0;
  HadEOF := FReplicaEOF or FMasterEOF;
  Result := PumpDirection(FReplicaChannel, FMasterChannel,
    FReplicaSession, FMasterSession, 'Replica', 'Master',
    FReplicaToMaster, FReplicaToMasterOffset, FReplicaToMasterCount,
    FReplicaEOF, FMasterEOFSent, ABufferSize, Moved);
  Inc(ATxBytes, Moved);
  if PumpDirection(FMasterChannel, FReplicaChannel, FMasterSession,
    FReplicaSession, 'Master', 'Replica', FMasterToReplica,
    FMasterToReplicaOffset, FMasterToReplicaCount, FMasterEOF,
    FReplicaEOFSent, ABufferSize, Moved) then
    Result := True;
  Inc(ARxBytes, Moved);

  if not HadEOF and (FReplicaEOF or FMasterEOF) then
    FFirstEOFTick := TThread.GetTickCount64;

  if FReplicaEOF and FMasterEOF and FReplicaEOFSent and FMasterEOFSent and
    (FReplicaToMasterCount = 0) and (FMasterToReplicaCount = 0) then
  begin
    if not FReplicaClosed and
      FReplicaSession.TryOperation(Self, sokChannelClose) then
    begin
      CloseResult := ssh2_channel_close(FReplicaChannel);
      FReplicaSession.CompleteOperation(Self, sokChannelClose, CloseResult);
      if CloseResult = 0 then
      begin
        FReplicaClosed := True;
        Result := True;
      end
      else if CloseResult <> LIBSSH2_ERROR_EAGAIN then
      begin
        if IsSSHSessionError(CloseResult) then
          raise ESSHBridgeSessionError.CreateFmt(
            'Replica SSH transport close failed: %s',
            [FReplicaSession.DescribeTransportError(CloseResult)]);
        raise ESSHLibError.CreateFmt(
          'Replica SSH forwarded channel close failed: %d', [CloseResult]);
      end;
    end;
    if not FMasterClosed and
      FMasterSession.TryOperation(Self, sokChannelClose) then
    begin
      CloseResult := ssh2_channel_close(FMasterChannel);
      FMasterSession.CompleteOperation(Self, sokChannelClose, CloseResult);
      if CloseResult = 0 then
      begin
        FMasterClosed := True;
        Result := True;
      end
      else if CloseResult <> LIBSSH2_ERROR_EAGAIN then
      begin
        if IsSSHSessionError(CloseResult) then
          raise ESSHBridgeSessionError.CreateFmt(
            'Master SSH transport close failed: %s',
            [FMasterSession.DescribeTransportError(CloseResult)]);
        raise ESSHLibError.CreateFmt(
          'Master SSH forwarded channel close failed: %d', [CloseResult]);
      end;
    end;
  end;
end;

function TnbSSHBridgeChannelPair.Finished: Boolean;
begin
  Result := FReplicaClosed and FMasterClosed;
end;

function TnbSSHBridgeChannelPair.EOFDrainTimedOut(
  ATimeoutMs: UInt64): Boolean;
var
  DrainProgressTick, NowTick: UInt64;
begin
  Result := False;
  if (FFirstEOFTick = 0) or Finished then
    Exit;
  DrainProgressTick := FFirstEOFTick;
  if FLastProgressTick > DrainProgressTick then
    DrainProgressTick := FLastProgressTick;
  NowTick := TThread.GetTickCount64;
  Result := NowTick - DrainProgressTick >= ATimeoutMs;
end;

function TnbSSHBridgeChannelPair.DiagnosticText: string;
var
  ReplicaReadWindow, ReplicaReadAvailable, ReplicaReadInitial: TLibSSH2ULong;
  ReplicaWriteWindow, ReplicaWriteInitial: TLibSSH2ULong;
  MasterReadWindow, MasterReadAvailable, MasterReadInitial: TLibSSH2ULong;
  MasterWriteWindow, MasterWriteInitial: TLibSSH2ULong;
  NowTick: UInt64;
begin
  ReplicaReadWindow := 0;
  ReplicaReadAvailable := 0;
  ReplicaReadInitial := 0;
  ReplicaWriteWindow := 0;
  ReplicaWriteInitial := 0;
  MasterReadWindow := 0;
  MasterReadAvailable := 0;
  MasterReadInitial := 0;
  MasterWriteWindow := 0;
  MasterWriteInitial := 0;
  if Assigned(ssh2_channel_window_read_ex) then
  begin
    ReplicaReadWindow := ssh2_channel_window_read_ex(FReplicaChannel,
      @ReplicaReadAvailable, @ReplicaReadInitial);
    MasterReadWindow := ssh2_channel_window_read_ex(FMasterChannel,
      @MasterReadAvailable, @MasterReadInitial);
  end;
  if Assigned(ssh2_channel_window_write_ex) then
  begin
    ReplicaWriteWindow := ssh2_channel_window_write_ex(FReplicaChannel,
      @ReplicaWriteInitial);
    MasterWriteWindow := ssh2_channel_window_write_ex(FMasterChannel,
      @MasterWriteInitial);
  end;
  NowTick := TThread.GetTickCount64;
  Result := Format(
    'channel=%d age_ms=%d idle_ms=%d r2m_bytes=%d m2r_bytes=%d ' +
    'r2m_buffer=%d/%d m2r_buffer=%d/%d ' +
    'replica_io=%d/%d master_io=%d/%d eof=%s/%s eof_sent=%s/%s closed=%s/%s ' +
    'replica_window=read:%d,avail:%d,initial:%d,write:%d,initial:%d ' +
    'master_window=read:%d,avail:%d,initial:%d,write:%d,initial:%d',
    [FId, Int64(NowTick - FCreatedTick), Int64(NowTick - FLastProgressTick),
     FReplicaToMasterBytes, FMasterToReplicaBytes,
     FReplicaToMasterOffset, FReplicaToMasterCount,
     FMasterToReplicaOffset, FMasterToReplicaCount,
     FReplicaReadResult, FReplicaWriteResult,
     FMasterReadResult, FMasterWriteResult,
     BoolToStr(FReplicaEOF, True), BoolToStr(FMasterEOF, True),
     BoolToStr(FReplicaEOFSent, True), BoolToStr(FMasterEOFSent, True),
     BoolToStr(FReplicaClosed, True), BoolToStr(FMasterClosed, True),
     UInt64(ReplicaReadWindow), UInt64(ReplicaReadAvailable),
     UInt64(ReplicaReadInitial), UInt64(ReplicaWriteWindow),
     UInt64(ReplicaWriteInitial), UInt64(MasterReadWindow),
     UInt64(MasterReadAvailable), UInt64(MasterReadInitial),
     UInt64(MasterWriteWindow), UInt64(MasterWriteInitial)]);
end;

{ TnbSSHBridgeWorker }

constructor TnbSSHBridgeWorker.Create(AOwner: TnbSSHTunnelManager;
  AProfile: TnbSSHBridgeProfile);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FProfile := AProfile;
  FStateLock := TCriticalSection.Create;
  FChannels := TObjectList<TnbSSHBridgeChannelPair>.Create(True);
  FMaster := TnbSSHBridgeSession.Create(Self, sbrMaster, FProfile.Master);
  FReplica := TnbSSHBridgeSession.Create(Self, sbrReplica, FProfile.Replica);
  FStatus := sbsStopped;
end;

destructor TnbSSHBridgeWorker.Destroy;
begin
  CloseForwarding;
  FReplica.Free;
  FMaster.Free;
  FChannels.Free;
  FStateLock.Free;
  FProfile.Free;
  inherited;
end;

procedure TnbSSHBridgeWorker.QueueUpdate;
begin
  if TInterlocked.CompareExchange(FUpdateQueued, 1, 0) = 0 then
    TThread.Queue(Self, DeliverUpdate);
end;

procedure TnbSSHBridgeWorker.DeliverUpdate;
begin
  TInterlocked.Exchange(FUpdateQueued, 0);
  FOwner.ApplyWorkerUpdate(Self);
end;

procedure TnbSSHBridgeWorker.Snapshot(out AStatus: TnbSSHBridgeStatus;
  out AMasterConnected, AReplicaConnected: Boolean;
  out AActiveChannels: Integer; out ARxBytes, ATxBytes: Int64;
  out AConnectedSinceTick: UInt64; out ALastError,
  AChannelDiagnostics: string);
begin
  FStateLock.Acquire;
  try
    AStatus := FStatus;
    AMasterConnected := FMasterConnected;
    AReplicaConnected := FReplicaConnected;
    AActiveChannels := FActiveChannels;
    ARxBytes := FRxBytes;
    ATxBytes := FTxBytes;
    AConnectedSinceTick := FConnectedSinceTick;
    ALastError := FLastError;
    AChannelDiagnostics := FChannelDiagnostics;
  finally
    FStateLock.Release;
  end;
end;

procedure TnbSSHBridgeWorker.SetStatus(AStatus: TnbSSHBridgeStatus;
  const AError: string);
begin
  FStateLock.Acquire;
  try
    FStatus := AStatus;
    if AError <> '' then
      FLastError := AError
    else if AStatus in [sbsListening, sbsActive, sbsStopped] then
      FLastError := '';
  finally
    FStateLock.Release;
  end;
  QueueUpdate;
end;

procedure TnbSSHBridgeWorker.SetConnections(AMaster, AReplica: Boolean);
begin
  FStateLock.Acquire;
  try
    FMasterConnected := AMaster;
    FReplicaConnected := AReplica;
  finally
    FStateLock.Release;
  end;
  QueueUpdate;
end;

procedure TnbSSHBridgeWorker.UpdateStatistics;
begin
  FStateLock.Acquire;
  try
    FActiveChannels := FChannels.Count;
  finally
    FStateLock.Release;
  end;
  QueueUpdate;
end;

procedure TnbSSHBridgeWorker.UpdateChannelDiagnostics;
var
  I: Integer;
  Diagnostics: TStringBuilder;
begin
  Diagnostics := TStringBuilder.Create;
  try
    for I := 0 to FChannels.Count - 1 do
    begin
      if Diagnostics.Length > 0 then
        Diagnostics.AppendLine;
      Diagnostics.Append(FChannels[I].DiagnosticText);
    end;
    FStateLock.Acquire;
    try
      FChannelDiagnostics := Diagnostics.ToString;
    finally
      FStateLock.Release;
    end;
  finally
    Diagnostics.Free;
  end;
  QueueUpdate;
end;

procedure TnbSSHBridgeWorker.DoVerifyHostKey;
begin
  FVerifyAccepted := FOwner.VerifyHostKey(FVerifyRole, FVerifyHost,
    FVerifyFingerprint);
end;

function TnbSSHBridgeWorker.VerifyHostKey(ARole: TnbSSHBridgeRole;
  const AHost, AFingerprint: string): Boolean;
begin
  FVerifyRole := ARole;
  FVerifyHost := AHost;
  FVerifyFingerprint := AFingerprint;
  FVerifyAccepted := False;
  Synchronize(DoVerifyHostKey);
  Result := FVerifyAccepted;
end;

procedure TnbSSHBridgeWorker.ConnectAndListen;
var
  ListenHost: UTF8String;
  BoundPort: Integer;
begin
  EnsureLibLoaded;
  if not Assigned(ssh2_channel_forward_listen_ex) or
    not Assigned(ssh2_channel_forward_accept) or
    not Assigned(ssh2_channel_forward_cancel) or
    not Assigned(ssh2_channel_direct_tcpip_ex) then
    raise ESSHLibError.Create(
      'The loaded libssh2 does not provide SSH forwarding APIs');
  FMaster.Connect;
  SetConnections(True, False);
  FReplica.Connect;
  SetConnections(True, True);

  ListenHost := UTF8String(FProfile.RemoteListenHost);
  BoundPort := 0;
  FListener := ssh2_channel_forward_listen_ex(FReplica.Session,
    PAnsiChar(ListenHost), FProfile.RemoteListenPort, @BoundPort,
    FProfile.ForwardQueueSize);
  if FListener = nil then
    raise ESSHLibError.Create('Cannot open Replica remote listener: ' +
      FReplica.GetLastError);
  if (BoundPort <> 0) and (BoundPort <> FProfile.RemoteListenPort) then
    raise ESSHLibError.CreateFmt(
      'Replica listener bound unexpected port %d instead of %d',
      [BoundPort, FProfile.RemoteListenPort]);

  FMaster.SetNonBlocking;
  FReplica.SetNonBlocking;
  FStateLock.Acquire;
  try
    FConnectedSinceTick := TThread.GetTickCount64;
  finally
    FStateLock.Release;
  end;
  SetStatus(sbsListening);
end;

procedure TnbSSHBridgeWorker.CloseForwarding;
begin
  FMaster.ReleaseOperationOwner(Self);
  FReplica.ReleaseOperationOwner(Self);
  if FMaster.Session <> nil then
    FMaster.SetBlocking(1000);
  if FReplica.Session <> nil then
    FReplica.SetBlocking(1000);
  FChannels.Clear;
  if FPendingReplicaChannel <> nil then
  begin
    try ssh2_channel_close(FPendingReplicaChannel); except end;
    try ssh2_channel_free(FPendingReplicaChannel); except end;
    FPendingReplicaChannel := nil;
  end;
  if FListener <> nil then
  begin
    try ssh2_channel_forward_cancel(FListener); except end;
    FListener := nil;
  end;
  FReplica.Disconnect;
  FMaster.Disconnect;
  FStateLock.Acquire;
  try
    FConnectedSinceTick := 0;
  finally
    FStateLock.Release;
  end;
  SetConnections(False, False);
  UpdateStatistics;
  UpdateChannelDiagnostics;
end;

procedure TnbSSHBridgeWorker.RunForwarding;
var
  MasterChannel: PLIBSSH2_CHANNEL;
  TargetHost, SourceHost: UTF8String;
  I, ErrorCode, KeepAliveResult, BurstIndex: Integer;
  Pair: TnbSSHBridgeChannelPair;
  RxDelta, TxDelta, BurstRx, BurstTx: Int64;
  DidWork: Boolean;
  NextKeepAlive, KeepAliveIntervalMs, LastActivityTick,
    NextDiagnosticsTick: UInt64;
  MasterKeepAliveBlockedSince, ReplicaKeepAliveBlockedSince: UInt64;
  NowTick: UInt64;
  KeepAliveBlocked: Boolean;
  ErrorText: string;
begin
  TargetHost := UTF8String(FProfile.TargetHost);
  SourceHost := '127.0.0.1';
  KeepAliveIntervalMs := UInt64(FProfile.KeepAliveSeconds) * 1000;
  LastActivityTick := TThread.GetTickCount64;
  NextKeepAlive := LastActivityTick + KeepAliveIntervalMs;
  MasterKeepAliveBlockedSince := 0;
  ReplicaKeepAliveBlockedSince := 0;
  NextDiagnosticsTick := LastActivityTick + 1000;
  while not Terminated do
  begin
    DidWork := False;
    if (FPendingReplicaChannel = nil) and
      FReplica.CanRunUntrackedOperation then
    begin
      FPendingReplicaChannel := ssh2_channel_forward_accept(FListener);
      if FPendingReplicaChannel = nil then
      begin
        ErrorCode := FReplica.GetLastErrorCode;
        // In nonblocking mode libssh2 reports CHANNEL_UNKNOWN after it has
        // consumed a transport packet when no new forwarded channel is queued.
        if (ErrorCode <> 0) and (ErrorCode <> LIBSSH2_ERROR_EAGAIN) and
          (ErrorCode <> LIBSSH2_ERROR_CHANNEL_UNKNOWN) then
          raise ESSHLibError.Create('Replica forward accept failed: ' +
            FReplica.GetLastError);
      end
      else
      begin
        DidWork := True;
        LastActivityTick := TThread.GetTickCount64;
      end;
    end;

    if FPendingReplicaChannel <> nil then
    begin
      if FMaster.TryOperation(Self, sokDirectOpen) then
      begin
        MasterChannel := ssh2_channel_direct_tcpip_ex(FMaster.Session,
          PAnsiChar(TargetHost), FProfile.TargetPort, PAnsiChar(SourceHost), 0);
        if MasterChannel <> nil then
          ErrorCode := 0
        else
          ErrorCode := FMaster.GetLastErrorCode;
        FMaster.CompleteOperation(Self, sokDirectOpen, ErrorCode);
        if MasterChannel <> nil then
        begin
          Inc(FNextChannelId);
          FChannels.Add(TnbSSHBridgeChannelPair.Create(FNextChannelId,
            FReplica, FMaster, FPendingReplicaChannel, MasterChannel));
          FPendingReplicaChannel := nil;
          UpdateStatistics;
          UpdateChannelDiagnostics;
          SetStatus(sbsActive);
          DidWork := True;
          LastActivityTick := TThread.GetTickCount64;
        end
        else if ErrorCode <> LIBSSH2_ERROR_EAGAIN then
        begin
          try ssh2_channel_close(FPendingReplicaChannel); except end;
          try ssh2_channel_free(FPendingReplicaChannel); except end;
          FPendingReplicaChannel := nil;
          raise ESSHLibError.Create('Master direct-tcpip failed: ' +
            FMaster.GetLastError);
        end;
      end;
    end;

    I := FChannels.Count - 1;
    while I >= 0 do
    begin
      Pair := FChannels[I];
      try
        RxDelta := 0;
        TxDelta := 0;
        for BurstIndex := 1 to 16 do
        begin
          if not Pair.Pump(FProfile.BufferSize, BurstRx, BurstTx) then
            Break;
          DidWork := True;
          Inc(RxDelta, BurstRx);
          Inc(TxDelta, BurstTx);
        end;
        if (RxDelta <> 0) or (TxDelta <> 0) then
        begin
          FStateLock.Acquire;
          try
            Inc(FRxBytes, RxDelta);
            Inc(FTxBytes, TxDelta);
          finally
            FStateLock.Release;
          end;
          QueueUpdate;
          LastActivityTick := TThread.GetTickCount64;
          MasterKeepAliveBlockedSince := 0;
          ReplicaKeepAliveBlockedSince := 0;
        end;
        if Pair.EOFDrainTimedOut(120000) then
          raise ESSHLibError.Create(
            'SSH forwarded channel drain timed out after EOF');
        if Pair.Finished then
        begin
          FChannels.Delete(I);
          UpdateStatistics;
          UpdateChannelDiagnostics;
          if FChannels.Count = 0 then
            SetStatus(sbsListening);
        end;
      except
        on E: ESSHBridgeSessionError do
          raise ESSHBridgeSessionError.Create(E.Message + sLineBreak +
            Pair.DiagnosticText);
        on E: Exception do
        begin
          ErrorText := E.Message + sLineBreak + Pair.DiagnosticText;
          FChannels.Delete(I);
          UpdateStatistics;
          UpdateChannelDiagnostics;
          if FChannels.Count = 0 then
            SetStatus(sbsListening, ErrorText)
          else
            SetStatus(sbsActive, ErrorText);
        end;
      end;
      Dec(I);
    end;

    if (FProfile.KeepAliveSeconds > 0) and
      (TThread.GetTickCount64 >= NextKeepAlive) then
    begin
      NowTick := TThread.GetTickCount64;
      if NowTick - LastActivityTick < KeepAliveIntervalMs then
        NextKeepAlive := LastActivityTick + KeepAliveIntervalMs
      else
      begin
        KeepAliveBlocked := False;
        if FMaster.TryKeepAlive(Self, KeepAliveResult) then
        begin
          if (KeepAliveResult <> 0) and
            (KeepAliveResult <> LIBSSH2_ERROR_EAGAIN) then
            raise ESSHLibError.Create('Master SSH keepalive failed: ' +
              FMaster.GetLastError);
          if KeepAliveResult = LIBSSH2_ERROR_EAGAIN then
          begin
            KeepAliveBlocked := True;
            if MasterKeepAliveBlockedSince = 0 then
              MasterKeepAliveBlockedSince := NowTick
            else if NowTick - MasterKeepAliveBlockedSince >=
              UInt64(FProfile.KeepAliveTimeoutMs) then
              raise ESSHLibError.Create('Master SSH keepalive timed out');
          end
          else
            MasterKeepAliveBlockedSince := 0;
        end
        else
          KeepAliveBlocked := True;

        if FReplica.TryKeepAlive(Self, KeepAliveResult) then
        begin
          if (KeepAliveResult <> 0) and
            (KeepAliveResult <> LIBSSH2_ERROR_EAGAIN) then
            raise ESSHLibError.Create('Replica SSH keepalive failed: ' +
              FReplica.GetLastError);
          if KeepAliveResult = LIBSSH2_ERROR_EAGAIN then
          begin
            KeepAliveBlocked := True;
            if ReplicaKeepAliveBlockedSince = 0 then
              ReplicaKeepAliveBlockedSince := NowTick
            else if NowTick - ReplicaKeepAliveBlockedSince >=
              UInt64(FProfile.KeepAliveTimeoutMs) then
              raise ESSHLibError.Create('Replica SSH keepalive timed out');
          end
          else
            ReplicaKeepAliveBlockedSince := 0;
        end
        else
          KeepAliveBlocked := True;

        if KeepAliveBlocked then
          NextKeepAlive := NowTick + 1000
        else
        begin
          LastActivityTick := NowTick;
          NextKeepAlive := NowTick + KeepAliveIntervalMs;
        end;
      end
    end;

    NowTick := TThread.GetTickCount64;
    if NowTick >= NextDiagnosticsTick then
    begin
      UpdateChannelDiagnostics;
      NextDiagnosticsTick := NowTick + 1000;
    end;

    if not DidWork then
      Sleep(FProfile.IdleWaitMs);
  end;
end;

function TnbSSHBridgeWorker.WaitForReconnect(ADelayMs: Integer): Boolean;
var
  Remaining, Slice: Integer;
begin
  Remaining := ADelayMs;
  while (Remaining > 0) and not Terminated do
  begin
    Slice := Remaining;
    if Slice > 100 then
      Slice := 100;
    Sleep(Slice);
    Dec(Remaining, Slice);
  end;
  Result := not Terminated;
end;

procedure TnbSSHBridgeWorker.Execute;
var
  ReconnectDelay: Integer;
begin
  ReconnectDelay := FProfile.ReconnectMinMs;
  SetStatus(sbsStarting);
  while not Terminated do
  begin
    try
      ConnectAndListen;
      ReconnectDelay := FProfile.ReconnectMinMs;
      RunForwarding;
    except
      on E: Exception do
      begin
        if not Terminated then
          SetStatus(sbsError, E.Message);
      end;
    end;

    CloseForwarding;
    if Terminated then
      Break;
    if not WaitForReconnect(ReconnectDelay) then
      Break;
    SetStatus(sbsReconnecting);
    ReconnectDelay := ReconnectDelay * 2;
    if ReconnectDelay > FProfile.ReconnectMaxMs then
      ReconnectDelay := FProfile.ReconnectMaxMs;
  end;
  CloseForwarding;
  SetStatus(sbsStopped);
end;

procedure TnbSSHBridgeWorker.RequestStop;
begin
  Terminate;
  FMaster.Interrupt;
  FReplica.Interrupt;
end;

end.
