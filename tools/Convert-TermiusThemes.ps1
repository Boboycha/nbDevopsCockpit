param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText($InputFile, [Text.Encoding]::UTF8)

$pattern = '(?s)\{name:"(?<name>(?:\\.|[^"\\])*)",colorPaletteOverrides:\[(?<palette>.*?)\],backgroundColor:"(?<background>#[0-9A-Fa-f]{6,8})",cursorColor:"(?<cursor>#[0-9A-Fa-f]{6,8})",foregroundColor:"(?<foreground>#[0-9A-Fa-f]{6,8})",selectionColor:"(?<selection>#[0-9A-Fa-f]{6,8})",app:\{terminalUIColor:"(?<ui>#[0-9A-Fa-f]{6,8})"\}\}'
$matches = [regex]::Matches($source, $pattern)
if ($matches.Count -eq 0) {
    throw 'No Termius themes found in input file.'
}

[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

function Escape-YamlSingleQuoted([string]$Value) {
    return $Value.Replace("'", "''")
}

function Safe-FileName([string]$Name) {
    $result = $Name
    foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) {
        $result = $result.Replace([string]$ch, '_')
    }
    return $result.Trim()
}

$written = 0
foreach ($match in $matches) {
    $name = [regex]::Unescape($match.Groups['name'].Value)
    # The supplied Termius export contains Rosé Pine names double-decoded
    # through a Cyrillic code page. Repair that known mojibake on import.
    $brokenRose = 'Ros' + [char]0x0413 + [char]0x00A9
    $correctRose = 'Ros' + [char]0x00E9
    $name = $name.Replace($brokenRose, $correctRose)
    $colors = [regex]::Matches($match.Groups['palette'].Value, '"(?<color>#[0-9A-Fa-f]{6,8})"') |
        ForEach-Object { $_.Groups['color'].Value.ToUpperInvariant() }

    if ($colors.Count -ne 16) {
        throw "Theme '$name' has $($colors.Count) palette colors instead of 16."
    }

    $background = $match.Groups['background'].Value.ToUpperInvariant()
    $foreground = $match.Groups['foreground'].Value.ToUpperInvariant()
    $cursor = $match.Groups['cursor'].Value.ToUpperInvariant()
    $selection = $match.Groups['selection'].Value.ToUpperInvariant()
    $terminalUi = $match.Groups['ui'].Value.ToUpperInvariant()

    $rgb = $background.Substring(1, 6)
    $r = [Convert]::ToInt32($rgb.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($rgb.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($rgb.Substring(4, 2), 16)
    $variant = if ((0.2126 * $r + 0.7152 * $g + 0.0722 * $b) -lt 128) { 'dark' } else { 'light' }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("name: '$(Escape-YamlSingleQuoted $name)'")
    $lines.Add("author: 'Termius'")
    $lines.Add("variant: '$variant'")
    $lines.Add('')
    for ($i = 0; $i -lt 16; $i++) {
        $lines.Add(('color_{0:D2}: ''{1}''' -f ($i + 1), $colors[$i]))
    }
    $lines.Add('')
    $lines.Add("background: '$background'")
    $lines.Add("foreground: '$foreground'")
    $lines.Add("cursor: '$cursor'")
    $lines.Add("selection: '$selection'")
    $lines.Add("terminal_ui: '$terminalUi'")

    $fileName = (Safe-FileName $name) + '.yml'
    [IO.File]::WriteAllLines((Join-Path $OutputDirectory $fileName), $lines, [Text.UTF8Encoding]::new($false))
    $written++
}

Write-Output "Converted $written Termius themes to $OutputDirectory"
