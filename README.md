# Monitor Input Switcher / 显示器输入源切换

A portable Windows DDC/CI monitor input switcher with an EVA-02 themed interface.
Windows 10/11; Windows PowerShell 5.1 and .NET Framework; no additional runtime installation.

## 使用 / Usage

先运行 `Build.ps1` 构建，再双击 `MonitorSwitch-Neon.exe`。在设置中选择“中文 / English”并保存，立即切换语言，重启后保持。
Build with `Build.ps1`, then run `MonitorSwitch-Neon.exe`. Choose Chinese or English in Settings and Save. Language changes immediately and persists.

- DP、HDMI 1、HDMI 2 三张输入卡片；Ctrl+Alt+1/2/3 快捷键。
- Three input cards: DP, HDMI 1 and HDMI 2; global shortcuts Ctrl+Alt+1/2/3.
- 关闭窗口收起到托盘；再次启动唤起已有窗口，始终只有一个托盘图标。
- Closing hides to the tray. Launching again restores the existing instance.
- 当前输入边框高亮；人物彩色表示 Windows 检测或用户确认已连接。
- The border marks the active input. Color portraits indicate locally detected or user-confirmed connections.
- 本机通常无法查询另一台电脑连接的输入。手动确认不会随拔线自动改变。
- Remote computer connections cannot generally be queried locally. Manual confirmation does not automatically change when a cable is unplugged.

## 输入映射 / Input mapping

ASUS XG27AQ verified VCP 0x60 values: DisplayPort=15 (0x0F), HDMI 1=17 (0x11), HDMI 2=18 (0x12).
Other monitors may use different mappings. Enable DDC/CI in your monitor OSD. Settings preserve the configured DP/HDMI 1 values.

## 构建 / Build

Run `Build.ps1` using Windows PowerShell 5.1. The launcher depends on the scripts, C# files, icon and assets in this directory; the EXE alone is insufficient.

## 验证 / Verification

Run `Test-Logic.ps1`, `Test-Connection.ps1`, `Test-CardLayout.ps1`, and `Test-Language.ps1` in Windows PowerShell 5.1.
`Test-SingleInstance.ps1` launches and exits a real application instance. Avoid running it while using the application.
Visual self-test: `MonitorSwitch.ps1 -SelfTest -PreviewPort 15 -ShotPath <absolute PNG path>`.
Tests simulate input states; successful tests do not prove a physical input change on every monitor.

## 开源准备 / Publishing preparation

Code is available under PolyForm Noncommercial 1.0.0: noncommercial use, modification and sharing are permitted subject to LICENSE and NOTICE. Commercial use and sale are not granted. This is source-available software, rather than OSI-approved open source. Theme contributions are separately licensed under CC BY-NC-SA 4.0 only to the extent the contributor can grant those rights. Third-party EVA rights are excluded; see ASSETS.md.
Personal `config.json`, runtime logs, generated EXEs and test screenshots are ignored. Share a sanitized `config.example.json` instead.

Windows APIs: QueryDisplayConfig, GetVCPFeatureAndVCPFeatureReply, SetVCPFeature.

The sample config contains only a language preference. Copy it to config.json if desired; configure monitor input mappings and connections locally in Settings.
