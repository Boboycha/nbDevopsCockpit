param(
  [string]$Configuration = "Release",
  [string]$Platform = "Win64",
  [string]$Tag = "",
  [switch]$Publish
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProjectFile = Join-Path $RepoRoot "demo\nbDevOpsCockpitDemo.dproj"
$OutputDir = Join-Path $RepoRoot "bin\demo\$Platform\$Configuration"
$DistDir = Join-Path $RepoRoot "dist"
$PackageRoot = Join-Path $RepoRoot "dist\nbDevOpsCockpitDemo-$Platform-portable"
$ZipPath = "$PackageRoot.zip"

if ($Tag -eq "") {
  $Tag = "demo-latest"
}

[string[]]$RsVarsCandidates = @(
  "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat",
  "C:\Program Files\Embarcadero\Studio\23.0\bin\rsvars.bat"
) | Where-Object { Test-Path $_ }

if ($RsVarsCandidates.Count -eq 0) {
  throw "RAD Studio rsvars.bat was not found."
}

$RsVars = $RsVarsCandidates[0]

Push-Location $RepoRoot
try {
  New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
  $BuildScript = Join-Path $DistDir "build-demo-$Platform-$Configuration.cmd"
  @(
    "@echo off",
    "call `"$RsVars`"",
    "msbuild `"$ProjectFile`" /t:Build /p:Config=$Configuration /p:Platform=$Platform",
    "exit /b %ERRORLEVEL%"
  ) | Set-Content -Path $BuildScript -Encoding ASCII

  cmd.exe /c $BuildScript
  if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
  }

  if (Test-Path $PackageRoot) {
    Remove-Item -LiteralPath $PackageRoot -Recurse -Force
  }
  if (Test-Path $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }

  New-Item -ItemType Directory -Path $PackageRoot | Out-Null
  Copy-Item -LiteralPath (Join-Path $OutputDir "nbDevOpsCockpitDemo.exe") -Destination $PackageRoot
  Copy-Item -LiteralPath (Join-Path $RepoRoot "vendor\win64\libssh2.dll") -Destination $PackageRoot
  Copy-Item -LiteralPath (Join-Path $RepoRoot "vendor\win64\sk4d.dll") -Destination $PackageRoot
  Copy-Item -LiteralPath (Join-Path $RepoRoot "demo\themes") -Destination (Join-Path $PackageRoot "themes") -Recurse

  Compress-Archive -Path (Join-Path $PackageRoot "*") -DestinationPath $ZipPath -Force
  Write-Host "Portable package: $ZipPath"

  if ($Publish) {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    gh release view $Tag --repo Boboycha/nbDevopsCockpit *> $null
    $ReleaseExists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $PreviousErrorActionPreference

    if ($ReleaseExists) {
      gh release upload $Tag $ZipPath --repo Boboycha/nbDevopsCockpit --clobber
    }
    else {
      gh release create $Tag $ZipPath --repo Boboycha/nbDevopsCockpit --title "Latest portable demo" --notes "Portable Win64 demo build."
    }
  }
}
finally {
  Pop-Location
}
