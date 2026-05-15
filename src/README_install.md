# nbDevOpsCockpit — Design-Time Package для Delphi/FMX

Family of components for building DevOps tools.

## Что внутри сейчас

| Компонент | Назначение |
|---|---|
| `TnbSSHClient` | SSH-соединение через libssh2 (Win/Linux/macOS) |
| `TnbTerminalControl` | Визуальный xterm-256color терминал на Skia |

Палитра в IDE — `nb DevOps`.

## Что планируется добавить

- `TnbGitLabClient` — REST-клиент GitLab API
- `TnbServerInventory` — инвентарь серверов с привязкой к проектам
- `TnbSnippetRunner` — выполнение скриптов на удалённых серверах через SSH
- `TnbAuditLogger` — журналирование действий в БД

## Файлы пакета

| Файл | Что |
|---|---|
| `nbDevOpsCockpit.dpk` | Описание пакета |
| `nbDevOpsCockpit.dcr` | Иконки компонентов (24×24) |
| `Reg_nbDevOpsCockpit.pas` | Регистрация в палитре |
| `ModernSSHClient.pas` | Юнит с `TnbSSHClient` и worker-потоком |

Юниты `Terminal.*` и `GoghThemeLoader.pas` берутся из твоего проекта — пакет на них ссылается через `contains`.

## Установка в Delphi (один раз)

1. **Открой `nbDevOpsCockpit.dpk`**: File → Open Project → выбрать `.dpk`
2. **Project → Options → Delphi Compiler → Search Path** — добавить:
   - Папку с `Terminal.*.pas` и `GoghThemeLoader.pas`
   - Папку с Synapse (`blcksock.pas`)
3. **Project → Build** — должно собраться без ошибок
4. **Project → Install** — увидишь:
   > Package nbDevOpsCockpit installed.
   > Components registered: TnbSSHClient, TnbTerminalControl

5. На палитре появится вкладка **`nb DevOps`** с двумя иконками

Готово — теперь компоненты доступны во всех проектах.

## Использование в форме

1. **Drag** `TnbTerminalControl` на форму, `Align := Client`
2. **Drag** `TnbSSHClient` рядом
3. В **Object Inspector** у `TerminalControl1`:
   - В свойстве `SSHClient` из dropdown'а выбрать `SSHClient1`
4. У `SSHClient1` заполнить `Host`, `User`, `KeyPath` (или `Password`)
5. Кнопка `Connect` → `SSHClient1.Connect;`

В Object Inspector у `TnbSSHClient` доступны раздельные события:
- `OnConnecting` / `OnAuthenticating` / `OnConnected` / `OnDisconnected`
- `OnError(Sender, ErrorMessage: string)`
- `OnStatusChange(Sender, Status)` — универсальное
- `OnReadData(Sender, Data: string)` — поток данных от сервера

## Минимальный пример

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

Никакой ручной разводки `OnReadData` → `WriteText`. Привязка через
`TerminalControl1.SSHClient := SSHClient1` всё разруливает в обе стороны.

## Платформенные требования

| OS | Что нужно |
|---|---|
| Windows | `libssh2.dll` рядом с `.exe` (вместе с `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `zlib1.dll`) |
| Linux (Rocky/RHEL) | `sudo dnf install libssh2` |
| Linux (Debian/Ubuntu) | `sudo apt install libssh2-1` |
| macOS | `brew install libssh2` |

## Multi-tab сессии

Когда понадобится много вкладок:
1. Создать `TFrame` с `TerminalControl1` + `SSHClient1` внутри (привязать через дизайнер)
2. В runtime клонировать frame для каждой новой вкладки

Архитектура `TnbSSHClient` уже поддерживает множественные независимые экземпляры — каждый со своим worker-thread'ом.

## Удаление пакета

Component → Install Packages → выбрать `nbDevOpsCockpit` → Remove.
