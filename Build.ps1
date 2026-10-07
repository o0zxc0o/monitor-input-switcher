#Requires -Version 5.1
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /out:"$PSScriptRoot\MonitorSwitch-Neon.exe" /win32icon:"$PSScriptRoot\monitor-switch.ico" "$PSScriptRoot\Launcher.cs"
if($LASTEXITCODE -ne 0){throw 'Build failed'}
Write-Host 'Build succeeded: MonitorSwitch-Neon.exe'