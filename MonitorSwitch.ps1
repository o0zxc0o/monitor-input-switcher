#Requires -Version 5.1
<#
    MonitorSwitch.ps1

    EVA-02 skinned desktop app for switching the input source of an
    ASUS ROG Strix XG27AQ over DDC/CI.

    - Borderless window with a self-drawn caption: minimise / close are
      painted into the dark skin, so it reads as a tool, not a window.
    - No installer, no third-party runtime: Windows' own user32.dll +
      dxva2.dll, WinForms and GDI+ only.
    - Global hotkeys Ctrl+Alt+1 (desktop) / Ctrl+Alt+2 (laptop) while running.

    Verified port values on the XG27AQ:
        DisplayPort = 0x0F     HDMI-1 = 0x11     HDMI-2 = 0x12

    The same folder runs unmodified on both machines - which machine this is
    comes from Win32_ComputerSystem.PCSystemType.

    Run with -SelfTest -ShotPath <png> to render the window, grab a
    screenshot and exit (used for verification).
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$ShotPath,
    [int]$PreviewPort = -1,
    [int[]]$PreviewConnectedPorts,
    [switch]$SelfTestSaveSettings,
    [ValidateSet('zh','en')][string]$SelfTestLanguage
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Localization.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SingleInstance.cs'))) -ReferencedAssemblies 'System.Windows.Forms','System.Core'
$script:AppGate=$null
if(-not $SelfTest){
    $script:AppGate=New-Object AppInstance
    if(-not $script:AppGate.IsOwner){[AppInstance]::SignalExisting();$script:AppGate.Dispose();return}
}
# ---------------------------------------------------------------- interop
$interop = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class DdcCi
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr lprc, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr data);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint number);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count,
        [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] PHYSICAL_MONITOR[] arr);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr type,
        out uint current, out uint maximum);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetVCPFeature(IntPtr h, byte code, uint value);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitor(IntPtr h);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct MONITORINFOEX { public int cbSize; public int l,t,r,b,wl,wt,wr,wb; public uint flags; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string device; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr h,ref MONITORINFOEX info);
    public static List<string> DeviceNames=new List<string>();
    public static List<PHYSICAL_MONITOR> Open()
    {
        List<PHYSICAL_MONITOR> list = new List<PHYSICAL_MONITOR>(); DeviceNames.Clear();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
            delegate(IntPtr hMon, IntPtr hdc, IntPtr lprc, IntPtr data)
            {
                uint n;
                if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, out n) && n > 0)
                {
                    PHYSICAL_MONITOR[] arr = new PHYSICAL_MONITOR[n];
                    if (GetPhysicalMonitorsFromHMONITOR(hMon, n, arr)) {
                        list.AddRange(arr); MONITORINFOEX info=new MONITORINFOEX();info.cbSize=Marshal.SizeOf(typeof(MONITORINFOEX));GetMonitorInfo(hMon,ref info);
                        for(int i=0;i<n;i++)DeviceNames.Add(info.device);
                    }
                }
                return true;
            }, IntPtr.Zero);
        return list;
    }

    public static bool GetInput(IntPtr h, out uint current)
    {
        uint max;
        return GetVCPFeatureAndVCPFeatureReply(h, 0x60, IntPtr.Zero, out current, out max);
    }

    public static bool SetInput(IntPtr h, uint value) { return SetVCPFeature(h, 0x60, value); }
    public static void Close(IntPtr h) { DestroyPhysicalMonitor(h); }
}

public class HotkeySink : NativeWindow, IDisposable
{
    public const int WM_HOTKEY = 0x0312;

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler<int> Pressed;

    private readonly List<int> ids = new List<int>();

    public HotkeySink() { CreateHandle(new CreateParams()); }

    public bool Register(uint modifiers, uint key, int id)
    {
        bool ok = RegisterHotKey(this.Handle, id, modifiers, key);
        if (ok) ids.Add(id);
        return ok;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && Pressed != null) Pressed(this, m.WParam.ToInt32());
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        foreach (int id in ids) UnregisterHotKey(this.Handle, id);
        DestroyHandle();
    }
}
'@

Add-Type -TypeDefinition $interop -Language CSharp -ReferencedAssemblies 'System.Windows.Forms'

# ---------------------------------------------------------------- skin controls
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'NeonSkin.cs'))) -Language CSharp -ReferencedAssemblies 'System.Windows.Forms','System.Drawing'
[NeonSkin]::Art = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'assets\eva-neon-reference.png'))
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DisplayConnections.cs')))
# ---------------------------------------------------------------- config
$script:MonitorIndex = 0
$script:HostHdmiInput=-1
$script:ConnectionOverrides=New-Object "System.Collections.Generic.Dictionary[int,int]"
$script:UiScale = 1.0
$script:PortA = 0x0F
$script:PortB = 0x11
$script:PortC = 0x12
$script:PortD = $null
$script:PortAWho    = (T '台式机')
$script:PortBWho    = (T '笔记本')
$script:PortALabel  = 'DisplayPort'
$script:PortBLabel  = 'HDMI-1'

$configPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $configPath) {
    try {
        $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json; if($cfg.language -eq 'en'){$script:Language='en'}; [NeonSkin]::English=($script:Language -eq 'en')
        if ($null -ne $cfg.monitorIndex) { $script:MonitorIndex = [Math]::Max(0,[int]$cfg.monitorIndex) }
        if ($cfg.uiScale -ge 1 -and $cfg.uiScale -le 1.5) { $script:UiScale = [double]$cfg.uiScale }
        if($cfg.hostHdmiInput -eq 17 -or $cfg.hostHdmiInput -eq 18){$script:HostHdmiInput=[int]$cfg.hostHdmiInput}
        if($cfg.connectionOverrides){foreach($entry in $cfg.connectionOverrides.PSObject.Properties){if($entry.Value -eq 0 -or $entry.Value -eq 1){$script:ConnectionOverrides[[int]$entry.Name]=[int]$entry.Value}}}
        # This display has only DP and two HDMI inputs.
        foreach ($side in 'portA', 'portB') {
            $c = $cfg.$side
            if ($c) {
                if ($null -ne $c.value -and '' -ne $c.value) {
                    if ($side -eq 'portA') { $script:PortA = [int]$c.value }
                    else                   { $script:PortB = [int]$c.value }
                }
                if ($c.label) {
                    if ($side -eq 'portA') { $script:PortALabel = [string]$c.label }
                    else                   { $script:PortBLabel = [string]$c.label }
                }
                if ($c.who) {
                    if ($side -eq 'portA') { $script:PortAWho = [string]$c.who }
                    else                   { $script:PortBWho = [string]$c.who }
                }
            }
        }
    }
    catch { }
}

$script:Names = @{
    0x0F = @{ Port = 'DisplayPort'; Who = (T '台式机') }
    0x11 = @{ Port = 'HDMI-1';      Who = (T '笔记本') }
    0x12 = @{ Port = 'HDMI-2';      Who = 'HDMI-2' }
}
$script:Names[$script:PortA] = @{ Port = $script:PortALabel; Who = $script:PortAWho }
$script:Names[$script:PortB] = @{ Port = $script:PortBLabel; Who = $script:PortBWho }

$script:ThisRole = (T '台式机')
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.PCSystemType -eq 2) { $script:ThisRole = (T '笔记本') }
}
catch {
    $script:ThisRole = ''
}

# ---------------------------------------------------------------- colours
$cText   = [System.Drawing.Color]::FromArgb(255, 63, 43)
$cSub    = [System.Drawing.Color]::FromArgb(158, 162, 172)
$cHint   = [System.Drawing.Color]::FromArgb(138, 142, 152)
$cOk     = [System.Drawing.Color]::FromArgb(166, 226, 46)
$cWarn   = [System.Drawing.Color]::FromArgb(255, 122, 0)
$cErr    = [System.Drawing.Color]::FromArgb(232, 32, 60)
$cIdle   = [System.Drawing.Color]::FromArgb(90, 94, 102)
$cCapBg  = [System.Drawing.Color]::FromArgb(90, 31, 31)

$fSmall = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$fTiny  = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)
$fTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$fCap   = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)
$fHuge  = New-Object System.Drawing.Font('Microsoft YaHei UI', 20, [System.Drawing.FontStyle]::Bold)
$fPort  = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$fBtn   = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
$fBtnS  = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)

# ---------------------------------------------------------------- helpers
function Load-ImageNoLock {
    param([string]$Path, [int]$Size = 0)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = New-Object System.IO.MemoryStream(, $bytes)
    $src = [System.Drawing.Image]::FromStream($ms)
    $w = if ($Size -gt 0) { $Size } else { $src.Width }
    $h = if ($Size -gt 0) { $Size } else { $src.Height }
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)))
    $g.Dispose(); $src.Dispose(); $ms.Dispose()
    return $bmp
}

# newest skin wins (a running instance keeps a lock on the previous file)
$skinFile = Get-ChildItem -Path (Join-Path $PSScriptRoot 'assets') -Filter 'ui-bg*.png' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

# ---------------------------------------------------------------- ddc helpers
$script:LogPath = Join-Path $PSScriptRoot 'MonitorSwitch.log'
function Write-Log([string]$Message) {
    try { Add-Content -LiteralPath $script:LogPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message) -Encoding UTF8 } catch { }
}
function Read-CurrentPort {
    if($SelfTest -and $PreviewPort -ge 0){return $PreviewPort}
    $mons = @()
    try {
        $mons = @([DdcCi]::Open())
        if ($mons.Count -le $script:MonitorIndex) { return -1 }
        $cur = [uint32]0
        if ([DdcCi]::GetInput($mons[$script:MonitorIndex].hPhysicalMonitor, [ref]$cur)) { return [int]$cur }
        return -1
    } catch { Write-Log $_.Exception.Message; return -1 }
    finally { foreach ($m in $mons) { [DdcCi]::Close($m.hPhysicalMonitor) } }
}
function Write-PortSwitch([int]$Value) {
    $mons = @()
    try {
        $mons = @([DdcCi]::Open())
        if ($mons.Count -le $script:MonitorIndex) { return $false }
        $ok = [DdcCi]::SetInput($mons[$script:MonitorIndex].hPhysicalMonitor, [uint32]$Value)
        Write-Log ('VCP 0x60 monitor={0} target=0x{1:X2} accepted={2}' -f $script:MonitorIndex,$Value,$ok)
        return $ok
    } catch { Write-Log $_.Exception.Message; return $false }
    finally { foreach ($m in $mons) { [DdcCi]::Close($m.hPhysicalMonitor) } }
}
# ---------------------------------------------------------------- form
$form=New-Object ArmorForm
$form.ClientSize=New-Object Drawing.Size([int](840*$script:UiScale),[int](675*$script:UiScale))
$form.StartPosition='CenterScreen'; $form.BackColor=[Drawing.Color]::FromArgb(5,6,8)
$form.Text=(T 'EVA-02 · 显示器输入源切换'); $form.Font=$fSmall
$form.Icon=New-Object Drawing.Icon((Join-Path $PSScriptRoot 'monitor-switch.ico'))
function New-Label {
    param([int]$X,[int]$Y,[int]$W,[int]$H,[string]$Text,$Font,[Drawing.Color]$Color,[Drawing.ContentAlignment]$Align=[Drawing.ContentAlignment]::MiddleLeft)
    $l=New-Object Windows.Forms.Label
    $l.AutoEllipsis=$true;$l.SetBounds($X,$Y,$W,$H);$l.Text=(T $Text);$l.Font=$Font;$l.ForeColor=$Color;$l.BackColor=[Drawing.Color]::Transparent;$l.TextAlign=$Align
    return $l
}
function Add-ArtControl($Control,[int]$X,[int]$Y,[int]$W,[int]$H){$Control.Tag=New-Object Drawing.Rectangle($X,$Y,$W,$H);$form.Controls.Add($Control)}
$btnMin=New-Object CaptionButton;Add-ArtControl $btnMin 1148 8 82 43;$form.CaptionExempt.Add($btnMin)
$btnMax=New-Object CaptionButton;$btnMax.IsMax=$true;Add-ArtControl $btnMax 1230 8 82 43;$form.CaptionExempt.Add($btnMax)
$btnClose=New-Object CaptionButton;$btnClose.IsClose=$true;Add-ArtControl $btnClose 1312 8 80 43;$form.CaptionExempt.Add($btnClose)
$btnMax.OnActivated=[Action]{
    if($script:NormalSize){$form.ClientSize=$script:NormalSize;$script:NormalSize=$null}
    else{$script:NormalSize=$form.ClientSize;$area=[Windows.Forms.Screen]::FromControl($form).WorkingArea;$h=[Math]::Min($area.Height-24,[int]($area.Width*1125/1398));$form.ClientSize=New-Object Drawing.Size([int]($h*1398/1125),$h);$form.Location=New-Object Drawing.Point(($area.X+($area.Width-$form.Width)/2),($area.Y+($area.Height-$form.Height)/2))}
}
$lblCurrent=New-Object NeonCurrent;$lblCurrent.Text=(T '读取中');$lblCurrent.ForeColor=$cText;Add-ArtControl $lblCurrent 64 608 515 96
$lblWho=New-Label 0 0 1 1 '' $fTiny $cSub
$btnA=New-Object ArmorButton;$btnA.CardIndex=0;$btnA.TabIndex=0;Add-ArtControl $btnA 27 735 420 236
$btnB=New-Object ArmorButton;$btnB.CardIndex=1;$btnB.TabIndex=1;Add-ArtControl $btnB 489 735 420 236
$btnC=New-Object ArmorButton;$btnC.CardIndex=2;$btnC.TabIndex=2;Add-ArtControl $btnC 951 735 420 236
$btnD=New-Object ArmorButton;$btnD.CardIndex=3;$btnD.TabIndex=3;$btnD.Enabled=($null -ne $script:PortD);$btnD.Visible=$false
$shortcutFont=New-Object Drawing.Font('Segoe UI',11)
$keyA=New-Label 0 0 1 1 'Ctrl + Alt + 1' $shortcutFont $cText ([Drawing.ContentAlignment]::MiddleCenter);Add-ArtControl $keyA 27 972 420 27
$keyB=New-Label 0 0 1 1 'Ctrl + Alt + 2' $shortcutFont $cSub ([Drawing.ContentAlignment]::MiddleCenter);Add-ArtControl $keyB 489 972 420 27
$keyC=New-Label 0 0 1 1 'Ctrl + Alt + 3' $shortcutFont $cSub ([Drawing.ContentAlignment]::MiddleCenter);Add-ArtControl $keyC 951 972 420 27
$keyD=New-Label 0 0 1 1 $(if($null -ne $script:PortD){'Ctrl + Alt + 4'}else{(T 'HDMI 3 未配置')}) $shortcutFont $cSub ([Drawing.ContentAlignment]::MiddleCenter);$keyD.Visible=$false; $keyD.Font=New-Object Drawing.Font('Microsoft YaHei UI',9)
$barStatus=New-Object Windows.Forms.Panel;$barStatus.BackColor=$cIdle;Add-ArtControl $barStatus 65 709 4 18
$lblStatus=New-Label 0 0 1 1 '' $fSmall $cSub;Add-ArtControl $lblStatus 75 705 680 26
$lblHotkeys=New-Object NeonNotice;$lblHotkeys.Font=$fSmall;Add-ArtControl $lblHotkeys 608 670 722 35
$btnRefresh=New-Object ArmorButton;$btnRefresh.BigText=(T '↻ 刷新');$btnRefresh.BigFont=$fSmall;Add-ArtControl $btnRefresh 608 610 170 48
$tip=New-Object Windows.Forms.ToolTip
$tip.SetToolTip($btnA,($script:PortAWho+' · '+$script:PortALabel+' · VCP '+$script:PortA))
$tip.SetToolTip($btnB,($script:PortBWho+' · '+$script:PortBLabel+' · VCP '+$script:PortB))
$tip.SetToolTip($btnC,(T 'HDMI-2 · 现有输入值 18 / 0x12'))
$tip.SetToolTip($keyD,(T '项目未验证 HDMI-3 输入值，需配置 portD.value 后启用'))
# ---------------------------------------------------------------- state
$script:Busy = $false
$script:Quitting = $false
$script:ShownPort = -999
$script:ShownStatus = $null
$script:BusyTimer = $null

function Set-PortVisual {
    param($Button, [bool]$IsActive, [string]$Label, [string]$Hotkey)
    $Button.Active = $IsActive
    $Button.SmallText = $(if ($IsActive) { $Label + (T '  ·  正在输出') } else { $Label + '  ·  ' + $Hotkey })
    $Button.Invalidate()
}

function Set-Status {
    param([string]$Message, [ValidateSet('info', 'ok', 'warn', 'err', 'idle')][string]$Kind = 'info')
    if ($script:ShownStatus -ne ($Message + '|' + $Kind)) {
        Write-Log ($Kind + ' ' + $Message)
        $script:ShownStatus = $Message + '|' + $Kind
        $lblStatus.Text = T $Message
        switch ($Kind) {
            'ok'   { $lblStatus.ForeColor = $cOk;   $barStatus.BackColor = $cOk }
            'warn' { $lblStatus.ForeColor = $cWarn; $barStatus.BackColor = $cWarn }
            'err'  { $lblStatus.ForeColor = $cErr;  $barStatus.BackColor = $cErr }
            'idle' { $lblStatus.ForeColor = $cHint; $barStatus.BackColor = $cIdle }
            default { $lblStatus.ForeColor = $cSub;  $barStatus.BackColor = $cIdle }
        }
    }
}

function Update-ConnectionStates([int]$Current){
    $detected=[int[]]@()
    if($SelfTest -and $null -ne $PreviewConnectedPorts){$detected=[int[]]$PreviewConnectedPorts}
    else{
        try{
            if([DdcCi]::DeviceNames.Count -gt $script:MonitorIndex){$gdi=[DdcCi]::DeviceNames[$script:MonitorIndex];$detected=[DisplayConnections]::Detect($gdi,$Current,$script:HostHdmiInput)}
        }catch{Write-Log ((T '连接检测失败: ')+$_.Exception.Message)}
    }
    $script:DetectedPorts=$detected
    $items=@(@{Button=$btnA;Value=$script:PortA;Name=$script:PortALabel},@{Button=$btnB;Value=$script:PortB;Name=$script:PortBLabel},@{Button=$btnC;Value=$script:PortC;Name='HDMI-2'},@{Button=$btnD;Value=$script:PortD;Name='HDMI-3'})
    foreach($item in $items){
        $value=$item.Value
        $state=if($null -ne $value){[ConnectionEvidence]::Resolve([int]$value,$Current,$detected,$script:ConnectionOverrides)}else{-1}
        $item.Button.ConnectionState=$state;$item.Button.Invalidate()
        $description=switch($state){1{(T '已连接 · 彩色人物')}0{(T '确认未连接 · 灰色人物')}default{(T '连接未确认 · 灰色人物')}}
        $tip.SetToolTip($item.Button,($item.Name+' · '+$description+(T '；红框只表示当前输入')))
    }
}
function Update-PortStatus {
    if ($script:Busy) { return -1 }
    $cur = Read-CurrentPort
    Update-ConnectionStates $cur
    if ($cur -eq $script:ShownPort) { return $cur }

    if ($cur -lt 0) {
        $script:ShownPort = -1
        $lblCurrent.Text = (T '读不到')
        $lblCurrent.ForeColor = $cWarn
        $lblWho.Text = (T '读取失败 · 请检查显示器选择与 DDC/CI')
        Set-PortVisual $btnA $false $script:PortALabel 'Ctrl+Alt+1'
        Set-PortVisual $btnB $false $script:PortBLabel 'Ctrl+Alt+2'
        $btnC.Active=$false;$btnC.Invalidate();$btnD.Active=$false;$btnD.Invalidate()
        return -1
    }

    $script:ShownPort = $cur
    $info = $script:Names[$cur]
    if ($info) {
        $lblCurrent.Text = $info.Port
        $lblWho.Text = ((T '{0} · 正在输出 · 0x{1:X2}') -f $info.Who, $cur)
    }
    else {
        $lblCurrent.Text = ('0x{0:X2}' -f $cur)
        $lblWho.Text = (T '显示器上的其他输入源')
    }
    $lblCurrent.ForeColor = $cText
    Set-PortVisual $btnA ($cur -eq $script:PortA) $script:PortALabel 'Ctrl+Alt+1'
    Set-PortVisual $btnB ($cur -eq $script:PortB) $script:PortBLabel 'Ctrl+Alt+2'
    $btnC.Active=($cur -eq $script:PortC);$btnC.Invalidate();$btnD.Active=($null -ne $script:PortD -and $cur -eq $script:PortD);$btnD.Invalidate()
    $keyA.ForeColor=if($btnA.Active){$cText}else{$cSub};$keyB.ForeColor=if($btnB.Active){$cText}else{$cSub};$keyC.ForeColor=if($btnC.Active){$cText}else{$cSub};$keyD.ForeColor=if($btnD.Active){$cText}else{$cSub}
    return $cur
}

function Invoke-PortChange {
    param([int]$Value, [string]$Who, [string]$Label)

    if ($script:Busy) { return }
    $cur = Read-CurrentPort
    if ($cur -eq $Value) {
        Set-Status ((T '已经在') + $Who) 'info'
        return
    }

    $script:Busy = $true
    $btnA.Enabled = $false
    $btnB.Enabled = $false; $btnC.Enabled=$false; $btnD.Enabled=$false
    Set-Status ((T '正在切换到') + $Label + (T ' · 显示器会黑屏 2–3 秒')) 'warn'

    $ok = Write-PortSwitch $Value
    if (-not $ok) {
        $script:Busy = $false
        $btnA.Enabled = $true
        $btnB.Enabled = $true; $btnC.Enabled=$true; $btnD.Enabled=($null -ne $script:PortD)
        Set-Status (T '切换指令没有发出去 · 检查 DDC/CI 是否开启') 'err'
        return
    }

    $script:PendingValue = $Value
    $script:PendingLabel = $Label
    if ($script:BusyTimer) { $script:BusyTimer.Stop(); $script:BusyTimer.Dispose() }
    $script:BusyTimer = New-Object System.Windows.Forms.Timer
    $script:BusyTimer.Interval = 1500
    $script:BusyTimer.Add_Tick({
        $script:BusyTimer.Stop()
        $script:Busy = $false
        $btnA.Enabled = $true
        $btnB.Enabled = $true; $btnC.Enabled=$true; $btnD.Enabled=($null -ne $script:PortD)
        $script:ShownPort = -999          # force a re-read after switching
        Update-PortStatus | Out-Null
        if ($script:ShownPort -eq $script:PendingValue) { Set-Status ((T '已切换到') + $script:PendingLabel) 'ok' }
        elseif ($script:ShownPort -ge 0) { Set-Status (T '切换失败 · 显示器仍在其他输入源') 'err' }
        else { Set-Status (T '切换指令已发送 · 未读到确认') 'warn' }
    })
    $script:BusyTimer.Start()
}

$btnA.OnActivated = [System.Action]{ & $script:InvokePortA }
$btnB.OnActivated = [System.Action]{ & $script:InvokePortB }
$btnC.OnActivated=[Action]{Invoke-PortChange $script:PortC "HDMI-2" "HDMI-2"}
$btnD.OnActivated=[Action]{if($null -ne $script:PortD){Invoke-PortChange $script:PortD "HDMI-3" "HDMI-3"}}
$btnRefresh.OnActivated = [System.Action]{
    $script:ShownPort = -999
    Update-PortStatus | Out-Null
    if ($script:ShownPort -lt 0) { Set-Status (T '读取失败 · 请检查 DDC/CI 或打开设置') 'warn' } else { Set-Status (T '已刷新') 'info' }
}
$btnMin.OnActivated = [System.Action]{ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized }
$btnClose.OnActivated = [System.Action]{ if ($tray) { $form.Hide() } else { $form.Close() } }

$script:InvokePortA = { Invoke-PortChange $script:PortA $script:PortAWho $script:PortALabel }
$script:InvokePortB = { Invoke-PortChange $script:PortB $script:PortBWho $script:PortBLabel }

function Show-Settings {
    $d = New-Object System.Windows.Forms.Form
    $settingCombos=@()
    $d.Text = (T 'EVA-02 · 输入源设置'); $d.ClientSize = New-Object System.Drawing.Size(470,530)
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false
    $d.BackColor = $form.BackColor; $d.ForeColor = $cText; $d.Font = $fSmall
    $d.Controls.Add((New-Label 16 12 350 25 (T '显示器（DDC/CI 枚举顺序）') $fSmall $cText))
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.SetBounds(16,42,358,26); $combo.DropDownStyle = 'DropDownList'
    $mons = @([DdcCi]::Open())
    try { for($i=0;$i -lt $mons.Count;$i++) { [void]$combo.Items.Add(('{0}: {1}' -f $i,$mons[$i].szPhysicalMonitorDescription)) } }
    finally { foreach($m in $mons) { [DdcCi]::Close($m.hPhysicalMonitor) } }
    if($combo.Items.Count -gt 0) { $combo.SelectedIndex = [Math]::Min($script:MonitorIndex,$combo.Items.Count-1) }
    $d.Controls.Add($combo)
    $d.Controls.Add((New-Label 16 78 350 25 (T 'VCP 0x60 输入值（保留现有配置映射）') $fSmall $cText))
    $va = New-Object System.Windows.Forms.NumericUpDown; $va.Maximum=255; $va.Value=$script:PortA; $va.SetBounds(16,112,160,26)
    $vb = New-Object System.Windows.Forms.NumericUpDown; $vb.Maximum=255; $vb.Value=$script:PortB; $vb.SetBounds(212,112,160,26)
    $d.Controls.Add($va); $d.Controls.Add($vb)
    $d.Controls.Add((New-Label 16 142 170 20 ($script:PortAWho+' / '+$script:PortALabel) $fTiny $cSub))
    $d.Controls.Add((New-Label 212 142 170 20 ($script:PortBWho+' / '+$script:PortBLabel) $fTiny $cSub))
    $d.Controls.Add((New-Label 16 175 140 25 (T '界面缩放（重启生效）') $fSmall $cText))
    $scale = New-Object System.Windows.Forms.ComboBox; $scale.SetBounds(212,175,160,26); $scale.DropDownStyle='DropDownList'
    [void]$scale.Items.AddRange(@('100%','125%','150%')); $scale.SelectedIndex = [int](($script:UiScale-1)/0.25); $d.Controls.Add($scale)
    $d.Controls.Add((New-Label 16 220 360 24 (T '其他电脑的接口无法直接查询，可在下方确认连接') $fTiny $cSub))
    $rows=@(@{Value=$script:PortA;Name=$script:PortALabel},@{Value=$script:PortB;Name=$script:PortBLabel},@{Value=$script:PortC;Name='HDMI-2'})
    for($i=0;$i -lt $rows.Count;$i++){
        $row=$rows[$i];$y=250+$i*31
        $d.Controls.Add((New-Label 16 $y 180 26 $row.Name $fSmall $cSub))
        $choice=New-Object Windows.Forms.ComboBox;$choice.SetBounds(212,$y,160,26);$choice.DropDownStyle='DropDownList'
        [void]$choice.Items.AddRange(@((T '自动检测'),(T '确认已连接'),(T '确认未连接')));$choice.SelectedIndex=0
        if($null -ne $row.Value -and $script:ConnectionOverrides.ContainsKey([int]$row.Value)){$choice.SelectedIndex=if($script:ConnectionOverrides[[int]$row.Value] -eq 1){1}else{2}}
        if($null -eq $row.Value){$choice.Enabled=$false}
        $settingCombos+=@{Value=$row.Value;Combo=$choice};$d.Controls.Add($choice)
    }
    $d.Controls.Add((New-Label 16 382 190 26 (T '本机 HDMI 接在哪一口') $fSmall $cSub))
    $hostHdmi=New-Object Windows.Forms.ComboBox;$hostHdmi.SetBounds(212,382,160,26);$hostHdmi.DropDownStyle='DropDownList'
    [void]$hostHdmi.Items.AddRange(@((T '自动 / 未确认'),'HDMI-1','HDMI-2'));$hostHdmi.SelectedIndex=if($script:HostHdmiInput -eq 17){1}elseif($script:HostHdmiInput -eq 18){2}else{0};$d.Controls.Add($hostHdmi)
    $d.Controls.Add((New-Label 16 427 185 26 (T '语言 / Language') $fSmall $cText))
    $language=New-Object Windows.Forms.ComboBox;$language.SetBounds(212,427,160,26);$language.DropDownStyle='DropDownList';[void]$language.Items.AddRange(@('中文','English'));$language.SelectedIndex=if($script:Language -eq 'en'){1}else{0};$d.Controls.Add($language)
    $save = New-Object System.Windows.Forms.Button; $save.Text=(T '保存'); $save.SetBounds(270,480,102,30); $d.Controls.Add($save)
    $save.Add_Click({
        if($va.Value -eq $vb.Value) { [void][System.Windows.Forms.MessageBox]::Show((T '两个输入源不能使用相同值。')); return }
        try {
            $overrides=[ordered]@{}
            $script:ConnectionOverrides.Clear()
            for($i=0;$i -lt $settingCombos.Count;$i++){
                $row=$settingCombos[$i];$port=if($i -eq 0){[int]$va.Value}elseif($i -eq 1){[int]$vb.Value}else{$row.Value}
                if($null -ne $port -and $row.Combo.SelectedIndex -gt 0){$state=if($row.Combo.SelectedIndex -eq 1){1}else{0};$script:ConnectionOverrides[[int]$port]=$state;$overrides[[string]$port]=$state}
            }
            $script:HostHdmiInput=if($hostHdmi.SelectedIndex -eq 1){17}elseif($hostHdmi.SelectedIndex -eq 2){18}else{-1}
            $script:Language=if($language.SelectedIndex -eq 1){'en'}else{'zh'}; Apply-Language
            $data = [ordered]@{language=$script:Language;connectionOverrides=$overrides;hostHdmiInput=$script:HostHdmiInput; monitorIndex=$(if($combo.SelectedIndex -ge 0){$combo.SelectedIndex}else{$script:MonitorIndex}); uiScale=(1+$scale.SelectedIndex*0.25); portA=@{value=[int]$va.Value;label=$script:PortALabel;who=$script:PortAWho}; portB=@{value=[int]$vb.Value;label=$script:PortBLabel;who=$script:PortBWho}; portD=@{value=$script:PortD} }
            $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
            $script:PortA=[int]$va.Value; $script:PortB=[int]$vb.Value; $script:MonitorIndex=$data.monitorIndex
            $script:Names[$script:PortA]=@{Port=$script:PortALabel;Who=$script:PortAWho}; $script:Names[$script:PortB]=@{Port=$script:PortBLabel;Who=$script:PortBWho}
            $script:ShownPort=-999; Update-PortStatus | Out-Null; Set-Status (T '设置已保存 · 缩放重启生效') 'info'; $d.Close()
        } catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,(T '保存失败')) }
    })
    if($SelfTest) {
        $dialogTimer=New-Object System.Windows.Forms.Timer
        $dialogTimer.Interval=300
        $dialogTimer.Add_Tick({
            $dialogTimer.Stop()
            if($SelfTestSaveSettings){$settingCombos[1].Combo.SelectedIndex=1};if($SelfTestLanguage){$language.SelectedIndex=if($SelfTestLanguage -eq 'en'){1}else{0}}
            $bitmap=New-Object System.Drawing.Bitmap($d.Width,$d.Height)
            $d.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$d.Width,$d.Height)))
            $bitmap.Save(($ShotPath+'.settings.png')); $bitmap.Dispose()
            if($va.Value -ne $script:PortA -or $vb.Value -ne $script:PortB) { throw 'Settings input mapping mismatch' }
            if($SelfTestSaveSettings){$save.PerformClick()}else{$d.Close()}
        })
        $dialogTimer.Start()
    }
    [void]$d.ShowDialog($form)
    if($dialogTimer){$dialogTimer.Dispose()}
    $d.Dispose()
}
$btnSettings=New-Object ArmorButton;$btnSettings.ActionIndex=0;$btnSettings.TabIndex=5;$btnSettings.OnActivated=[Action]{Show-Settings};Add-ArtControl $btnSettings 835 1011 180 74
$btnLogs=New-Object ArmorButton;$btnLogs.ActionIndex=1;$btnLogs.TabIndex=6;$btnLogs.OnActivated=[Action]{if(-not(Test-Path $script:LogPath)){Write-Log (T '日志初始化')};Start-Process notepad.exe -ArgumentList ('"'+$script:LogPath+'"')};Add-ArtControl $btnLogs 1022 1011 173 74
$btnExit=New-Object ArmorButton;$btnExit.ActionIndex=2;$btnExit.TabIndex=7;$btnExit.OnActivated=[Action]{$script:Quitting=$true;$form.Close()};Add-ArtControl $btnExit 1199 1011 170 74
$form.LayoutArt()
# ---------------------------------------------------------------- tray
$tray = $null
if (-not $SelfTest) {
    try {
        $tray = New-Object System.Windows.Forms.NotifyIcon
        if ($form.Icon) { $tray.Icon = $form.Icon }
        $tray.Text = (T '显示器输入源切换')
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $miShow = $menu.Items.Add((T '显示 / 隐藏'))
        $miShow.Add_Click({
            if ($form.Visible) { $form.Hide() }
            else { [AppInstance]::BringToFront($form) }
        })
        [void]$menu.Items.Add((T '切换到') + $script:PortAWho).Add_Click({ & $script:InvokePortA })
        [void]$menu.Items.Add((T '切换到') + $script:PortBWho).Add_Click({ & $script:InvokePortB })
        [void]$menu.Items.Add('-')
        [void]$menu.Items.Add((T '退出')).Add_Click({ $script:Quitting = $true; $form.Close() })
        $tray.ContextMenuStrip = $menu
        $tray.Visible = $true; $form.ShowInTaskbar=$false
        $tray.Add_DoubleClick({ [AppInstance]::BringToFront($form) })
    }
    catch { $tray = $null }
}

$wakeTimer=$null
if($script:AppGate){
    $wakeTimer=New-Object Windows.Forms.Timer;$wakeTimer.Interval=150
    $wakeTimer.Add_Tick({
        if($script:AppGate.ExitRequested()){$script:Quitting=$true;$form.Close();return}
        if($script:AppGate.ConsumeActivation()){[AppInstance]::BringToFront($form);Write-Log (T '重复启动：已唤出并置顶现有窗口')}
    });$wakeTimer.Start()
}
$script:HideTipShown = $false
$form.Add_FormClosing({
    param($s, $e)
    if (-not $script:Quitting -and $tray) {
        $e.Cancel = $true
        $form.Hide()
        if (-not $script:HideTipShown) {
            $script:HideTipShown = $true
            $tray.ShowBalloonTip(3500, (T '仍在后台运行'),
                (T '热键 Ctrl+Alt+1 / 2 照常可用。右键托盘图标可彻底退出。'), [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
})

$form.Add_FormClosed({
    if ($wakeTimer) { $wakeTimer.Stop(); $wakeTimer.Dispose() }
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    if ($script:BusyTimer) { $script:BusyTimer.Stop(); $script:BusyTimer.Dispose() }
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    if ([NeonSkin]::Art) { [NeonSkin]::Art.Dispose() }; $tip.Dispose()
    if ($sink) { $sink.Dispose() }
})

$form.Add_Shown({
    if($script:AppGate){$script:AppGate.Publish($form.Handle,$(if($tray){1}else{0}))}
    Update-PortStatus | Out-Null
    if ($script:ShownPort -lt 0) { Set-Status (T '未读到输入源 · 检查 DDC/CI 和显示器选择') 'warn' }
    else { Set-Status (T '已读取当前输入源') 'ok' }
    if ($script:HotkeyInfo -match 'False|failed') { $lblHotkeys.Text = (T '快捷键注册失败 · 已被占用，请使用输入卡片'); $lblHotkeys.ForeColor = $cWarn }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({
    if ($form.Visible -and -not $script:Busy) { Update-PortStatus | Out-Null }
})
$timer.Start()

# global hotkeys: Ctrl+Alt+1 -> desktop, Ctrl+Alt+2 -> laptop
$script:HotkeyInfo = (T '未启用')
try {
    $sink = New-Object HotkeySink
    $modCtrlAlt = 0x0003
    $ok1 = $sink.Register($modCtrlAlt, 0x31, 201)
    $ok2 = $sink.Register($modCtrlAlt, 0x32, 202)
    $ok3 = $sink.Register($modCtrlAlt,0x33,203)
    $ok4 = if($null -ne $script:PortD){$sink.Register($modCtrlAlt,0x34,204)}else{$true}
    $sink.Add_Pressed({
        param($Sender, $Id)
        if ($Id -eq 201) { & $script:InvokePortA }
        elseif ($Id -eq 202) { & $script:InvokePortB }
        elseif($Id -eq 203){Invoke-PortChange $script:PortC "HDMI-2" "HDMI-2"}
        elseif($Id -eq 204 -and $null -ne $script:PortD){Invoke-PortChange $script:PortD "HDMI-3" "HDMI-3"}
    })
    $script:HotkeyInfo = "Ctrl+Alt+1=$ok1 Ctrl+Alt+2=$ok2 Ctrl+Alt+3=$ok3 Ctrl+Alt+4=$ok4"
    if (-not ($ok1 -and $ok2 -and $ok3 -and $ok4)) { Set-Status (T '热键被其他程序占用 · 请点按钮切换') 'warn' }
}
catch {
    $script:HotkeyInfo = 'failed: ' + $_.Exception.Message
}

# ---------------------------------------------------------------- self test
if ($SelfTest) {
    if (-not $ShotPath) { $ShotPath = Join-Path $PSScriptRoot 'ui.png' }
    $form.TopMost = $true
    $shot = New-Object System.Windows.Forms.Timer
    $shot.Interval = 2000
    $shot.Add_Tick({
        $shot.Stop(); Show-Settings
        if($PreviewPort -eq 15 -and -not $btnA.Active){throw "DP active state failed"}
        if($PreviewPort -eq 18 -and -not $btnC.Active){throw "HDMI-2 active state failed"}
        try {
            $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
            $bmp.Save($script:ShotPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose()
            $bmp.Dispose()
        }
        catch { }
        $form.Close()
    })
    $shot.Start()
}

try { [System.Windows.Forms.Application]::Run($form) } finally { if($script:AppGate){$script:AppGate.Dispose()} }

if ($SelfTest) {
    $lines = @(
        ('ShotPath = ' + $ShotPath)
        ('FormSize = ' + $form.Width + 'x' + $form.Height)
        ('Skin = neon artwork slices + live controls / original icon')
        ('Hotkeys = ' + $script:HotkeyInfo)
        ('CurrentIn = ' + (Read-CurrentPort))
        ('Status = ' + $script:ShownStatus)
        ('SettingsSmoke = passed')
        ('ConnectionStates = '+$btnA.ConnectionState+','+$btnB.ConnectionState+','+$btnC.ConnectionState+','+$btnD.ConnectionState)
        ('DetectedPorts = '+($script:DetectedPorts -join ','))
    )
    $lines | Out-File -FilePath ($ShotPath + '.log') -Encoding utf8
}