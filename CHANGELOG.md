# Changelog

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
