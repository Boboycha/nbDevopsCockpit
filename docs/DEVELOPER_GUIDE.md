# Developer Guide: nbDevOpsCockpit

## Purpose

Use this package when an FMX application needs SSH, terminal, SFTP or file-transfer building blocks.

The package should not know about `nbFleet` business rules. It may expose events and reusable components; the host application decides what to do with selected servers, files and actions.

## Build Order

1. Make sure Synapse is available at `Z:\VCL\synapse` or update the project search path.
2. Make sure libssh2 headers/import/runtime assumptions match the target platform.
3. Build the package:

```powershell
msbuild src\nbDevOpsCockpit.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

4. Optional: build the demo project.

## Main Units

- `ModernSSHClient.pas` - high-level SSH client component.
- `Terminal.Control.pas` - FMX terminal control.
- `nbSFTPClient.pas` - SFTP client/session layer.
- `nbSFTPTransfer.pas` - streaming transfer worker.
- `nbFilePane.pas` - reusable file panel component.
- `nbFilePane.Controls.pas` - visual helper controls for file pane rows/toolbars.
- `nbSSH.LibSSH2.pas` - libssh2 dynamic loading helpers.
- `nbSSH.KeyValidation.pas` - SSH key validation helpers.

## Ownership Rules

- Components placed on forms/frames should be owned by that form/frame.
- Temporary worker sessions must be owned/freed by the worker code that created them.
- Do not let protocol objects outlive the thread/session that owns their socket.
- UI controls must be updated on the FMX UI thread.

## Threading Rules

SSH/SFTP operations can block. Keep long operations away from the UI thread.

For transfer workers:

- Report progress through events.
- Support cancellation between chunks.
- Clean up partial target files when cancellation happens before completion.
- Avoid graceful shutdown paths that can block forever after the socket is already unusable.

## Theming

`TnbFilePane` is theme-aware but should not pull global application state by itself. Prefer passing palette/colors from the host application.

When adding themed controls:

- Keep icon glyph text separate from translated captions.
- Do not hard-code Windows-only icon fonts unless the component has a fallback.
- Avoid changing layout in hover/active state.

## SFTP Transfer Notes

The streaming worker copies data from source SFTP handle to target SFTP handle by chunks. It should not stage the whole file locally.

When changing buffer sizes or read/write loops, verify:

- Same-server copy.
- Server-to-server copy across different networks.
- Cancellation mid-transfer.
- Failed target connection.
- Failed source read.
- Cleanup after close.

## Platform Notes

Windows:

- DLLs must be near exe or in `PATH`.
- Watch for Windows-only units in shared units.

Linux/macOS:

- Use conditional compilation for platform units.
- Do not assume MDL2 icon fonts exist.
- Check shared library names and loader paths.

## Integration Checklist

Before consuming a component in another repo:

1. Put the package in the project group.
2. Add `src` to search path only if the package is not installed.
3. Place visual components at design time where possible.
4. Assign event handlers in the host form/frame.
5. Keep host-specific persistence outside this package.
