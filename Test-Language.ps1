#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Localization.ps1')
$script:Language='en'
if((T '正在切换到HDMI-1 · 显示器会黑屏 2–3 秒') -ne 'Switching to HDMI-1; display may go black for 2–3 seconds'){throw 'Dynamic message translation failed'}
if((T '确认已连接') -ne 'Confirm connected'){throw 'Longer phrase translation failed'}
$english=T '设置已保存 · 缩放重启生效'
$script:Language='zh'
if((Convert-UiText $english) -ne '设置已保存 · 缩放重启生效'){throw 'Language round trip failed'}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot 'NeonSkin.cs') -Raw) -ReferencedAssemblies System.Drawing,System.Windows.Forms
$form=New-Object ArmorForm
$label=New-Object Windows.Forms.Label;$label.Text='已读取当前输入源';$form.Controls.Add($label)
$button=New-Object ArmorButton;$button.BigText='↻ 刷新';$form.Controls.Add($button)
$script:Language='en';Apply-Language
if($label.Text -ne 'Current input read' -or $button.BigText -ne '↻ Refresh' -or -not [NeonSkin]::English){throw 'Live language change failed'}
$script:Language='zh';Apply-Language
if($label.Text -ne '已读取当前输入源' -or $button.BigText -ne '↻ 刷新' -or [NeonSkin]::English){throw 'Live return to Chinese failed'}
$form.Dispose()
'PASS: dynamic translations, phrase ordering, live switching and Chinese round trip'
