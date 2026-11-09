# nbDevOpsCockpit

`nbDevOpsCockpit` - Delphi FMX uchun DevOps komponentlar paketi. Unda SSH, terminal, SFTP va fayl panel komponentlari bor. Paket `nTizgin` ichida ishlatiladi.

Tillar: [Русский](README.md) | [English](README.en.md) | [O'zbekcha](README.uz.md)

## Ichida nimalar bor

- `TnbSSHClient` - libssh2 asosidagi SSH komponent.
- `TnbSSHTunnelManager` - ikkita mustaqil SSH sessiyasi orqali TCP ko'prik.
- `TnbTerminalControl` - ANSI/VT chizish va scrollback bilan FMX terminal.
- `TnbSFTPClient` - fayl amallari uchun SFTP klient.
- `TnbFilePane` - lokal/SFTP fayl paneli.
- `TnbSFTPTransfer` - serverdan serverga oqimli fayl uzatish worker'i.
- SSH kalitlarini tekshirish va libssh2 yuklash yordamchilari.

## Hozirgi holat

Paket `nTizgin` tomonidan faol ishlatiladi. Windows x64 va Linux uchun platformaga bog'liq joylarda shartli kompilyatsiyani alohida tekshirish kerak.

## Bog'liqliklar

- Delphi 13.1 / RAD Studio 13.1
- FireMonkey
- [UniListView](https://github.com/Boboycha/UniListView) runtime paketi
- [Ararat Synapse](https://github.com/geby/synapse) to'liq manba katalogi
- libssh2 runtime kutubxonasi
- libssh2 yig'ilishiga qarab OpenSSL/zlib runtime kutubxonalari

`third_party/synapse` ichida faqat `synacode.pas` bor. `blcksock`, `synsock` va
boshqa modullar uchun to'liq Ararat Synapse katalogini Delphi Library Path yoki
Project Search Path ichiga qo'shish kerak.

## Yig'ish

Repozitoriylarni yonma-yon joylashtiring:

```text
workdir/
|- UniListView/
`- nbDevopsCockpit/
```

`CockpitGroup.groupproj` faylini oching. Guruh avval tanlangan platforma uchun
`UniListViewRuntime`, keyin `nbDevOpsCockpit` va demo loyihasini yig'adi.

Qo'lda yig'ishda avval ayni platforma uchun
`UniListView/packages/UniListViewRuntime.dproj`, keyin quyidagi paketni
yig'ing. `E2202 Required package 'UniListViewRuntime' not found` xatosi mos
platforma DCP fayli hali yig'ilmaganini yoki uning katalogi Library Path ichida
yo'qligini bildiradi.

To'liq Ararat Synapse katalogi yo'lda bo'lmasa, kompilyator
`Unit 'blcksock' not found` xatosi bilan to'xtaydi.

Repozitoriy ichidan:

```powershell
msbuild src\nbDevOpsCockpit.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

Demo loyiha:

```powershell
msbuild demo\nbDevOpsCockpitDemo.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

Delphi designer uchun paketni bog'liqliklar ulanganidan keyin build/install qilish kerak.

## Runtime eslatmalari

Windows'da libssh2/OpenSSL/zlib DLL fayllari exe yonida yoki `PATH` ichida bo'lishi kerak.

Linux/macOS'da mos shared library fayllari tizim loader'iga ko'rinishi kerak.

## Hujjatlar

- [Developer Guide](docs/DEVELOPER_GUIDE.md)
- [SSH Bridge](docs/SSH-BRIDGE.md)

## Litsenziya

Loyihaning original kodi Mozilla Public License 2.0 asosida tarqatiladi.
Ichiga kiritilgan bog'liqliklarning litsenziyalari
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) faylida ko'rsatilgan.
