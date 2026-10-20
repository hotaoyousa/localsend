# Run from a Windows machine with Flutter 3.41.9, Rust 1.97.1,
# Visual Studio's Desktop development with C++ workload and the Windows SDK.
# Generates a local portable ZIP without uploading source or artifacts.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $RepoRoot
try {
    function Invoke-Flutter {
        if (Get-Command fvm -ErrorAction SilentlyContinue) { & fvm flutter @args }
        else { & flutter @args }
        if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: $args" }
    }
    $MakePri = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\10.*\x64\makepri.exe' |
        Sort-Object FullName | Select-Object -Last 1
    if (-not $MakePri) { throw 'Windows SDK makepri.exe is required.' }
    & $MakePri.FullName new /pr support\build\msix\content /cf support\build\msix\priconfig.xml /mn support\build\msix\content\AppxManifest.xml /of support\build\msix\content\resources.pri /o
    if ($LASTEXITCODE -ne 0) { throw 'MSIX resource generation failed.' }
    & 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\makeappx.exe' pack /o /d support\build\msix\content /nv /p app\windows\localsend_msix_helper.msix
    if ($LASTEXITCODE -ne 0) { throw 'MSIX helper build failed.' }
    Push-Location app
    try { Invoke-Flutter pub get; Invoke-Flutter build windows --release }
    finally { Pop-Location }
    $Release = Join-Path $RepoRoot 'app\build\windows\x64\runner\Release'
    Copy-Item support\build\windows\x64\*.dll $Release
    foreach ($Name in @('localsend_msix_helper.msix', 'install_msix_helper.ps1', 'localsend_app.exe.manifest')) {
        $Item = Join-Path $Release $Name
        if (Test-Path $Item) { Remove-Item $Item }
    }
    Set-Content -Path (Join-Path $Release 'settings.json') -Value '{}' -Encoding ASCII
    $Output = Join-Path $RepoRoot 'dist\qr-connection-20261020'
    New-Item -ItemType Directory -Force -Path $Output | Out-Null
    $Zip = Join-Path $Output 'LocalSend-1.18.2-qr-connection-windows-x64.zip'
    Compress-Archive -Path "$Release\*" -DestinationPath $Zip -Force
    Write-Host "Created: $Zip"
} finally { Pop-Location }
