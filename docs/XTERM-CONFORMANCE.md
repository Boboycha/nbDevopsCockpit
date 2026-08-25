# Xterm Conformance

LOCK-030 tracks terminal emulation compatibility gaps against xterm-style behavior.

## Covered

- `ESC 7` / `ESC 8` save and restore cursor position.
- `ESC M` reverse index inside the active scroll region.
- Fragmented CSI parsing across multiple `Parse` calls.
- Pending wrap at the last column, including backspace before the deferred wrap.
- `DECAWM` (`CSI ? 7 h` / `CSI ? 7 l`) autowrap enable and disable behavior.
- Insert mode (`CSI 4 h` / `CSI 4 l`).
- Origin mode (`CSI ? 6 h` / `CSI ? 6 l`) for cursor addressing inside scroll margins.
- Wide and combining character cell widths.

## Smoke Coverage

`tests/TerminalBufferSmoke/TerminalBufferSmoke.dpr` exercises the compatibility cases above without requiring an SSH session or FMX window.

Build and run:

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
dcc64 -B -Q -I"Z:\Repos\Devops\nbDevopsCockpit\src" -U"Z:\Repos\Devops\nbDevopsCockpit\src" "Z:\Repos\Devops\nbDevopsCockpit\tests\TerminalBufferSmoke\TerminalBufferSmoke.dpr"
Z:\Repos\Devops\nbDevopsCockpit\tests\TerminalBufferSmoke\TerminalBufferSmoke.exe
```

Expected output:

```text
OK
```
