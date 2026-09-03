# nbDevopsCockpit Agent Guidelines

## Role

This public repository owns reusable Delphi FMX components for SSH sessions, terminal emulation, SFTP and remote file transfer.

## Boundaries

- Keep application business rules out of this package.
- Keep transport/session ownership explicit and deterministic.
- Terminal parsing, buffer state, input routing and rendering belong here.
- SFTP protocol and reusable file-pane behavior belong here.
- Preserve public component APIs unless a coordinated breaking change is required.
- Do not include private endpoints, credentials, server names or proprietary application logic.

## Terminal Changes

- Validate parser, buffer and renderer behavior together.
- Preserve xterm control-sequence semantics, alternate-buffer behavior and scrollback invariants.
- Check keyboard input, AltGr, selection, clipboard paste and mouse behavior.
- Rendering fixes require visual runtime validation, not compilation alone.

## Source Rules

- Preserve existing Delphi encoding and line endings.
- Keep Windows, Linux and macOS code behind appropriate conditional compilation.
- Do not commit generated DCUs, BPLs, executables or local profiler output.

## Verification

Use RAD Studio `rsvars.bat` and MSBuild. Build `src/nbDevOpsCockpit.dproj` for the affected platform. Build or run `demo/nbDevOpsCockpitDemo.dproj` when visual behavior changes.

Changes used by a host application must also be validated in that consumer. State compile results and runtime checks separately.

## Git

The canonical public branch is `main`. Keep public and mirror remotes synchronized only when explicitly requested. After pushing, update the parent workspace submodule pointer.
