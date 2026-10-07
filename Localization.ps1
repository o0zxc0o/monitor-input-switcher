$script:Language='zh'
$script:Translations=@{
'显示器输入源切换'='Monitor Input Switcher';'当前输入源'='CURRENT INPUT';'输入源设置'='Input Settings';'设置'='Settings';'日志'='Logs';'退出'='Exit';'刷新'='Refresh';'读取中'='Reading';'读不到'='Unavailable';'已连接'='Connected';'未连接'='Disconnected';'未确认'='Unknown';'台式机'='Desktop';'笔记本'='Laptop';'显示 / 隐藏'='Show / Hide';'切换到'='Switch to ';'已经在'='Already using ';'正在切换到'='Switching to ';'已切换到'='Switched to ';'正在输出'='Active';'已读取当前输入源'='Current input read';'已刷新'='Refreshed';'保存'='Save';'保存失败'='Save failed';'显示器上的其他输入源'='Other monitor input';'显示器（DDC/CI 枚举顺序）'='Monitor (DDC/CI enumeration order)';'VCP 0x60 输入值（保留现有配置映射）'='VCP 0x60 input values (existing mapping)';'界面缩放（重启生效）'='Scale (restart required)';'其他电脑的接口无法直接查询，可在下方确认连接'='Confirm remote PC connections below.';'自动检测'='Auto detect';'确认已连接'='Confirm connected';'确认未连接'='Confirm disconnected';'本机 HDMI 接在哪一口'='Local HDMI input';'自动 / 未确认'='Auto / Unknown';'两个输入源不能使用相同值。'='The two inputs must use different values.';'设置已保存 · 缩放重启生效'='Settings saved; restart to apply scale';'读取失败 · 请检查显示器选择与 DDC/CI'='Read failed; check monitor and DDC/CI';'读取失败 · 请检查 DDC/CI 或打开设置'='Read failed; check DDC/CI or Settings';'快捷键注册失败 · 已被占用，请使用输入卡片'='Hotkeys unavailable; use the input cards';' · 显示器会黑屏 2–3 秒'='; display may go black for 2–3 seconds';'切换指令没有发出去 · 检查 DDC/CI 是否开启'='Switch command failed; enable DDC/CI';'切换失败 · 显示器仍在其他输入源'='Switch failed; monitor is on another input';'切换指令已发送 · 未读到确认'='Command sent; confirmation unavailable';'语言 / Language'='Language / 语言'
}
function T([string]$Text){
 if($script:Language -ne 'en'){return $Text}
 foreach($key in ($script:Translations.Keys | Sort-Object Length -Descending)){$Text=$Text.Replace($key,$script:Translations[$key])}
 return $Text
}
function Convert-UiText([string]$Text){
 if($script:Language -eq 'en'){return (T $Text)}
 foreach($key in ($script:Translations.Keys | Sort-Object { $script:Translations[$_].Length } -Descending)){$Text=$Text.Replace($script:Translations[$key],$key)}
 return $Text
}
function Apply-Language {
 [NeonSkin]::English=($script:Language -eq 'en')
 foreach($control in $form.Controls){
  if($control -is [Windows.Forms.Label]){$control.Text=Convert-UiText $control.Text}
  if($control -is [ArmorButton]){$control.BigText=Convert-UiText $control.BigText}
  $control.Invalidate()
 }
 $form.Text=Convert-UiText $form.Text
 if($tray){$tray.Text=Convert-UiText $tray.Text;foreach($item in $tray.ContextMenuStrip.Items){$item.Text=Convert-UiText $item.Text}}
 $form.Invalidate()
}
