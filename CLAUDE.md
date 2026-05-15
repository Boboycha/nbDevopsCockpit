# Инструкции для AI-агентов

Этот файл — контекст для Claude Code и других агентов, работающих с репозиторием.

## О проекте

`nbDevOpsCockpit` — дизайн-тайм пакет компонентов **Delphi / FireMonkey (FMX)**
для DevOps-инструментов. Кросс-платформенный (Windows / Linux / macOS),
рендеринг на Skia, SSH через `libssh2`.

## Язык

- Общение с пользователем — **полностью на русском**.
- Комментарии в коде — на русском, файлы сохранять в **UTF-8**.
- Комментарии должны быть пригодны для публикации (репозиторий открытый):
  без черновых пометок, без битой кодировки.

## Структура

```
src/    — исходники пакета компонентов (.pas, .dpk, .dproj, .dcr, .res)
demo/   — демо-приложение FMX (nbDevOpsCockpitDemo)
```

Папки `__history/` и `__recovery/` — резервные копии IDE, в `.gitignore`,
**не редактировать и не использовать как источник истины**.

## Соглашения по именованию

- **Регистрируемые компоненты** именуются с префиксом `Tnb`
  (`TnbSSHClient`, `TnbTerminalControl`, планируемые `TnbGitLabClient` и т.д.).
- Внутренние и вспомогательные классы под правило не подпадают
  (`TSSHWorkerThread`, `TTerminalBuffer`, `TAnsiParser`, `TTerminalTheme`).

## Архитектура (юниты в src/)

| Юнит | Роль |
|------|------|
| `ModernSSHClient.pas` | `TnbSSHClient` + фоновый `TSSHWorkerThread`, биндинг к `libssh2` |
| `Terminal.Types.pas` | базовые типы, метрики символов (ширина, emoji, псевдографика) |
| `Terminal.Theme.pas` | `TTerminalTheme` — палитра ANSI-цветов |
| `Terminal.Buffer.pas` | модель экрана: буферы, scrollback, выделение, регион скролла |
| `Terminal.AnsiParser.pas` | конечный автомат разбора ANSI/VT-последовательностей |
| `Terminal.Renderer.pas` | отрисовка буфера через Skia (back-buffer, кэш шрифтов) |
| `Terminal.Control.pas` | `TnbTerminalControl` — визуальный контрол, склейка всех слоёв |
| `GoghThemeLoader.pas` | загрузка цветовых тем из YAML-формата Gogh |
| `Reg_nbDevOpsCockpit.pas` | регистрация компонентов в палитре IDE |

Поток данных:
`libssh2 → TnbSSHClient → AnsiParser → Buffer → Renderer → TnbTerminalControl`
и обратно (ввод/resize → SSH).

## Демо-приложение (demo/)

Панель управления (`Panel1`, высота 33 px) содержит:
- **«Подключить» / «Отключить»** — `TCornerButton`, обёртки над `SSHClient1.Connect/Disconnect`.
- **Комбобокс `cbTheme`** (`FMX.ListBox.TComboBox`) — перечисляет темы Gogh из папки `themes\`.
  Первый пункт «По умолчанию» вызывает `TnbTerminalControl.LoadDefaultTheme`.
  Последующие пункты — `LoadThemeFromFile` по `FThemes[Idx].FileName`.
- **Кнопка `...` (`btnBrowse`)** — открывает `TOpenDialog` для загрузки произвольного `.yml`.

Логика поиска папки с темами (`FormCreate`):
1. `<exe_dir>\themes\` — для развёрнутого приложения.
2. `ExpandFileName(<exe_dir> + '..\..\..\..\demo\themes\')` — запасной путь при запуске
   из `bin\demo\Win64\Debug\` во время разработки (ведёт в `demo\themes\` репозитория).

В `demo/themes/` хранятся 365 `.yml`-файлов тем из проекта
[Gogh](https://github.com/Gogh-Co/Gogh); папка отслеживается в git.

### Зависимость libssh2.dll

`TnbSSHClient` загружает `libssh2.dll` динамически через `SafeLoadLibrary`.
DLL нет в репозитории (`*.dll` в `.gitignore`). Для работы демо файл нужно
разместить рядом с `nbDevOpsCockpitDemo.exe`.

Проверенная сборка: **WinCNG-backend** (зависит только от системных DLL Windows —
`bcrypt.dll`, `ws2_32.dll` и т.д.; OpenSSL не нужен). Такая сборка есть, например,
в установленном Termius:
`%LOCALAPPDATA%\Programs\Termius\resources\app.asar.unpacked\node_modules\@termius\libtermius\win-x64\libssh2.dll`

## Сборка и проверка

- Проект собирается в RAD Studio (`src/nbDevOpsCockpit.dpk`, демо `demo/nbDevOpsCockpitDemo.dproj`).
- Поддерживается CLI-сборка через MSBuild:
  ```
  call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
  msbuild demo\nbDevOpsCockpitDemo.dproj /t:Build /p:Config=Debug /p:Platform=Win64
  ```
- Автоматических тестов нет.
- После правок проверять корректность по диагностике Delphi LSP (если доступна).

## На что обращать внимание

- `.res`, `.dcr` — бинарные файлы; текстовым редактированием не правятся.
  При переименовании компонента иконки в `.dcr` нужно пересоздавать вручную.
- Зависимость `blcksock` (Synapse) подключается через путь поиска, не через `requires`.
- Пакет помечен `{$DESIGNONLY}`, хотя содержит рантайм-код — известная
  архитектурная особенность; демо линкует юниты статически.
- Не коммитить файлы с абсолютными путями машины (`.vscode/`, `*.local`,
  `*.delphilsp.json`) — они уже в `.gitignore`.
- `TCharacter` (устарел с Delphi 12) заменён на `TCharHelper`: методы вызываются
  прямо на переменной типа `Char` — `Ch.IsHighSurrogate`, `Ch.IsLowSurrogate`.
  Юнит `System.Character` в `uses` при этом остаётся обязательным.
- `TComboBox` в FMX находится в `FMX.ListBox`, а не в `FMX.StdCtrls`.
  Это неочевидно: в палитре IDE он в группе «Standard», но юнит другой.
