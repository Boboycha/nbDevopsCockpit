# nbDevOpsCockpit

[Русский](README.md) | **English**

A **Delphi / FireMonkey (FMX)** component package for building DevOps tooling.
Cross-platform — Windows, Linux, macOS. Rendering powered by [Skia](https://skia.org/).

## Demo

A ready-to-run Windows x64 portable demo is published in [GitHub Releases](https://github.com/Boboycha/nbDevopsCockpit/releases/tag/demo-latest). The archive contains `nbDevOpsCockpitDemo.exe`, `libssh2.dll`, `sk4d.dll`, and terminal themes.

[Download portable demo](https://github.com/Boboycha/nbDevopsCockpit/releases/download/demo-latest/nbDevOpsCockpitDemo-Win64-portable.zip)

## Contents

| Component | Purpose |
|-----------|---------|
| `TnbSSHClient` | SSH connection via `libssh2` (loaded dynamically) |
| `TnbSSHTunnelManager` | Independent two-session SSH TCP bridge with remote/direct forwarding |
| `TnbTerminalControl` | Visual `xterm-256color` terminal |
| `TnbFilePane` | Local/SFTP file browser pane with themeable toolbar, rows, and drag/drop transfer hooks |

Components register in the IDE palette under the **`nb DevOps`** tab.

### File pane theming

`TnbFilePane.ApplyColors(ABg, ASurface, ABorder, AText, AMuted, AAccent)` lets
host applications drive the file browser from their own palette. The final two
arguments are optional for older callers, but passing them is recommended so
icons, selected rows, row separators, and drop indicators match the active app
theme.

### Terminal features

- ANSI/VT: CSI, OSC, SGR, G0/G1 character sets, device query replies (DA/DSR)
- 16/256 colors and 24-bit truecolor
- Primary and alternate buffers, scrolling region, scrollback history
- Wide characters (CJK), emoji and ZWJ sequences
- Mouse selection, copy/paste, bracketed paste
- Mouse reporting (modes 1000/1002/1003/1006 SGR)
- Color themes in the [Gogh](https://github.com/Gogh-Co/Gogh) format (YAML)

### SSH client features

- Password and public-key authentication (key from file or from memory)
- Host key verification through the `OnVerifyHostKey` event (SHA256 fingerprint)
- Runs on a background thread, correct UTF-8 splitting on byte boundaries
- Live PTY resize

## Repository layout

```
src/    — component package sources
demo/   — FMX demo application showing the SSH + terminal pairing
```

## Dependencies

Required dependencies:

| Library | Kind | Purpose | Source |
|---------|------|---------|--------|
| [UniListView](https://github.com/Boboycha/UniListView) | build-time and runtime | `UniListViewRuntime` package used by `TnbFilePane` | GitHub |
| [Ararat Synapse](https://github.com/geby/synapse) | build-time | `blcksock`, `synsock`, and other network units | GitHub |
| libssh2 | runtime | SSH protocol implementation | see "Platform requirements" |

Only the package's `synacode.pas` is vendored under `third_party/synapse`.
The complete Ararat Synapse source directory must still be available through
the Delphi Library Path or Project Search Path.
Skia ships with RAD Studio 12 and newer — no separate installation needed.

## Installation

Clone the repositories as siblings:

```text
workdir/
|- UniListView/
`- nbDevopsCockpit/
```

Open `CockpitGroup.groupproj`. The group builds `UniListViewRuntime` for the
selected platform before `nbDevOpsCockpit` and the demo. After a successful
build, install `src/nbDevOpsCockpit.dpk` in the IDE.

For a manual installation, first build
`UniListView/packages/UniListViewRuntime.dproj` for the same platform (`Win32`
for the 32-bit IDE, `Win64` for the 64-bit IDE), then build
`src/nbDevOpsCockpit.dproj`. `E2202 Required package 'UniListViewRuntime' not
found` means that the runtime-package DCP for the selected platform has not
been built or its directory is missing from the Library Path.

Also add the complete Ararat Synapse source directory to the Library Path or
Project Search Path. Otherwise compilation stops with `Unit 'blcksock' not
found`.

Additional development rules are in the [Developer Guide](docs/DEVELOPER_GUIDE.md).

## Quick start

```pascal
procedure TFormMain.btConnectClick(Sender: TObject);
begin
  // TerminalControl1.SSHClient := SSHClient1 — the link is set in the designer
  SSHClient1.Host := edHost.Text;
  SSHClient1.User := edUser.Text;
  SSHClient1.KeyPath := edKey.Text;
  SSHClient1.Connect;
end;
```

Binding `TnbTerminalControl.SSHClient := SSHClient1` wires data both ways
automatically — no manual `OnReadData` → `WriteText` plumbing required.

## Platform requirements

The `libssh2` library is required:

| OS | Installation |
|----|--------------|
| Windows | `libssh2.dll` next to the `.exe` (+ `libcrypto`, `libssl`, `zlib1`) |
| Linux (RHEL/Rocky) | `sudo dnf install libssh2` |
| Linux (Debian/Ubuntu) | `sudo apt install libssh2-1` |
| macOS | `brew install libssh2` |

## Status

The project is under active development. Planned components: `TnbGitLabClient`,
`TnbServerInventory`, `TnbSnippetRunner`, `TnbAuditLogger`.

## Project Documentation

- [Developer Guide](docs/DEVELOPER_GUIDE.md)
- [SSH Bridge](docs/SSH-BRIDGE.md)

## License

Original project code is licensed under the Mozilla Public License 2.0.
Bundled dependency licenses are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
