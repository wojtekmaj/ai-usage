[CmdletBinding()]
param(
    [ValidateSet('ARM64', 'x64')]
    [string]$Architecture = 'ARM64',
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')]
    [string]$Version = '1.1.0',
    [switch]$SkipArchive
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet)) {
    $dotnet = (Get-Command dotnet -ErrorAction Stop).Source
}

$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
$env:Path = "$cargoBin;$([Environment]::GetEnvironmentVariable('Path', 'User'));$([Environment]::GetEnvironmentVariable('Path', 'Machine'))"
$cargo = (Get-Command cargo -ErrorAction Stop).Source
$rustup = (Get-Command rustup -ErrorAction Stop).Source
$runtime = if ($Architecture -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$rustArchitecture = if ($Architecture -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
$installedToolchains = & $rustup toolchain list
$toolchain = ($installedToolchains | Where-Object { $_ -match '^stable-(aarch64|x86_64)-pc-windows-gnullvm' } | Select-Object -First 1) -replace '\s+\(.*$', ''
if ($toolchain) {
    $rustTarget = "$rustArchitecture-pc-windows-gnullvm"
} else {
    $hostArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToUpperInvariant()
    if ($hostArchitecture -ne $Architecture.ToUpperInvariant()) {
        throw 'Cross-packaging requires a stable Windows gnullvm Rust toolchain. See CONTRIBUTING.md.'
    }
    $toolchain = ($installedToolchains | Where-Object { $_ -match '^stable-(aarch64|x86_64)-pc-windows-msvc' } | Select-Object -First 1) -replace '\s+\(.*$', ''
    if (-not $toolchain) {
        throw 'Install a stable Rust toolchain first. See CONTRIBUTING.md.'
    }
    $rustTarget = "$rustArchitecture-pc-windows-msvc"
}
$artifactName = "AI-Usage-$Version-windows-$($Architecture.ToLowerInvariant())"
$artifactsRoot = Join-Path $repoRoot 'artifacts'
$publishDirectory = Join-Path $artifactsRoot $artifactName
$archivePath = Join-Path $artifactsRoot "$artifactName.zip"
$project = Join-Path $repoRoot 'apps\windows\AiUsage.Windows\AiUsage.Windows.csproj'

& $rustup target add $rustTarget --toolchain $toolchain
if ($LASTEXITCODE -ne 0) { throw 'Unable to install the Rust target.' }

& $cargo "+$toolchain" build --manifest-path (Join-Path $repoRoot 'Cargo.toml') --package ai-usage-core --release --target $rustTarget
if ($LASTEXITCODE -ne 0) { throw 'The shared core build failed.' }

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null

& $dotnet publish $project -c Release -r $runtime "-p:Platform=$Architecture" "-p:Version=$Version" --self-contained true -o $publishDirectory
if ($LASTEXITCODE -ne 0) { throw 'The Windows app publish failed.' }

$coreExecutable = Join-Path $repoRoot "target\$rustTarget\release\ai-usage-core.exe"
Copy-Item -LiteralPath $coreExecutable -Destination (Join-Path $publishDirectory 'ai-usage-core.exe')

if (-not $SkipArchive) {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -Path (Join-Path $publishDirectory '*') -DestinationPath $archivePath -CompressionLevel Optimal
    Write-Host "Created $archivePath"
}

Write-Host "Portable app: $publishDirectory"
