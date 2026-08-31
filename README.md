# Cmd Tab Pro

保留 macOS 原生 Cmd+Tab。切换到普通应用时自动发送一次标准 reopen 请求：应用已有窗口时正常前置，没有窗口时由应用重新创建窗口。

## 安装

在项目目录运行：

    bash scripts/install.sh

安装脚本会为 macOS 26 构建 arm64 + x86_64 通用二进制、生成 AppIcon.icns、启用 hardened runtime、签名、复制到 /Applications 并启动，不需要辅助功能权限。

## 使用

工具启动后显示在菜单栏，无需配置。正常使用系统原生 Cmd+Tab 即可。

菜单栏可以暂停功能、设置登录时启动或退出。

## 验证

安装并启动应用后运行正对照：

    bash Tests/Acceptance/run.sh 1

退出 Cmd Tab Pro 后运行负对照：

    bash Tests/Acceptance/run.sh 0

## 边界

- Cmd+Q 已退出的应用不会出现在 Cmd+Tab 中，也不会由本工具启动。
- 工具不检查窗口数量，而是把是否需要创建窗口交给目标应用自己的 reopen 处理。
- 规范的 macOS 应用在已有窗口时只前置，在没有窗口时创建窗口。
- 少数不规范应用可能忽略 reopen，或把它解释为新建窗口。

## 卸载

先在菜单栏关闭“登录时启动”并退出，再删除：

    /Applications/Cmd Tab Pro.app

## 开源准备

项目不依赖第三方库，构建和安装流程都在仓库内。发布到公开仓库前还需要选择许可证；推荐 MIT，但不会在未经确认的情况下自动添加。

当前部署目标为 macOS 26.0。公开发布预编译版本时仍需要 Developer ID 签名和 Apple notarization；本地安装脚本使用 ad-hoc 签名，仅用于个人构建。
