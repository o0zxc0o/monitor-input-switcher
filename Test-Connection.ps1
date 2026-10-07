#Requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$skin=Get-Content (Join-Path $PSScriptRoot 'NeonSkin.cs') -Raw
if($skin -notmatch 'class ConnectionEvidence'){throw 'Missing ConnectionEvidence: connection and active input are still coupled'}
Add-Type -TypeDefinition $skin -ReferencedAssemblies 'System.Drawing','System.Windows.Forms'
$override=New-Object 'System.Collections.Generic.Dictionary[int,int]'
$override[17]=1;$override[18]=0
function Assert($v,$message){if(-not $v){throw $message}}
Assert ([ConnectionEvidence]::Resolve(15,15,@(15),$override) -eq 1) 'Windows-confirmed current input is connected'
Assert ([ConnectionEvidence]::Resolve(15,15,@(),$override) -eq -1) 'VCP current selection alone does not prove a cable connection'
Assert ([ConnectionEvidence]::Resolve(17,15,@(),$override) -eq 1) 'Confirmed second input remains colored without being active'
Assert ([ConnectionEvidence]::Resolve(18,15,@(),$override) -eq 0) 'Explicit disconnected input'
Assert ([ConnectionEvidence]::Resolve(19,15,@(),$override) -eq -1) 'Unsupported detection must stay unknown'
Assert ([ConnectionEvidence]::Resolve(18,18,@(18),$override) -eq 1) 'Live connection evidence supersedes manual disconnected status'
Assert ([ConnectionEvidence]::Resolve(18,15,@(18),$override) -eq 1) 'Detected connection supersedes manual status'
Assert ([ConnectionEvidence]::Resolve(15,-1,@(),$override) -eq -1) 'Do not retain a stale current source'
$card=New-Object ArmorButton;$card.CardIndex=1;$card.ConnectionState=1;$card.Active=$false
Assert ($card.ConnectionState -eq 1 -and -not $card.Active) 'Portrait color and border selection must be independent'
$card.Dispose()
Write-Host 'PASS: 9 connection/selection checks.'
