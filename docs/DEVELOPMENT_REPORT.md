# Development Report: nbDevOpsCockpit

Date: 2026-06-01

## Summary

`nbDevOpsCockpit` provides the low-level DevOps UI and protocol components used by `nbFleet`: SSH sessions, terminal rendering, SFTP file browsing and streaming file transfer.

The repository is now positioned as a reusable component package rather than only an application helper folder.

## Completed Work

- SSH connection component based on libssh2.
- FMX terminal control with ANSI/VT output rendering.
- SFTP client and reusable file pane.
- Streaming SFTP transfer worker for server-to-server copy without full local staging.
- Transfer progress and cancel support.
- Temporary-file cleanup on cancelled transfer.
- File pane theme integration used by `nbFleet`.
- Design-time registration cleanup after package reorganization.
- Initial cross-platform checks for Windows/Linux-sensitive code.

## Current Consumers

- `nbFleet` uses the package for terminal tabs, SFTP panels, embedded file panes and transfer operations.

## Important Decisions

- Keep protocol/session logic in this package, not in `nbFleet`.
- Keep visual file-pane behavior reusable: the host app supplies data, events and theme colors.
- Use streaming transfer worker for remote-to-remote file copy.
- Keep normal SSH/SFTP client cleanup graceful, but avoid blocking cleanup paths for temporary transfer sessions.

## Known Risks

- libssh2 cleanup and non-blocking behavior are sensitive. Long transfers and failed sessions should be tested carefully.
- Linux runtime library names and deployment still need real machine verification.
- Some terminal behavior is pragmatic, not a full xterm clone.
- `TnbFilePane` is reusable, but the public API should stay conservative until more host screens use it.
- If Delphi package dependencies are changed, design-time registration can break quickly. FMX is dramatic like that.

## Recommended Next Steps

1. Add a small automated smoke demo for SSH/SFTP connection lifecycle.
2. Add transfer resume support on top of the current streaming worker.
3. Consolidate libssh2 loader/error reporting in one place.
4. Run Linux64 build and runtime checks.
5. Document deployment of libssh2/OpenSSL/zlib for each platform.
