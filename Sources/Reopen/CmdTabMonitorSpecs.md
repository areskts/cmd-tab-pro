# Cmd+Tab 会话

- 事件 tap 使用 listenOnly，不拦截原生 Cmd+Tab。
- Command 按住期间使用 Tab，释放 Command 时完成一次切换。
- 新一次 Cmd+Tab 开始时取消上一次尚未执行的恢复；同一会话内重复 Tab 继续选择。
- 松开 Command 后等待原生切换完成，再读取前台 App；等待期间不绑定旧 App，窗口查询开始后才绑定目标并防止失焦抢回。
- 重复 modifier 事件不得重复完成会话。
- 会话内反向选择键和左右方向键保留切换意图。
- Escape、Cmd+W 等其他按键、鼠标按下和 tap 被禁用时取消会话及旧恢复请求。
- 不保存按键输入。输入监控未授权时自动回到兼容模式，后台启动不反复弹授权请求。
- 暂停后移除 tap；重新启用时按当前模式恢复。

验证：`Tests/Windows/WindowPolicyTests.swift` 的键盘会话检查、`Tests/Windows/integration.sh --reopen-only` 的激活时序检查，以及原生快捷键人工验收。
