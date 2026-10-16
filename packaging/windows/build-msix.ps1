<#
.SYNOPSIS
    Builds the Microsoft Store (MSIX) package for RunCat Lumina.

.DESCRIPTION
    Pipeline:
      1. PyInstaller build of RunCat-Lumina.store.spec (windowed, no UPX)
      2. Stage folder: RunCat-Lumina.exe + AppxManifest.xml + Assets\
      3. makeappx pack  -> RunCatLumina-<version>-x64.msix
      4. Self-signed certificate (matching the manifest Publisher)
         + signtool sign -> package ready for local install / Partner Center upload

    Requires: Python 3.9+ with pyinstaller (pip install pyinstaller -r requirements.txt)
    Requires: Windows SDK (makeappx.exe, signtool.exe) - installed with
              "VS 2022 Build Tools > Windows SDK" or the standalone Windows SDK.

.PARAMETER Publisher
    Manifest Publisher value. MUST match the certificate subject used for signing.
    For a Microsoft Store submission pass the EXACT Publisher string from
    Microsoft Partner Center (Account settings), e.g.:
        -Publisher "CN=12345678-1234-1234-1234-123456789012"
    Default (local test build): CN=AL ASAR JADEED

.PARAMETER Version
    Four-part package version. Defaults to the repo VERSION file (1.0.0 -> 1.0.0.0).

.PARAMETER SdkDir
    Windows SDK root containing bin\<version>\x64\makeappx.exe.
    Auto-detected from the standard install location when omitted.

.PARAMETER NoSign
    Build an unsigned .msix (not accepted by Partner Center; for diagnostics only).

.EXAMPLE
    .\build-msix.ps1
    Local test build signed with CN=AL ASAR JADEED.

.EXAMPLE
    .\build-msix.ps1 -Publisher "CN=12345678-1234-1234-1234-123456789012" -Version 1.0.0.0
    Final Microsoft Store build.
#>
[CmdletBinding()]
param(
    [string]$Publisher = 'CN=AL ASAR JADEED',
    [string]$Version,
    [string]$SdkDir,
    [string]$Arch = 'x64',
    [switch]$NoSign
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Find-Tool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-SdkTool {
    param([string]$Name)
    if ($SdkDir) {
        $hit = Get-ChildItem -Path $SdkDir -Recurse -Filter $Name -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\$Arch\\$([regex]::Escape($Name))$" } |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
        throw "Tool $Name not found under -SdkDir $SdkDir"
    }
    # Windows SDK default: C:\Program Files (x86)\Windows Kits\10\bin\10.0.xxxxx.0\x64\
    $kits = ${env:ProgramFiles(x86)}
    if ($kits) {
        $base = Join-Path $kits 'Windows Kits\10\bin'
        if (Test-Path $base) {
            $hit = Get-ChildItem -Path $base -Directory -Filter '10.*' |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName "x64\$Name" } |
                Where-Object { Test-Path $_ } |
                Select-Object -First 1
            if ($hit) { return $hit }
        }
    }
    $onPath = Find-Tool $Name
    if ($onPath) { return $onPath }
    throw "$Name not found. Install the Windows SDK or pass -SdkDir."
}

# --- Version ---------------------------------------------------------------
if (-not $Version) {
    $Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()
}
# The MSIX manifest requires four parts: 1.2.3 -> 1.2.3.0
if ($Version -match '^\d+\.\d+\.\d+$') { $Version = '{0}.0' -f $Version }
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Version '$Version' is not a four-part version (x.y.z.w)."
}

Write-Host "== RunCat Lumina MSIX build ==" -ForegroundColor Cyan
Write-Host "Root      : $Root"
Write-Host "Version   : $Version"
Write-Host "Publisher : $Publisher"
Write-Host "Arch      : $Arch"

# --- Python / PyInstaller --------------------------------------------------
$python = Find-Tool 'python'
if (-not $python) { $python = Find-Tool 'py' }
if (-not $python) { throw 'Python not found on PATH (need python or py launcher).' }

$pyinstaller = Find-Tool 'pyinstaller'
if (-not $pyinstaller) {
    # fall back to python -m PyInstaller
    $pyinstaller = $null
}
if (-not $pyinstaller) {
    Write-Host 'Installing pyinstaller...' -ForegroundColor DarkGray
    & $python -m pip install --quiet pyinstaller
    if ($LASTEXITCODE -ne 0) { throw 'pip install pyinstaller failed.' }
}

Write-Host 'Step 1/4: PyInstaller (store spec)...' -ForegroundColor Cyan
$distStore = Join-Path $Root 'dist\store'
$buildStore = Join-Path $Root 'build\store'
if (Test-Path $distStore) { Remove-Item $distStore -Recurse -Force }
if (Test-Path $buildStore) { Remove-Item $buildStore -Recurse -Force }
$specPath = Join-Path $Root 'RunCat-Lumina.store.spec'
if ($pyinstaller) {
    & $pyinstaller --noconfirm --distpath $distStore --workpath $buildStore $specPath
} else {
    & $python -m PyInstaller --noconfirm --distpath $distStore --workpath $buildStore $specPath
}
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller build failed.' }
$exePath = Join-Path $distStore 'RunCat-Lumina.exe'
if (-not (Test-Path $exePath)) { throw "Expected executable not found: $exePath" }

# --- Stage -----------------------------------------------------------------
Write-Host 'Step 2/4: Staging package layout...' -ForegroundColor Cyan
$stage = Join-Path $Root 'build\msix-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Copy-Item $exePath (Join-Path $stage 'RunCat-Lumina.exe')
Copy-Item (Join-Path $Root 'packaging\windows\msix\Assets') (Join-Path $stage 'Assets') -Recurse

$manifest = Get-Content (Join-Path $Root 'packaging\windows\msix\AppxManifest.xml') -Raw
$manifest = $manifest.Replace('{{PUBLISHER}}', $Publisher).Replace('{{VERSION}}', $Version)
Set-Content -Path (Join-Path $stage 'AppxManifest.xml') -Value $manifest -Encoding utf8

# --- Pack ------------------------------------------------------------------
Write-Host 'Step 3/4: makeappx pack...' -ForegroundColor Cyan
$makeappx = Find-SdkTool 'makeappx.exe'
$outDir = Join-Path $Root 'dist\msix'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$msixPath = Join-Path $outDir "RunCatLumina-$Version-$Arch.msix"
if (Test-Path $msixPath) { Remove-Item $msixPath -Force }

$packArgs = @('pack', '/d', $stage, '/p', $msixPath, '/o')
& $makeappx @packArgs
if ($LASTEXITCODE -ne 0) { throw 'makeappx pack failed.' }

# --- Certificate + sign ----------------------------------------------------
if (-not $NoSign) {
    Write-Host 'Step 4/4: Signing...' -ForegroundColor Cyan
    $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object {
            $_.Subject -eq $Publisher -and
            $_.HasPrivateKey -and
            $_.NotAfter -gt (Get-Date).AddDays(30) -and
            $_.Issuer -eq $_.Subject
        } |
        Sort-Object NotAfter -Descending | Select-Object -First 1

    if (-not $cert) {
        Write-Host "Creating self-signed test certificate for $Publisher ..." -ForegroundColor DarkGray
        $cert = New-SelfSignedCertificate `
            -Type Custom `
            -Subject $Publisher `
            -KeyUsage DigitalSignature `
            -KeyLength 2048 `
            -KeyAlgorithm RSA `
            -HashAlgorithm SHA256 `
            -CertStoreLocation Cert:\CurrentUser\My `
            -FriendlyName 'RunCat Lumina MSIX test certificate' `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
            -NotAfter (Get-Date).AddYears(2)
    }

    $cerPath = [System.IO.Path]::ChangeExtension($msixPath, '.cer')
    Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null

    $signtool = Find-SdkTool 'signtool.exe'
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /td SHA256 $msixPath
    if ($LASTEXITCODE -ne 0) { throw 'signtool sign failed.' }
    & $signtool verify /pa $msixPath
    if ($LASTEXITCODE -ne 0) {
        # Non-fatal: some Windows SDK versions verify MSIX with different flags.
        Write-Host 'Warning: signtool verify reported an issue (package is signed; re-check locally).' -ForegroundColor Yellow
    }
} else {
    $cerPath = $null
    Write-Host 'Step 4/4: Skipped signing (-NoSign).' -ForegroundColor Yellow
}

# Package validation happens inside makeappx pack (schema errors fail step 3).

Write-Host ''
Write-Host "OK  $msixPath" -ForegroundColor Green
if ($cerPath) { Write-Host "Test certificate: $cerPath" -ForegroundColor Green }
Write-Host ''
Write-Host 'Local install test:' -ForegroundColor Cyan
Write-Host '  1. Import the .cer into Cert:\LocalMachine\TrustedPeople (or trust it when prompted)'
Write-Host '  2. Enable Settings > Privacy & security > For developers > Developer Mode'
Write-Host "  3. Add-AppxPackage -Path `"$msixPath`""
Write-Host 'Partner Center upload: pass -Publisher with your exact Partner Center Publisher string.'

# Success. Reset the exit code left behind by the non-fatal `signtool verify`
# (self-signed chain) so wrapper shells that end with `exit $LASTEXITCODE`
# (GitHub Actions pwsh) see 0 instead of 1.
$global:LASTEXITCODE = 0
