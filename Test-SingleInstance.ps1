#Requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SingleInstance.cs'))) -ReferencedAssemblies 'System.Windows.Forms','System.Core'
function Assert($value,$message){if(-not $value){throw $message}}
$primary=Start-Process -FilePath (Join-Path $PSScriptRoot 'MonitorSwitch-Neon.exe') -WindowStyle Hidden -PassThru
try{
 $state=$null
 for($i=0;$i -lt 100;$i++){
  try{$state=[AppInstance]::Snapshot();if([long]$state[1] -ne 0 -and $state[3] -eq '1'){break}}catch{}
  Start-Sleep -Milliseconds 150
 }
 Assert ($null -ne $state -and $state[3] -eq '1') 'Initial instance must create exactly one tray icon'
 $owner=$state[0]
 [AppInstance]::HideForTest()
 $duplicate=Start-Process -FilePath (Join-Path $PSScriptRoot 'MonitorSwitch-Neon.exe') -WindowStyle Hidden -PassThru
 Assert ($duplicate.WaitForExit(10000) -and $duplicate.ExitCode -eq 0) 'Duplicate EXE must exit normally without an extra icon'
 for($i=0;$i -lt 30;$i++){ $state=[AppInstance]::Snapshot();if($state[4] -eq 'True' -and [int]$state[2] -ge 1){break};Start-Sleep -Milliseconds 100 }
 Assert ($state[0] -eq $owner -and $state[3] -eq '1') 'Duplicate EXE must reuse the same UI owner and tray'
 Assert ($state[4] -eq 'True' -and $state[6] -eq 'True') 'Hidden UI must be restored and placed on top'
 $activation=[int]$state[2]
 [AppInstance]::MinimizeForTest()
 $again=Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'MonitorSwitch.ps1')+'"') -WindowStyle Hidden -PassThru
 Assert ($again.WaitForExit(10000) -and $again.ExitCode -eq 0) 'Direct script duplicate must also exit'
 for($i=0;$i -lt 30;$i++){ $state=[AppInstance]::Snapshot();if($state[5] -eq 'False' -and [int]$state[2] -gt $activation){break};Start-Sleep -Milliseconds 100 }
 Assert ($state[0] -eq $owner -and $state[3] -eq '1') 'Direct script must reuse the same UI and tray'
 Assert ($state[4] -eq 'True' -and $state[5] -eq 'False' -and $state[6] -eq 'True') 'Minimized UI must be restored and topmost'
 Write-Host 'PASS: 7 singleton/tray/window activation checks.'
}finally{
 try{[AppInstance]::RequestExit()}catch{}
 if(-not $primary.WaitForExit(10000)){throw 'Primary instance failed to shut down cleanly'}
}
