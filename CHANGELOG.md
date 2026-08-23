# Changelog

## 1.3.3 — Stacked Compact Widget

- 改成 Stats 风格的两行状态项：上方固定 `AI`，下方显示 `56%` 或 `¥45`。
- 保持无图标、无 Provider 标签，并继续只占一个菜单栏位置。
- 顶部使用 8.5pt 小字，额度使用 13pt 等宽常规体。
- 使用 Auto Layout 的视觉顶部锚点，确保 `AI` 永远位于额度上方。
- `AI` 与额度共用 2pt 左内边距，像 Stats 一样沿同一左边线对齐。
- 使用两个独立文本层绘制，避免 `NSStatusBarButton` 把第一行裁掉。
- 旧版配置自动迁移为已完成设置，升级后直接恢复额度数字。
- 启动日志增加文本行数与图标状态，便于验证两行布局。

## 1.3.1 — Compact Menu Bar

- 移除状态栏仪表盘图标和 Provider 标签，只显示一个等宽数字。
- 百分比使用大数字 + 小单位，例如 `56%`；余额自动去掉小数，例如 `¥45`。
- 移除“全部并排”模式；旧的 `all` 配置自动回落到 Codex 每周额度。
- 完整来源、窗口、重置时间继续保留在 Tooltip 与弹出面板。

## 1.3.0 Beta 1 — First-run Ready

- 首次启动先显示配置向导，不再立即触发多次钥匙串提示。
- Codex 与 Claude 保持登录后零配置。
- OpenCode 支持粘贴完整工作区 URL 并自动提取 `wrk_…`。
- DeepSeek API Key 通过 SecureField 写入 App 专用钥匙串条目。
- 移除菜单栏 App 无法可靠继承的 shell 环境变量兜底。
- 新用户默认只启用 Codex、Claude；OpenCode、DeepSeek 按需开启。
- 配置文件强制使用 `0600` 权限。
- 新增 MIT License、ZIP/DMG/SHA-256 Release 工具链。
- 清理图标源文件中的可选 C2PA/JUMBF 元数据，保持像素不变。

## 1.2.0 — Calm Dashboard

- 统一动态品牌蓝，橙红仅用于低额度告警。
- Provider 改为轻量卡片，并加入 `Cx / Cl / OC / DS` 徽标。
- 扩大关键数字、进度条和可点击区域。
- 余额改为独立数字胶囊，长提示支持自然换行。
- 菜单栏正常状态改为系统中性色，减少持续视觉干扰。
- 增强颜色之外的警告图标和辅助功能标签。
- 构建只使用 macOS 认可的有效签名身份，否则回退至严格可验证的 ad-hoc。

## 1.1.0

- 新增 Claude、OpenCode 和 DeepSeek 配额汇总。
- 支持选择菜单栏主显示来源与全部并排模式。
- 增加配置热重载、登录项与诊断命令。
