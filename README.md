# nbDevOpsCockpit
## 2026-05-26 note

`TnbFilePane` supports app-driven palette colors through `ApplyColors(ABg, ASurface, ABorder, AText, AMuted, AAccent)`. nTizgin uses this so SFTP/file panes follow the active terminal theme. The last two arguments are optional for older callers.

Development boundaries and integration notes are maintained in [Developer Guide](docs/DEVELOPER_GUIDE.md). Terminal behavior is tracked in [XTERM Conformance](docs/XTERM-CONFORMANCE.md).

**Русский** | [English](README.en.md)

Пакет компонентов **Delphi / FireMonkey (FMX)** для построения DevOps-инструментов.
Кросс-платформенный — Windows, Linux, macOS. Рендеринг на [Skia](https://skia.org/).

## Демо

Готовая portable-сборка демо для Windows x64 публикуется в [GitHub Releases](https://github.com/Boboycha/nbDevopsCockpit/releases/tag/demo-latest). Архив содержит `nbDevOpsCockpitDemo.exe`, `libssh2.dll`, `sk4d.dll` и темы терминала.

[Скачать portable demo](https://github.com/Boboycha/nbDevopsCockpit/releases/download/demo-latest/nbDevOpsCockpitDemo-Win64-portable.zip)

## Состав

| Компонент | Назначение |
|-----------|-----------|
| `TnbSSHClient` | SSH-соединение через `libssh2` (динамическая загрузка библиотеки) |
| `TnbTerminalControl` | Визуальный терминал `xterm-256color` |

Компоненты регистрируются в палитре IDE на вкладке **`nb DevOps`**.

### Возможности терминала

- ANSI/VT: CSI, OSC, SGR, наборы символов G0/G1, ответы на запросы устройства (DA/DSR)
- 16/256 цветов и truecolor (24 бита)
- Основной и альтернативный буферы, регион скроллинга, история (scrollback)
- Wide-символы (CJK), эмодзи и ZWJ-последовательности
- Выделение мышью, копирование/вставка, bracketed paste
- Отчёты мыши (режимы 1000/1002/1003/1006 SGR)
- Цветовые темы в формате [Gogh](https://github.com/Gogh-Co/Gogh) (YAML)

### Возможности SSH-клиента

- Аутентификация по паролю и по ключу (файл или ключ из памяти)
- Проверка ключа хоста через событие `OnVerifyHostKey` (SHA256-отпечаток)
- Работа в фоновом потоке, корректная нарезка UTF-8 на границах байтов
- Изменение размера PTY на лету

## Структура репозитория

```
src/    — исходники пакета компонентов
demo/   — демо-приложение FMX, показывающее связку SSH + терминал
```

## Зависимости

Обязательные зависимости:

| Библиотека | Тип | Назначение | Где взять |
|------------|-----|-----------|-----------|
| [UniListView](https://github.com/Boboycha/UniListView) | время сборки и выполнения | runtime-пакет `UniListViewRuntime`, используемый `TnbFilePane` | GitHub |
| [Ararat Synapse](https://github.com/geby/synapse) | время сборки | `blcksock`, `synsock` и другие сетевые модули | GitHub |
| libssh2 | время выполнения | реализация протокола SSH | см. «Платформенные требования» |

В `third_party/synapse` находится только используемый пакетом `synacode.pas`;
для сборки всё равно требуется полный каталог исходников Ararat Synapse в
Delphi Library Path или Project Search Path.
Skia входит в состав RAD Studio 12 и новее — отдельная установка не нужна.

## Установка

Разместите репозитории рядом:

```text
workdir/
|- UniListView/
`- nbDevopsCockpit/
```

Откройте `CockpitGroup.groupproj`: группа сначала собирает
`UniListViewRuntime` для выбранной платформы, затем `nbDevOpsCockpit` и демо.
После успешной сборки установите `src/nbDevOpsCockpit.dpk` в IDE.

При ручной установке сначала соберите
`UniListView/packages/UniListViewRuntime.dproj` для той же платформы
(`Win32` для 32-битной IDE, `Win64` для 64-битной), затем собирайте
`src/nbDevOpsCockpit.dproj`. Ошибка `E2202 Required package
'UniListViewRuntime' not found` означает, что DCP runtime-пакета для выбранной
платформы ещё не собран или его каталог отсутствует в Library Path.

Перед сборкой также добавьте каталог полного Ararat Synapse в Library Path или
Project Search Path. Иначе компилятор остановится на `Unit 'blcksock' not found`.

Дополнительные правила разработки описаны в [руководстве разработчика](docs/DEVELOPER_GUIDE.md).

## Быстрый старт

```pascal
procedure TFormMain.btConnectClick(Sender: TObject);
begin
  // TerminalControl1.SSHClient := SSHClient1 — связка задаётся в дизайнере
  SSHClient1.Host := edHost.Text;
  SSHClient1.User := edUser.Text;
  SSHClient1.KeyPath := edKey.Text;
  SSHClient1.Connect;
end;
```

Привязка `TnbTerminalControl.SSHClient := SSHClient1` разводит данные в обе
стороны автоматически — ручного `OnReadData` → `WriteText` не требуется.

## Платформенные требования

Нужна библиотека `libssh2`:

| ОС | Установка |
|----|-----------|
| Windows | `libssh2.dll` рядом с `.exe` (+ `libcrypto`, `libssl`, `zlib1`) |
| Linux (RHEL/Rocky) | `sudo dnf install libssh2` |
| Linux (Debian/Ubuntu) | `sudo apt install libssh2-1` |
| macOS | `brew install libssh2` |

## Статус

Проект в активной разработке. Запланированы компоненты `TnbGitLabClient`,
`TnbServerInventory`, `TnbSnippetRunner`, `TnbAuditLogger`.

## Документация проекта

- [Руководство разработчика](docs/DEVELOPER_GUIDE.md)
