# nbDevOpsCockpit

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

Сторонние библиотеки, необходимые для сборки (в репозиторий **не входят**):

| Библиотека | Тип | Назначение | Где взять |
|------------|-----|-----------|-----------|
| [Ararat Synapse](http://synapse.ararat.cz/) | время сборки | TCP-сокет (`blcksock.pas`), на котором работает libssh2 | synapse.ararat.cz |
| libssh2 | время выполнения | реализация протокола SSH | см. «Платформенные требования» |

Synapse подключается через путь поиска проекта (см. инструкцию по установке).
Skia входит в состав RAD Studio 12 и новее — отдельная установка не нужна.

## Установка

Кратко: открыть `src/nbDevOpsCockpit.dpk` в RAD Studio, прописать пути поиска,
собрать и установить пакет.

Подробная пошаговая инструкция — в [src/README_install.md](src/README_install.md).

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
