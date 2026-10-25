# Cmd Tab Pro 设计方案

- 状态：已实施
- 日期：2026-09-01
- 用途：个人 macOS 工具

## 1. 目标

保留 macOS 原生 Cmd+Tab。普通 GUI 应用仍在运行，但最后一个窗口被 Cmd+W 关闭后，用户再次通过 Cmd+Tab 切换到该应用，工具补发一次 reopen 请求，让应用重新创建默认窗口并前置。

已经关闭的窗口对象无法恢复。工具请求应用重新展示或创建窗口，内容和状态由目标应用决定。

## 2. 完成标准

1. 不替换、不禁用系统 Cmd+Tab。
2. 兼容模式不需要辅助功能、输入监控或屏幕录制权限；增强自动模式只申请输入监控权限。
3. 工具启动后后台运行，菜单栏图标默认隐藏，无需配置即可工作。
4. 只处理 activationPolicy 为 regular 的普通 GUI 应用。
5. 兼容模式在应用激活后发送标准 reopen 请求；增强自动模式会额外处理 Cmd+Tab 完成后的无窗口应用。
6. 规范应用已有窗口时只前置，没有窗口时创建窗口。
7. 同一 PID 0.5 秒内只处理一次，避免 reopen 引发激活循环，同时允许快速关闭后切回。
8. 支持暂停、退出和登录时启动。
9. 展示近 7 天切换总量、每日趋势和切换最多的 5 个 App。
10. 统计只保存在本机，并自动淘汰 7 天前的数据。
11. 用户可以清除全部统计，复制不包含使用记录的诊断信息，并恢复部分默认设置。
12. 用户主动操作时可以打开 GitHub Releases，不进行后台更新检查。
13. 主页面依次使用“切换设置”“Dock 预览”“统计”“关于”四个原生工具栏页签，图标分别对应应用切换、Dock、统计图表和信息说明。
14. 支持在三套内置图标之间切换，重签名必须沿用原签名身份；证书或私钥不可用时保留原应用。
15. 用户于 2026-10-24 确认加入可选的已有窗口恢复、Dock 预览和点击最小化；不制作键盘端同 App 多窗口选择器，不增加顶部手势和分屏。

## 3. 运行链路

    原生 Cmd+Tab
          |
          v
    macOS 激活目标应用
          |
          v
    NSWorkspace didActivateApplicationNotification
          |
          v
    延迟 150ms，确认目标仍是前台应用
          |
          v
    NSWorkspace.launchApplication(at:configuration:)
          |
          v
    目标应用处理 reopen
          |
          +---- 已有窗口：保持现有窗口并前置
          |
          +---- 没有窗口：创建默认窗口并前置

兼容模式也会在 Dock、Spotlight 或其他方式激活应用时执行相同行为，但跳过 Finder。增强自动模式使用被动事件监听识别 Cmd+Tab 结束，并在发送 reopen 前确认目标应用没有顶层窗口，包括 Finder。

同一个激活通知也用于本地统计。统计记录目标 App 的 Bundle ID、显示名称和次数，不记录窗口标题或内容。reopen 可能再次触发激活通知，因此同一 PID 在 0.5 秒内只统计一次。

## 4. 为什么兼容模式跳过 Finder

通用窗口数量检查需要 Accessibility，首次运行必须由用户手动授权，而且 macOS 可能让授权前已启动的进程继续看到旧权限状态。这与“安装后直接使用”的目标冲突。

点击桌面也会激活 Finder，兼容模式无法从应用激活通知区分这次操作与主动切回 Finder，因此不向 Finder 发送 reopen。增强自动模式会在 Cmd+Tab 完成时对目标应用查询顶层窗口，用于区分页签关闭和窗口关闭；这个查询不维护窗口列表。

兼容模式的其他应用仍由 reopen 入口决定“已有窗口如何处理、没有窗口如何创建”。

## 5. 为什么使用废弃的 LaunchServices 入口

2026-08-31 在 macOS 26.5.2 上做了真实夹具验证：

- NSWorkspace.openApplication 返回成功，但不会向已经前台的无窗口应用投递 reopen。
- /usr/bin/open 返回成功，也不会在这条路径投递 reopen。
- NSWorkspace.launchApplication(at:configuration:) 可以投递 reopen，AltTab 同样使用该入口。

因此保留这个已废弃但行为必要的 API。编译会产生一条明确的 deprecation warning，不屏蔽其他编译警告。

## 6. 明确不做

- 不接管 Cmd+Tab 键盘事件
- 不使用 SkyLight 私有快捷键 API
- 不维护全局窗口清单；窗口增强按需读取目标 App 的窗口，并通过事件更新
- 基础兼容模式不使用 Accessibility；窗口与 Dock 增强按需申请辅助功能、屏幕录制权限
- 不移动窗口到其他 Space，不增加浏览器标签页管理
- 不替换系统切换面板；Dock 预览作为独立的可选面板
- 不增加应用白名单、黑名单或应用级配置
- 不引入第三方库、后台网络、遥测和自动更新系统

## 7. 用户体验

应用是 LSUIElement 菜单栏工具，不显示 Dock 图标，主页面按需显示。

正常手动启动或再次打开 App 时展示主页面；登录时自动启动保持菜单栏常驻，不主动弹出窗口。关闭主页面不会退出应用。
登录启动通过 open-application Apple event 的 `keyAEPropData == keyAELaunchedAsLogInItem` 识别；即使启动通知标记为默认启动，也不显示主页面。
原生主菜单注册 Cmd+W 关闭主页面和 Cmd+Q 退出应用。增强自动模式使用被动键盘监听，不修改或吞掉系统快捷键。

主页面使用 AppKit 原生窗口、NSTabViewController、NSSwitch、NSPopUpButton、系统字体和动态颜色。设置页统一使用 NSVisualEffectView 的 underWindowBackground 材质，卡片采用系统 controlBackgroundColor 和 separatorColor；分组标题放在功能块外。页签顺序为切换设置、Dock 预览、统计、关于。

主窗口内容区固定为 680 × 620，暂不提供自由缩放。保留四个工具栏页签；页面标题 24pt、设置标题 14pt、说明 12pt，控件使用标准尺寸。统一圆角分组、留白和行高，较长页面在固定宽度内纵向滚动，三套图标在同一行显示。

切换设置页提供自动唤回、唤回模式、开机自启动、界面主题、菜单栏图标和应用图标设置。Dock 预览页提供窗口恢复、Dock 面板、点击最小化和权限状态。统计页展示今日计数、7 天合计、7 天柱状图和 Top 5 App。关于页展示版本和 Bundle ID，并提供复制诊断信息、清除统计、恢复默认设置和检查更新。清除统计与恢复默认设置都必须二次确认。

诊断信息只包含运行环境和功能状态，不包含 App 名称、切换次数或其他统计记录。检查更新只打开 GitHub Releases。

授权状态展示窗口控制、屏幕录制和输入监控三项系统权限，按两列对齐；已授权使用系统绿色圆形勾选图标，悬停及读屏保留状态说明。输入监控提供独立授权按钮，明确仅增强自动模式需要；授权请求后显式打开输入监控设置页，避免系统不再弹提示时点击无反馈。刷新授权状态不改变当前唤回模式。未授权及标签模式无需录屏继续显示具体文字。Dock 面板和点击最小化的运行状态保留在诊断信息中。

新增功能的行为和权限见 [窗口恢复规格](Sources/Windows/WindowSpecs.md)、[Dock 规格](Sources/Dock/DockSpecs.md) 和 [Cmd+Tab 会话规格](Sources/Reopen/CmdTabMonitorSpecs.md)。

### 系统玻璃材质

- 设置窗口使用非不透明窗口和原生背景材质，四个工具栏页签由系统管理 Liquid Glass，内容卡片保持清晰的阅读层级。
- Dock 面板使用 NSGlassEffectView regular，将实际内容放入 contentView，避免用旧式 popover 模糊或自绘色块模拟玻璃。macOS 27 的 effectIsInteractive 通过版本检查启用，最低系统仍为 macOS 26。
- 菜单、确认框、开关、下拉框采用原生 AppKit 控件，不覆盖系统的材质和交互。减少透明度、增强对比度和减少动态效果由系统组件适配，不增加独立的玻璃强度设置或自绘动画。
- 设置布局在浅色、深色及对应的高对比度外观下检查；合成器中的真实玻璃需在运行窗口中验收，离屏位图只能检查布局。

依据：[Apple：Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[AppKit：NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)。

菜单仅提供：

- 当前运行状态
- 开启或暂停窗口自动唤回
- 登录时启动
- 界面主题：跟随系统、浅色或深色
- 显示或隐藏菜单栏图标，重新打开应用可进入主页面恢复
- 打开应用
- 退出
- 关于 Cmd Tab Pro，固定在菜单最底部

安装脚本完成后应用直接启动，不弹权限请求。

## 8. 项目形态

项目独立位于：

    cmd-tab-pro/

不属于 alt-tab-macos 仓库，也不依赖 AltTab 源码。

技术约束：

- Swift 5 语言模式
- AppKit，不使用 SwiftUI
- 纯代码 UI，不使用 Interface Builder
- 最低系统版本 macOS 26
- 使用 xcrun swiftc 编译，不创建 Xcode 工程或 Swift Package
- 本地安装优先复用配置的固定代码签名身份，未配置时使用 ad-hoc；启用 hardened runtime
- 仅构建 Apple Silicon arm64
- 固定 bundle ID：com.ares.cmd.tab

核心模块：

- `Sources/main.swift`：应用生命周期、菜单栏、登录启动和模块连接。
- `Sources/Reopen/`：原生 Cmd+Tab 会话识别、延迟目标选择和窗口唤回。
- `Sources/Windows/`：增强设置、AX 窗口查询与控制、窗口恢复规则。
- `Sources/Dock/`：Dock 命中与交互、悬浮面板和按需缩略图。
- `Sources/Dashboard/`：四个设置页面及共用样式。
- `Sources/Statistics/`：本地切换统计。
- `Sources/Appearance/`、`Sources/IconSwitcher/`：应用图标、签名身份校验与安全替换。
- `Resources/Info.plist`、`scripts/`：版本、安装、固定本机签名与公开打包。

## 9. 安装

scripts/install.sh 负责：

1. 校验 Info.plist。
2. 编译 arm64 Release 可执行文件。
3. 运行内置决策自检。
4. 组装应用，使用配置的签名身份签名；更新证书版时验证候选符合原指定要求。
5. 正常终止已安装的旧版本。
6. 失败时恢复旧 app bundle。
7. 安装到 /Applications/CmdTabPro.app 并启动。

登录时启动使用 SMAppService.mainApp，由用户在菜单栏开关。

默认图标为方案 2 `flat-option-2-cmd-tab`。安装脚本把三套 PNG 生成 16 到 1024 像素的完整 iconset，并分别打包为 ICNS。

用户切换图标时，主应用先把 CmdTabProIconSwitcher 复制到临时目录，再退出。辅助程序等待主进程结束，在 Applications 同目录创建完整 App 副本，在副本中替换图标、签名并验证，全部成功后再通过 Foundation 的安全替换 API 更新正式 App。原 App 在替换完成前保持不变，失败时恢复并验证备份，然后重启应用显示错误。

发布脚本使用 build-only 模式并固定选择方案 2，只生成暂存 App、ZIP 和校验文件，不终止、覆盖或启动本机已经安装的应用。

运行时图标切换依赖修改 App bundle 和重新签名，支持 ad-hoc 或本机能使用原私钥的证书签名；签名失败或身份变化时保留原应用。如果以后改用 Developer ID 和公证，应取消这项运行时能力，避免破坏签名。

## 10. 验证

### 内置自检

- 手动启动显示主页面；登录项启动在默认启动标记为 true 或缺失时均保持后台运行。
- 非默认启动保持后台运行；缺少启动元数据时允许手动进入主页面。
- 兼容模式下 Finder 激活不触发 reopen，其他应用继续唤回；增强自动模式允许通过 Cmd+Tab 唤回无窗口的 Finder。
- 普通前台应用允许 reopen。
- 已切到后台的应用不处理。
- 0.5 秒冷却内不重复处理。

### 真实验收夹具

正对照：

1. 临时普通应用创建一个窗口。
2. 关闭最后一个窗口，但保持进程运行。
3. 激活 Finder，再激活临时应用。
4. Cmd Tab Pro 运行时，临时应用收到 reopen 并重新创建窗口。

负对照：

1. 正常退出 Cmd Tab Pro。
2. 执行完全相同的夹具流程。
3. 临时应用保持 closed，不会重新创建窗口。

正对照通过、负对照失败，证明行为来自本工具。

### 统计测试

- 始终返回今天及前 6 天。
- 第 8 天数据被自动删除。
- 每日总量与分 App 数量一致。
- Top 5 按近 7 天总次数排序。
- 清除后计数、App 排名和持久化数据全部为空。

### 界面验收

- 主窗口内容区固定为 680 × 620，不显示缩放入口；长页面可以滚动至最后一项。
- 四个工具栏页签均可切换，没有文字、数字或按钮裁切。
- 浅色主题使用白色页面底和浅灰功能块，深色主题保持对应层级。
- 三套图标在切换设置页同一行完整显示，选中项有高亮边框。
- Cmd+W 关闭窗口但保留进程，Cmd+Q 退出应用。
- 唤回模式可以选择兼容模式或增强自动模式；增强自动模式需要输入监控权限，未获授权时继续使用兼容模式。
- 兼容模式下关闭应用最后一个窗口后点击桌面，不自动打开 Finder；增强自动模式下通过 Cmd+Tab 切回无窗口的 Finder 时可以唤回，有可见窗口时不重复唤回。
- 恢复默认设置只恢复自动唤回、菜单栏图标和界面主题，不影响统计、登录项和应用图标。

## 11. 风险与边界

最脆弱的假设是目标应用正确实现 reopen。规范 AppKit 应用会根据 hasVisibleWindows 决定是否创建窗口；部分跨平台应用可能忽略 reopen，或在已有窗口时错误地创建新窗口。

兼容模式不自动唤回 Finder，因此通过 Cmd+Tab 切回无窗口的 Finder 也不会创建窗口。增强自动模式会在实际发送 reopen 前查询目标 App 的顶层窗口，以避免把 Chrome 页签关闭误判为窗口关闭。

统计无法区分 Cmd+Tab、Dock、Spotlight 和鼠标点击，只能准确识别成为前台的目标 App。页面文案明确使用“应用切换”，不把数据描述为“Cmd+Tab 次数”。

旧 LaunchServices API 已废弃，未来 macOS 可能移除或改变行为。每次系统大版本升级后应重新运行真实夹具验收。

## 12. 回滚

工具不修改系统 Cmd+Tab，不写目标应用数据。退出应用即可停止功能。卸载前关闭登录时启动，然后删除：

    /Applications/CmdTabPro.app

## 13. 开源准备

仓库保持无第三方依赖，安装脚本、设计说明和行为边界全部随源码提供，采用 PolyForm Noncommercial License 1.0.0，完整条款见 LICENSE。

公开预编译包仅提供 macOS 26 arm64 ZIP，使用 ad-hoc 签名并接受 Gatekeeper 首次阻止，由用户在“隐私与安全性”中手动允许。发布包同时提供 SHA-256 校验文件。若以后要求无提示安装，再改用 Developer ID Application 签名和 notarization。

## 14. 官方 API 依据

- [NSWorkspace.didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/1455076-cgwindowlistcopywindowinfo)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
