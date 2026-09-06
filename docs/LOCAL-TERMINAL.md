# Local terminal

`TnbTerminalControl` can now host a local shell using the same ANSI parser,
buffer, renderer, input handling and themes as its SSH sessions.

The demo has a **Local terminal** button. Disconnect the current session before
switching between SSH and local mode. The existing Disconnect button stops
either kind of session.

## Usage

```pascal
uses
  System.SysUtils, System.Classes, FMX.Forms, Terminal.Control;

procedure TMainForm.OpenLocalTerminal;
begin
  // Windows: Windows PowerShell. Linux/macOS: $SHELL, falling back to /bin/sh.
  TerminalControl1.StartLocalSession;
end;

procedure TMainForm.CloseLocalTerminal;
begin
  TerminalControl1.StopLocalSession;
end;
```

To choose an executable, argument array and working directory:

```pascal
{$IFDEF MSWINDOWS}
TerminalControl1.StartLocalSession('cmd.exe', ['/d'], 'C:\Work');
// Or a full path to pwsh.exe with ['-NoLogo'].
{$ELSE}
TerminalControl1.StartLocalSession('/bin/bash', ['-i'], '/tmp');
// macOS: /bin/zsh with ['-i'].
{$ENDIF}
```

Arguments are separate values, not a prequoted command line. POSIX executables
must use absolute paths. The working directory must exist; an empty directory
selects the user's home directory. An explicit directory takes precedence.
Empty POSIX arguments select `-i`. The default Windows shell displays its normal
startup banner and loads the user's normal profile. A profile can itself change
the prompt or working directory. Local processes run with the host application's
privileges.

`LocalSession` is nil before the first start. Afterwards it exposes `Running`,
`SendText`, `OnExit` and `OnError`. The control owns and frees it; do not free it
or replace its `OnReadData` handler. `OnHostOutput` remains available for observing
or filtering output. Assigning a non-nil `SSHClient` stops the local session;
starting local mode while SSH is connected/connecting raises an exception.

For a nonvisual consumer, create `TnbLocalTerminalSession` from
`Terminal.LocalSession`, assign `OnReadData`, and call `Pump` regularly on its
owning thread. `OnExit` supplies the process exit code (or -1 if unavailable).
An explicit `Stop` does not emit `OnExit`. Start/Stop/SendText/ResizePTY/Pump and
event handlers belong to the same thread. Do not destroy the session from inside
its callbacks. Workers never synchronize with or queue callbacks to the UI.

## Platform implementation

- Windows 10 1809+ / Windows Server 2019+: ConPTY, UTF-8 pipes, a job object
  containing the shell and its children. No separate console window is created.
- Linux: `openpty` from libutil, a new session/controlling terminal, `execve`,
  `TIOCSWINSZ`. Link against libutil through the platform SDK.
- Desktop macOS Intel/Apple Silicon: `openpty` from libSystem, the same POSIX
  session lifecycle and the Darwin window-size ioctl. An application distributed
  with App Sandbox must separately satisfy its process-launch restrictions.
- Mobile targets compile with an explicit unsupported-platform error on Start.

POSIX children receive `TERM=xterm-256color` and `COLORTERM=truecolor`; the rest
of the environment is inherited. All arguments/environment buffers are prepared
before fork. The child resets terminal-related signals, closes inherited file
descriptors and performs only native operations before exec.

Read and write use separate workers. Queues are bounded to 4 MiB; output applies
backpressure, and excess input is rejected before enqueueing rather than silently
truncated. Pump consumes at most 256 KiB per call and preserves split UTF-8.
ConPTY teardown keeps its reader alive to drain the final frame. On POSIX, Stop
terminates the foreground process group and shell group, reaps the shell and
closes the PTY. Processes that deliberately detach into another session are not
owned by this terminal. The host must not independently reap this session's
child (for example with a global `waitpid(-1, ...)` handler).

## Verification

`tests/LocalTerminalSmoke/LocalTerminalSmoke.dpr` checks interactive input/output,
PTY resize, exit status, repeated start/stop, shutdown with queued input or unread
output, and invalid executable cleanup. Windows also checks Cyrillic and emoji
through the actual ConPTY output path. Build in that test directory with Delphi;
keep all executable/DCU/object output in `bin/local-smoke/<platform>`.

`LocalTerminalVisual.dpr` is an FMX runtime probe. It starts a local shell, writes
a coloured marker, resizes the form, saves `local-terminal.png` beside the
executable and closes its session. Include `src`, Synapse and the FMX RTL in its
search path; deploy Skia as for the regular demo.

Validated in this workspace:

- Windows x64: package and demo builds; console smoke suite; FMX runtime image
  showing PowerShell, coloured output and a resized terminal.
- Linux x64: Delphi console smoke suite executed in local Ubuntu WSL.
- macOS Intel and Apple Silicon: compilation of both new units. Runtime and
  linking against a macOS SDK still need validation on a Mac.
- Existing `TerminalBufferSmoke`: passed.

Before release, exercise interactive applications (PowerShell/PSReadLine, bash,
zsh, vim/top), Ctrl+C, Ctrl+D, Tab, AltGr, selection, clipboard paste, mouse
tracking, alternate screen and repeated window close on the target desktops.
The automated tests do not establish full terminal conformance.

References: [ConPTY lifecycle](https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session),
[fork and exec constraints](https://man7.org/linux/man-pages/man2/fork.2.html).
