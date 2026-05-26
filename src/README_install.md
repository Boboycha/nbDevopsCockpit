# nbDevOpsCockpit вЂ” Design-Time Package РґР»СЏ Delphi/FMX
## 2026-05-26 note

`TnbFilePane` is now part of the theming contract used by nbFleet. Prefer the 6-argument `ApplyColors(ABg, ASurface, ABorder, AText, AMuted, AAccent)` when a host application has a full palette. The last two arguments are optional for older code.

Family of components for building DevOps tools.

## Р§С‚Рѕ РІРЅСѓС‚СЂРё СЃРµР№С‡Р°СЃ

| РљРѕРјРїРѕРЅРµРЅС‚ | РќР°Р·РЅР°С‡РµРЅРёРµ |
|---|---|
| `TnbSSHClient` | SSH-СЃРѕРµРґРёРЅРµРЅРёРµ С‡РµСЂРµР· libssh2 (Win/Linux/macOS) |
| `TnbTerminalControl` | Р’РёР·СѓР°Р»СЊРЅС‹Р№ xterm-256color С‚РµСЂРјРёРЅР°Р» РЅР° Skia |

РџР°Р»РёС‚СЂР° РІ IDE вЂ” `nb DevOps`.

## Р§С‚Рѕ РїР»Р°РЅРёСЂСѓРµС‚СЃСЏ РґРѕР±Р°РІРёС‚СЊ

- `TnbGitLabClient` вЂ” REST-РєР»РёРµРЅС‚ GitLab API
- `TnbServerInventory` вЂ” РёРЅРІРµРЅС‚Р°СЂСЊ СЃРµСЂРІРµСЂРѕРІ СЃ РїСЂРёРІСЏР·РєРѕР№ Рє РїСЂРѕРµРєС‚Р°Рј
- `TnbSnippetRunner` вЂ” РІС‹РїРѕР»РЅРµРЅРёРµ СЃРєСЂРёРїС‚РѕРІ РЅР° СѓРґР°Р»С‘РЅРЅС‹С… СЃРµСЂРІРµСЂР°С… С‡РµСЂРµР· SSH
- `TnbAuditLogger` вЂ” Р¶СѓСЂРЅР°Р»РёСЂРѕРІР°РЅРёРµ РґРµР№СЃС‚РІРёР№ РІ Р‘Р”

## Р¤Р°Р№Р»С‹ РїР°РєРµС‚Р°

| Р¤Р°Р№Р» | Р§С‚Рѕ |
|---|---|
| `nbDevOpsCockpit.dpk` | РћРїРёСЃР°РЅРёРµ РїР°РєРµС‚Р° |
| `nbDevOpsCockpit.dcr` | РРєРѕРЅРєРё РєРѕРјРїРѕРЅРµРЅС‚РѕРІ (24Г—24) |
| `Reg_nbDevOpsCockpit.pas` | Р РµРіРёСЃС‚СЂР°С†РёСЏ РІ РїР°Р»РёС‚СЂРµ |
| `ModernSSHClient.pas` | Р®РЅРёС‚ СЃ `TnbSSHClient` Рё worker-РїРѕС‚РѕРєРѕРј |

Р®РЅРёС‚С‹ `Terminal.*` Рё `GoghThemeLoader.pas` Р±РµСЂСѓС‚СЃСЏ РёР· С‚РІРѕРµРіРѕ РїСЂРѕРµРєС‚Р° вЂ” РїР°РєРµС‚ РЅР° РЅРёС… СЃСЃС‹Р»Р°РµС‚СЃСЏ С‡РµСЂРµР· `contains`.

## РЈСЃС‚Р°РЅРѕРІРєР° РІ Delphi (РѕРґРёРЅ СЂР°Р·)

1. **РћС‚РєСЂРѕР№ `nbDevOpsCockpit.dpk`**: File в†’ Open Project в†’ РІС‹Р±СЂР°С‚СЊ `.dpk`
2. **Project в†’ Options в†’ Delphi Compiler в†’ Search Path** вЂ” РґРѕР±Р°РІРёС‚СЊ:
   - РџР°РїРєСѓ СЃ `Terminal.*.pas` Рё `GoghThemeLoader.pas`
   - РџР°РїРєСѓ СЃ Synapse (`blcksock.pas`)
3. **Project в†’ Build** вЂ” РґРѕР»Р¶РЅРѕ СЃРѕР±СЂР°С‚СЊСЃСЏ Р±РµР· РѕС€РёР±РѕРє
4. **Project в†’ Install** вЂ” СѓРІРёРґРёС€СЊ:
   > Package nbDevOpsCockpit installed.
   > Components registered: TnbSSHClient, TnbTerminalControl

5. РќР° РїР°Р»РёС‚СЂРµ РїРѕСЏРІРёС‚СЃСЏ РІРєР»Р°РґРєР° **`nb DevOps`** СЃ РґРІСѓРјСЏ РёРєРѕРЅРєР°РјРё

Р“РѕС‚РѕРІРѕ вЂ” С‚РµРїРµСЂСЊ РєРѕРјРїРѕРЅРµРЅС‚С‹ РґРѕСЃС‚СѓРїРЅС‹ РІРѕ РІСЃРµС… РїСЂРѕРµРєС‚Р°С….

## РСЃРїРѕР»СЊР·РѕРІР°РЅРёРµ РІ С„РѕСЂРјРµ

1. **Drag** `TnbTerminalControl` РЅР° С„РѕСЂРјСѓ, `Align := Client`
2. **Drag** `TnbSSHClient` СЂСЏРґРѕРј
3. Р’ **Object Inspector** Сѓ `TerminalControl1`:
   - Р’ СЃРІРѕР№СЃС‚РІРµ `SSHClient` РёР· dropdown'Р° РІС‹Р±СЂР°С‚СЊ `SSHClient1`
4. РЈ `SSHClient1` Р·Р°РїРѕР»РЅРёС‚СЊ `Host`, `User`, `KeyPath` (РёР»Рё `Password`)
5. РљРЅРѕРїРєР° `Connect` в†’ `SSHClient1.Connect;`

Р’ Object Inspector Сѓ `TnbSSHClient` РґРѕСЃС‚СѓРїРЅС‹ СЂР°Р·РґРµР»СЊРЅС‹Рµ СЃРѕР±С‹С‚РёСЏ:
- `OnConnecting` / `OnAuthenticating` / `OnConnected` / `OnDisconnected`
- `OnError(Sender, ErrorMessage: string)`
- `OnStatusChange(Sender, Status)` вЂ” СѓРЅРёРІРµСЂСЃР°Р»СЊРЅРѕРµ
- `OnReadData(Sender, Data: string)` вЂ” РїРѕС‚РѕРє РґР°РЅРЅС‹С… РѕС‚ СЃРµСЂРІРµСЂР°

## РњРёРЅРёРјР°Р»СЊРЅС‹Р№ РїСЂРёРјРµСЂ

```pascal
procedure TFormMain.btConnectClick(Sender: TObject);
begin
  SSHClient1.Host := edHost.Text;
  SSHClient1.User := edUser.Text;
  SSHClient1.KeyPath := edKey.Text;
  SSHClient1.InitialCols := TerminalControl1.Cols;
  SSHClient1.InitialRows := TerminalControl1.Rows;
  SSHClient1.Connect;
end;

procedure TFormMain.btDisconnectClick(Sender: TObject);
begin
  SSHClient1.Disconnect;
  TerminalControl1.Clear;
end;
```

РќРёРєР°РєРѕР№ СЂСѓС‡РЅРѕР№ СЂР°Р·РІРѕРґРєРё `OnReadData` в†’ `WriteText`. РџСЂРёРІСЏР·РєР° С‡РµСЂРµР·
`TerminalControl1.SSHClient := SSHClient1` РІСЃС‘ СЂР°Р·СЂСѓР»РёРІР°РµС‚ РІ РѕР±Рµ СЃС‚РѕСЂРѕРЅС‹.

## РџР»Р°С‚С„РѕСЂРјРµРЅРЅС‹Рµ С‚СЂРµР±РѕРІР°РЅРёСЏ

| OS | Р§С‚Рѕ РЅСѓР¶РЅРѕ |
|---|---|
| Windows | `libssh2.dll` СЂСЏРґРѕРј СЃ `.exe` (РІРјРµСЃС‚Рµ СЃ `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `zlib1.dll`) |
| Linux (Rocky/RHEL) | `sudo dnf install libssh2` |
| Linux (Debian/Ubuntu) | `sudo apt install libssh2-1` |
| macOS | `brew install libssh2` |

## Multi-tab СЃРµСЃСЃРёРё

РљРѕРіРґР° РїРѕРЅР°РґРѕР±РёС‚СЃСЏ РјРЅРѕРіРѕ РІРєР»Р°РґРѕРє:
1. РЎРѕР·РґР°С‚СЊ `TFrame` СЃ `TerminalControl1` + `SSHClient1` РІРЅСѓС‚СЂРё (РїСЂРёРІСЏР·Р°С‚СЊ С‡РµСЂРµР· РґРёР·Р°Р№РЅРµСЂ)
2. Р’ runtime РєР»РѕРЅРёСЂРѕРІР°С‚СЊ frame РґР»СЏ РєР°Р¶РґРѕР№ РЅРѕРІРѕР№ РІРєР»Р°РґРєРё

РђСЂС…РёС‚РµРєС‚СѓСЂР° `TnbSSHClient` СѓР¶Рµ РїРѕРґРґРµСЂР¶РёРІР°РµС‚ РјРЅРѕР¶РµСЃС‚РІРµРЅРЅС‹Рµ РЅРµР·Р°РІРёСЃРёРјС‹Рµ СЌРєР·РµРјРїР»СЏСЂС‹ вЂ” РєР°Р¶РґС‹Р№ СЃРѕ СЃРІРѕРёРј worker-thread'РѕРј.

## РЈРґР°Р»РµРЅРёРµ РїР°РєРµС‚Р°

Component в†’ Install Packages в†’ РІС‹Р±СЂР°С‚СЊ `nbDevOpsCockpit` в†’ Remove.
