# Cmd Tab Pro

保留 macOS 原生 Cmd+Tab。切换到普通应用时自动发送一次标准 reopen 请求：应用已有窗口时正常前置，没有窗口时由应用重新创建窗口。

## 安装

在项目目录运行：

    bash scripts/install.sh

安装脚本会为 macOS 26 构建 Apple Silicon arm64 二进制、生成 AppIcon.icns、启用 hardened runtime、进行 ad-hoc 签名、复制到 /Applications 并启动，不需要辅助功能权限。

## 使用

工具启动后显示在菜单栏，无需配置。正常使用系统原生 Cmd+Tab 即可。

菜单栏可以暂停功能、设置登录时启动、隐藏图标或退出。隐藏图标后，重新打开 Cmd Tab Pro 即可恢复。

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

## 打包与下载

生成可上传到 GitHub Releases 的 ZIP 和 SHA-256 校验文件：

    bash scripts/package-release.sh

产物位于 `.build/release/`，仅支持 Apple Silicon Mac。ZIP 使用 ad-hoc 签名且未经过 Apple notarization，因此从网络下载后首次打开可能被 Gatekeeper 阻止。用户可以在“系统设置 → 隐私与安全性”中选择仍要打开，然后再次确认。

GitHub Releases 可以直接托管这个 ZIP，其他人下载、解压并将 `Cmd Tab Pro.app` 移入 `/Applications` 后即可使用。发布时应同时上传 `.sha256` 文件，并在发布说明中写明系统版本、芯片要求和首次打开方式。

## 开源准备

项目不依赖第三方库，构建和安装流程都在仓库内。发布到公开仓库前还需要选择许可证；推荐 MIT，但不会在未经确认的情况下自动添加。

当前部署目标为 macOS 26.0，仅支持 Apple Silicon arm64。当前发布包采用 ad-hoc 签名，接受用户手动信任的 Gatekeeper 提示；如果以后需要双击即开，再增加 Developer ID 签名和 Apple notarization。

Bundle ID：`com.ares.cmd.tab`。
