#Requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Collections.Generic;
public class DdcCi {
 public class Monitor { public IntPtr hPhysicalMonitor; }
 public static int Closed=0, Selected=-1; public static uint Written=0;
 public static bool Fail=false;
 public static List<Monitor> Open(){ return new List<Monitor>{new Monitor{hPhysicalMonitor=(IntPtr)1},new Monitor{hPhysicalMonitor=(IntPtr)2}}; }
 public static bool GetInput(IntPtr h,out uint value){ Selected=h.ToInt32();value=15;return !Fail; }
 public static bool SetInput(IntPtr h,uint value){Selected=h.ToInt32();Written=value;if(Fail)throw new Exception("mock write failure");return true;}
 public static void Close(IntPtr h){Closed++;}
}
'@
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'MonitorSwitch.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in 'Read-CurrentPort','Write-PortSwitch') {
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $node.Extent.Text
}
function Write-Log([string]$Message){}
function Assert($condition,$message){if(-not $condition){throw $message}}
$script:MonitorIndex=1
Assert ((Read-CurrentPort) -eq 15) 'Read should retain DP=15'
Assert ([DdcCi]::Selected -eq 2 -and [DdcCi]::Closed -eq 2) 'Selected monitor and cleanup'
Assert (Write-PortSwitch 17) 'HDMI write'
Assert ([DdcCi]::Written -eq 17 -and [DdcCi]::Selected -eq 2 -and [DdcCi]::Closed -eq 4) 'Mapping preserved and handles closed'
[DdcCi]::Fail=$true
Assert (-not (Write-PortSwitch 15)) 'Write exception must report failure'
Assert ([DdcCi]::Closed -eq 6) 'Exception cleanup'
Assert ((Read-CurrentPort) -eq -1) 'Read failure must be unknown'
Assert ([DdcCi]::Closed -eq 8) 'Read failure cleanup'
$script:MonitorIndex=9
Assert ((Read-CurrentPort) -eq -1) 'Missing selected monitor'
Assert (-not (Write-PortSwitch 17)) 'Missing monitor must not switch another monitor'
Assert ([DdcCi]::Closed -eq 12) 'Missing monitor cleanup'
Write-Host 'PASS: input mappings, selected monitor, failure paths and handle cleanup (11 checks).'
