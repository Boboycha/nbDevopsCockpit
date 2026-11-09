# SSH Bridge

`TnbSSHTunnelManager` provides an in-process TCP bridge over two independent
SSH sessions. It does not use `ssh.exe`, PowerShell, terminal tabs, or a PTY.

The PostgreSQL replication topology is:

```text
Replica PostgreSQL -> 127.0.0.1:15432
  -> remote listener on the Replica SSH session
  -> forwarded-tcpip channel to Windows
  -> direct-tcpip channel on the Master SSH session
  -> Master 127.0.0.1:5432
```

The manager owns both SSH sessions and all forwarding channels on one worker
thread. This keeps each libssh2 session single-threaded while allowing multiple
simultaneous PostgreSQL connections. Each direction has a bounded buffer and
supports partial reads, partial writes, EAGAIN, EOF, and half-close.

libssh2 keeps nonblocking write/open/close state inside the shared SSH session.
After one of those calls returns `LIBSSH2_ERROR_EAGAIN`, the bridge retries the
same operation with the same channel and buffer arguments before allowing a
different stateful operation on that session. Reads are not recorded as a
pending operation, but they start only while no stateful retry is pending.
The other SSH session continues to run independently. This prevents one
PostgreSQL connection from replacing another channel's pending write while
still preserving full-duplex backpressure.

## Server preflight

On the Replica SSH server, remote forwarding must be allowed:

```text
AllowTcpForwarding remote
```

`AllowTcpForwarding yes` is also sufficient. Check that `DisableForwarding`
does not disable forwarding and that `PermitListen`, when present, allows
`127.0.0.1:15432`.

On the Master SSH server, direct forwarding must be allowed. When `PermitOpen`
is used, it must allow `127.0.0.1:5432`.

Restart or reload sshd only after validating the effective configuration with
the platform's normal sshd configuration checks.

## Configuration

Credentials are deliberately not published properties and are not serialized
into FMX resources. The host application must load them from its secure secret
store immediately before `Start`.

```pascal
Bridge.Profile.Master.Host := 'master.example';
Bridge.Profile.Master.Port := 22;
Bridge.Profile.Master.User := 'bridge-user';
Bridge.Profile.Master.Password := LoadMasterPasswordFromSecretStore;
Bridge.Profile.Master.HostKeyFingerprint := 'SHA256:<verified fingerprint>';

Bridge.Profile.Replica.Host := 'replica.example';
Bridge.Profile.Replica.Port := 22;
Bridge.Profile.Replica.User := 'bridge-user';
Bridge.Profile.Replica.Password := LoadReplicaPasswordFromSecretStore;
Bridge.Profile.Replica.HostKeyFingerprint := 'SHA256:<verified fingerprint>';

Bridge.Profile.RemoteListenHost := '127.0.0.1';
Bridge.Profile.RemoteListenPort := 15432;
Bridge.Profile.TargetHost := '127.0.0.1';
Bridge.Profile.TargetPort := 5432;
Bridge.Profile.BufferSize := 1024 * 1024;
Bridge.Profile.IdleWaitMs := 1;
Bridge.Profile.KeepAliveSeconds := 10;
Bridge.Profile.KeepAliveTimeoutMs := 60000;
Bridge.Start;
```

For key authentication, set `KeyPath` and optionally `Passphrase`, or call
`SetPrivateKeyFromString` after retrieving a key from secure storage. Password,
passphrase, and in-memory private-key data are cleared when their endpoint
profile is destroyed.

Host-key verification is mandatory. Configure `HostKeyFingerprint` for both
servers or handle `OnVerifyHostKey` and explicitly approve the presented
fingerprint. Authentication is not attempted before host-key verification.

The bridge demo persists non-secret connection fields, key paths, accepted
host-key fingerprints, route settings, and the throughput profile. On Windows
the file is `%LOCALAPPDATA%\nbDevOpsCockpit\ssh-bridge-demo.ini`; on Unix it is
`$XDG_CONFIG_HOME/nbdevopscockpit/ssh-bridge-demo.ini` or, when XDG is unset,
`~/.config/nbdevopscockpit/ssh-bridge-demo.ini`. Passwords, key passphrases,
and in-memory private-key data are never written to this file.
The profile is written only after `Start` passes synchronous validation or a
host fingerprint is accepted. Closing an unused form never overwrites a saved
profile with blank defaults.

## Runtime state

The manager exposes:

- `Status`: `Stopped`, `Starting`, `Listening`, `Active`, `Reconnecting`,
  or `Error`;
- `MasterConnected` and `ReplicaConnected`;
- `ActiveChannels`;
- `RxBytes` and `TxBytes`;
- `ConnectedSinceTick`, reset after every SSH reconnect;
- `LastError`;
- `ChannelDiagnostics`, with per-channel age/idle time, byte counts, pending
  buffer offsets, last read/write results, EOF/close state, and SSH windows;
- status, statistics, error, and host-key verification events.

The demo writes a `CHANNEL` snapshot every 30 seconds while channels are
active. The log is `%LOCALAPPDATA%\nbDevOpsCockpit\ssh-bridge-demo.log` on
Windows and is stored beside the demo settings file on Unix. Error records
include the final state of the affected channel.

`Stop` affects only this bridge manager. It closes the listener, all active
channels, and both owned SSH sessions. It does not disconnect terminal or SFTP
components.

When either SSH session fails, all current forwarded connections are closed.
The manager reconnects with bounded exponential backoff and registers a new
remote listener. Existing PostgreSQL TCP connections cannot be resumed and
must reconnect normally.

Keepalive probes are sent only after `KeepAliveSeconds` without forwarded
traffic. `KeepAliveTimeoutMs` is independent from the endpoint connection
timeout, so temporary socket backpressure during a busy transfer does not
prematurely reset the bridge.

`ConnectionTimeoutMs` applies to TCP connect, SSH handshake, and authentication
only. After setup, the Synapse socket timeout is cleared and the socket is put
in nonblocking mode; an idle application channel therefore cannot become a
spurious `LIBSSH2_ERROR_SOCKET_RECV (-43)` after the connection timeout.

## Acceptance checks

From the Replica server:

```bash
pg_isready -h 127.0.0.1 -p 15432
```

When the replication role is allowed to connect to `postgres`:

```bash
psql -h 127.0.0.1 -p 15432 -U replicator -d postgres -c 'select 1'
```

Also verify at least two concurrent connections, SSH interruption and
recovery, and application shutdown with active channels. Closing a terminal
tab must not affect the bridge.

The `pg_basebackup -Xs` acceptance run must keep both the base-backup and WAL
stream channels active until completion. Use a data set of several tens of GB
and retain the demo diagnostic log. A successful build or smoke test does not
replace this long-running two-server check.

`tests/SSHBridgeSmoke/SSHBridgeSmoke.dpr` verifies the required libssh2 ABI,
the nonblocking operation gate, mandatory host-key verification, error
reporting, and bounded Start/Stop lifecycle without using real servers. It
does not replace the two-server integration test.

Do not initialize, delete, or clean a Replica `PGDATA` as part of bridge
testing. PostgreSQL version, replication permissions, WAL retention or slot
policy, and the empty target directory must be verified separately before
running `pg_basebackup`.
