# nbDevOpsCockpit

`nbDevOpsCockpit` - Delphi FMX uchun DevOps komponentlar paketi. Unda SSH, terminal, SFTP va fayl panel komponentlari bor. Paket `nTizgin` ichida ishlatiladi.

Tillar: [Русский](README.md) | [English](README.en.md) | [O'zbekcha](README.uz.md)

## Ichida nimalar bor

- `TnbSSHClient` - libssh2 asosidagi SSH komponent.
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
- libssh2 runtime kutubxonasi
- libssh2 yig'ilishiga qarab OpenSSL/zlib runtime kutubxonalari
- `Z:\VCL\synapse` ichidagi Ararat Synapse

## Yig'ish

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
