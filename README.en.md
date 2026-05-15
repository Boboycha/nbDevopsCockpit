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
| `TnbTerminalControl` | Visual `xterm-256color` terminal |

Components register in the IDE palette under the **`nb DevOps`** tab.

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

Third-party libraries required to build the package (**not** bundled in the repo):

| Library | Kind | Purpose | Source |
|---------|------|---------|--------|
| [Ararat Synapse](http://synapse.ararat.cz/) | build-time | TCP socket (`blcksock.pas`) that libssh2 runs on top of | synapse.ararat.cz |
| libssh2 | runtime | SSH protocol implementation | see "Platform requirements" |

Synapse is wired in via the project search path (see the installation guide).
Skia ships with RAD Studio 12 and newer — no separate installation needed.

## Installation

In short: open `src/nbDevOpsCockpit.dpk` in RAD Studio, set the search paths,
build and install the package.

A detailed step-by-step guide is in [src/README_install.md](src/README_install.md)
(in Russian).

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
