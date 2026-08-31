# Cmd Tab Pro 设计方案

- 状态：已实施
- 日期：2026-08-31
- 用途：个人 macOS 工具

## 1. 目标

保留 macOS 原生 Cmd+Tab。普通 GUI 应用仍在运行，但最后一个窗口被 Cmd+W 关闭后，用户再次通过 Cmd+Tab 切换到该应用，工具补发一次 reopen 请求，让应用重新创建默认窗口并前置。

已经关闭的窗口对象无法恢复。工具请求应用重新展示或创建窗口，内容和状态由目标应用决定。

## 2. 完成标准

1. 不替换、不禁用系统 Cmd+Tab。
2. 不需要辅助功能、输入监控或屏幕录制权限。
3. 工具启动后常驻菜单栏，无需配置即可工作。
4. 只处理 activationPolicy 为 regular 的普通 GUI 应用。
5. 应用激活后发送标准 reopen 请求。
6. 规范应用已有窗口时只前置，没有窗口时创建窗口。
7. 同一 PID 0.5 秒内只处理一次，避免 reopen 引发激活循环，同时允许快速关闭后切回。
8. 支持暂停、退出和登录时启动。
9. 展示近 7 天切换总量、每日趋势和切换最多的 5 个 App。
10. 统计只保存在本机，并自动淘汰 7 天前的数据。

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

工具也会在 Dock、Spotlight 或其他方式激活应用时执行相同行为。NSWorkspace 的激活通知不提供输入来源，为了只区分 Cmd+Tab 而增加全局键盘监听不值得。

同一个激活通知也用于本地统计。统计记录目标 App 的 Bundle ID、显示名称和次数，不记录窗口标题或内容。reopen 可能再次触发激活通知，因此同一 PID 在 0.5 秒内只统计一次。

## 4. 为什么不检查窗口数量

检查窗口数量需要 Accessibility，首次运行必须由用户手动授权，而且 macOS 可能让授权前已启动的进程继续看到旧权限状态。这与“安装后直接使用”的目标冲突。

公共 CGWindowList 查询对最小化窗口、其他 Space 和部分应用的隐藏窗口也不够可靠。为了修正这些边界而引入 WindowServer 或 AX 模型，会重新走向 AltTab 的复杂度。

reopen 本来就是目标应用决定“已有窗口如何处理、没有窗口如何创建”的标准入口。第一版直接把判断交给目标应用。

## 5. 为什么使用废弃的 LaunchServices 入口

2026-08-31 在 macOS 26.5.2 上做了真实夹具验证：

- NSWorkspace.openApplication 返回成功，但不会向已经前台的无窗口应用投递 reopen。
- /usr/bin/open 返回成功，也不会在这条路径投递 reopen。
- NSWorkspace.launchApplication(at:configuration:) 可以投递 reopen，AltTab 同样使用该入口。

因此保留这个已废弃但行为必要的 API。编译会产生一条明确的 deprecation warning，不屏蔽其他编译警告。

## 6. 明确不做

- 不接管 Cmd+Tab 键盘事件
- 不使用 SkyLight 私有快捷键 API
- 不维护窗口列表
- 不使用 Accessibility
- 不识别 Space、屏幕和标签页
- 不显示缩略图或自定义切换面板
- 不增加应用白名单、黑名单或配置文件
- 不引入第三方库、网络、遥测和更新系统

## 7. 用户体验

应用是 LSUIElement 菜单栏工具，不显示 Dock 图标，主页面按需显示。

正常手动启动或再次打开 App 时展示主页面；登录时自动启动保持菜单栏常驻，不主动弹出窗口。关闭主页面不会退出应用。

主页面使用 AppKit 原生窗口、NSVisualEffectView、NSSwitch、NSPopUpButton、系统字体和动态颜色，包含今日计数、7 天合计、7 天柱状图、Top 5 App 和三项设置。

主窗口固定为 760 × 720，暂不提供自由缩放，避免小尺寸下统计和设置区域被压缩。

菜单仅提供：

- 当前运行状态
- 开启或暂停窗口自动唤回
- 登录时启动
- 界面主题：跟随系统、浅色或深色
- 隐藏菜单栏图标，重新打开应用可恢复
- 打开主页面
- 退出

安装脚本完成后应用直接启动，不弹权限请求。

## 8. 项目形态

项目独立位于：

    /Users/wujunjie/Documents/ai_workspace/alt-tab/cmd-tab-pro

不属于 alt-tab-macos 仓库，也不依赖 AltTab 源码。

技术约束：

- Swift 5 语言模式
- AppKit，不使用 SwiftUI
- 纯代码 UI，不使用 Interface Builder
- 最低系统版本 macOS 26
- 使用 xcrun swiftc 编译，不创建 Xcode 工程或 Swift Package
- 本地安装使用 ad-hoc 签名并启用 hardened runtime
- 仅构建 Apple Silicon arm64
- 固定 bundle ID：com.ares.cmd.tab

核心实现文件：

1. Sources/main.swift
2. Sources/Statistics/SwitchStatistics.swift
3. Sources/Dashboard/DashboardWindowController.swift
4. Resources/Info.plist
5. scripts/install.sh
6. scripts/package-release.sh

## 9. 安装

scripts/install.sh 负责：

1. 校验 Info.plist。
2. 编译 arm64 Release 可执行文件。
3. 运行内置决策自检。
4. 组装并 ad-hoc 签名 CmdTabPro.app。
5. 正常终止已安装的旧版本。
6. 失败时恢复旧 app bundle。
7. 安装到 /Applications/CmdTabPro.app 并启动。

登录时启动使用 SMAppService.mainApp，由用户在菜单栏开关。

选定图标为方案 1 `icon-option-1-window-switch`。安装时从 Assets/AppIcon.png 生成 16 到 1024 像素的完整 iconset，并打包为 AppIcon.icns。Apple 在 macOS 26 推荐 Icon Composer 的多层 Liquid Glass 图标，但本机尚未安装 Icon Composer；以后可在不改应用逻辑的情况下，把同一视觉拆层升级为 .icon 资源。

## 10. 验证

### 内置自检

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

## 11. 风险与边界

最脆弱的假设是目标应用正确实现 reopen。规范 AppKit 应用会根据 hasVisibleWindows 决定是否创建窗口；部分跨平台应用可能忽略 reopen，或在已有窗口时错误地创建新窗口。

第一版不增加应用特例。只有个人实际使用中确认某个高频应用存在副作用时，才增加一个很小的 bundle ID 排除列表。

统计无法区分 Cmd+Tab、Dock、Spotlight 和鼠标点击，只能准确识别成为前台的目标 App。页面文案明确使用“应用切换”，不把数据描述为“Cmd+Tab 次数”。

旧 LaunchServices API 已废弃，未来 macOS 可能移除或改变行为。每次系统大版本升级后应重新运行真实夹具验收。

## 12. 回滚

工具不修改系统 Cmd+Tab，不写目标应用数据。退出应用即可停止功能。卸载前关闭登录时启动，然后删除：

    /Applications/CmdTabPro.app

## 13. 开源准备

仓库保持无第三方依赖，安装脚本、设计说明和行为边界全部随源码提供。公开发布前必须选择并添加 LICENSE；推荐 MIT，但许可证属于项目所有者决策，不在本次改名中代选。

公开预编译包仅提供 macOS 26 arm64 ZIP，使用 ad-hoc 签名并接受 Gatekeeper 首次阻止，由用户在“隐私与安全性”中手动允许。发布包同时提供 SHA-256 校验文件。若以后要求无提示安装，再改用 Developer ID Application 签名和 notarization。

## 14. 官方 API 依据

- [NSWorkspace.didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
