program SSHBridgeSmoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  nbSSH.LibSSH2,
  nbSSH.TunnelManager;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure ConfigureUnavailableEndpoint(AEndpoint: TnbSSHBridgeEndpoint);
begin
  AEndpoint.Host := '127.0.0.1';
  AEndpoint.Port := 1;
  AEndpoint.User := 'smoke';
  AEndpoint.Password := 'not-a-real-password';
  AEndpoint.HostKeyFingerprint := 'SHA256:smoke-only';
  AEndpoint.ConnectionTimeoutMs := 200;
end;

procedure CheckSessionOperationGate;
var
  Gate: TnbSSHSessionOperationGate;
  OwnerA, OwnerB: Integer;
begin
  Gate := TnbSSHSessionOperationGate.Create;
  try
    Check(Gate.TryEnter(@OwnerA, sokChannelWrite),
      'Fresh operation gate rejected a write');
    Gate.Complete(@OwnerA, sokChannelWrite, LIBSSH2_ERROR_EAGAIN,
      LIBSSH2_ERROR_EAGAIN);
    Check(Gate.IsPendingFor(@OwnerA, sokChannelWrite),
      'EAGAIN did not retain the write owner');
    Check(Gate.TryEnter(@OwnerA, sokChannelWrite),
      'Write retry with identical owner was rejected');
    Check(not Gate.TryEnter(@OwnerB, sokChannelWrite),
      'A second channel interleaved a pending write');
    Check(not Gate.TryEnter(@OwnerA, sokChannelEOF),
      'A different operation interleaved a pending write');
    Gate.Complete(@OwnerA, sokChannelWrite, 32700, LIBSSH2_ERROR_EAGAIN);
    Check(not Gate.IsPending, 'Successful partial write did not clear the gate');
    Check(Gate.TryEnter(@OwnerB, sokChannelWrite),
      'Gate remained locked after a successful partial write');
    Gate.Complete(@OwnerB, sokChannelWrite, LIBSSH2_ERROR_EAGAIN,
      LIBSSH2_ERROR_EAGAIN);
    Gate.ReleaseOwner(@OwnerB);
    Check(not Gate.IsPending, 'Releasing a channel left its operation pending');

    Check(Gate.TryEnter(@OwnerA, sokChannelWrite),
      'Gate rejected a zero-window write');
    Gate.Complete(@OwnerA, sokChannelWrite, LIBSSH2_ERROR_EAGAIN,
      LIBSSH2_ERROR_EAGAIN, False);
    Check(not Gate.IsPending,
      'Zero-window EAGAIN incorrectly retained the session gate');
    Check(Gate.TryEnter(@OwnerB, sokChannelWrite),
      'Another channel remained blocked after zero-window EAGAIN');
  finally
    Gate.Free;
  end;
end;

procedure Run;
var
  Manager: TnbSSHTunnelManager;
  StartedAt: UInt64;
  ValidationFailed: Boolean;
begin
  CheckSessionOperationGate;
  EnsureLibLoaded;
  Check(Assigned(ssh2_channel_forward_listen_ex),
    'libssh2_channel_forward_listen_ex is unavailable');
  Check(Assigned(ssh2_channel_forward_accept),
    'libssh2_channel_forward_accept is unavailable');
  Check(Assigned(ssh2_channel_forward_cancel),
    'libssh2_channel_forward_cancel is unavailable');
  Check(Assigned(ssh2_channel_direct_tcpip_ex),
    'libssh2_channel_direct_tcpip_ex is unavailable');
  Check(Assigned(ssh2_session_block_directions),
    'libssh2_session_block_directions is unavailable');

  Manager := TnbSSHTunnelManager.Create(nil);
  try
    ConfigureUnavailableEndpoint(Manager.Profile.Master);
    ConfigureUnavailableEndpoint(Manager.Profile.Replica);
    Manager.Profile.Master.HostKeyFingerprint := '';
    ValidationFailed := False;
    try
      Manager.Start;
    except
      on E: EArgumentException do
        ValidationFailed := Pos('host key', LowerCase(E.Message)) > 0;
    end;
    Check(ValidationFailed,
      'Bridge accepted an endpoint without host-key verification');

    Manager.Profile.Master.HostKeyFingerprint := 'SHA256:smoke-only';
    Manager.Profile.ReconnectMinMs := 100;
    Manager.Profile.ReconnectMaxMs := 200;
    Manager.Start;
    StartedAt := TThread.GetTickCount64;
    while (Manager.LastError = '') and
      (TThread.GetTickCount64 - StartedAt < 3000) do
    begin
      CheckSynchronize(10);
      Sleep(1);
    end;
    Check(Manager.LastError <> '',
      'Unavailable endpoint did not report a bridge error');
    Manager.Stop;
    Check(Manager.Status = sbsStopped, 'Bridge did not stop cleanly');
    Check(Manager.ActiveChannels = 0,
      'Bridge retained channels after stop');
  finally
    Manager.Free;
  end;
end;

begin
  Run;
  Writeln('SSHBridgeSmoke: PASS');
end.
