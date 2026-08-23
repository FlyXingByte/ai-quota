# Changelog

## 1.4.0 — Bilingual and Resilient

- 修复构建退回 ad-hoc 签名的回归：`find-identity -v` 会过滤掉未装信任根的自签名证书，
  于是每次重编译的指定要求都退化成 cdhash，已授过的钥匙串与 TCC 权限随之作废。
  改为直接签名、失败再退回，并恢复被一并删掉的 `make-signing-cert.sh`。
- 修复 Codex 读取可能永久卡死：`FileHandle.availableData` 是阻塞读，
  轮询它无法实现超时——app-server 起来后不说话也不退出时，刷新会永远停住，
  而刷新中标志位一直举着，后续所有定时与手动刷新都被入口的 guard 挡掉。
  改用可读性回调 + 带截止时间的信号量，并顺带排空 stderr（缓冲区写满同样会卡住子进程）。
- 每个数据源增加 90 秒兜底超时，刷新中标志位改为 `defer` 清除。
- 修复 `Shell.run` 与 Chrome cookie 密钥缓存的数据竞争（Swift 6 语言模式下会直接报错）。
- Chrome Safe Storage 密码轮换后，密钥缓存会在解密全部失败时失效重取，
  不再整个进程生命周期内一直报「没找到 cookie」。
- 某个来源读取失败时保留上一次的数字并标记「沿用上次读数」，不再整张卡清空、
  菜单栏掉回 `!` 等满一个刷新周期；失败后 60 秒、180 秒各补一次重试。
- 睡眠唤醒和网络恢复时主动刷新；刷新定时器加 10% tolerance，减少无谓唤醒。
- 菜单栏来源选单只列出真正启用的来源；在设置里关掉当前选中的来源会自动改选可用项。
- 状态栏按内容测宽（32–68pt），余额类读数（如 `¥1234`）不再被静默裁掉。
- 额度行改用稳定身份，进度条在数值变化时真正产生动画而不是瞬间跳变。
- **界面改为中英双语**：文案全部走 `L("key")`，随系统语言在简体中文与英文间切换，
  其他语言回落英文；`scripts/check-localization.sh` 在构建和 CI 里校验两份字符串表。
  诊断输出与日志统一英文，方便贴 issue。备注是否需要提醒由 provider 显式标注，不再靠匹配中文词。
- 版本号只写在 `Sources/Config.swift`，`build.sh` 据此注入 Info.plist，自检改为校验二者一致。
- 新增 GitHub Actions CI：本地化检查、严格并发类型检查、构建自检、双语文案冒烟测试。
- 补上 README 英文版与语言切换；修正 README 里已经过时的签名说明，恢复 `make-signing-cert.sh` 的位置。
- 配额请求显式使用 `.reloadIgnoringLocalCacheData`，不从缓存取数。
- 删除死代码 `ProviderCard.headlineWindow` 与 `FeedbackTone.warning`。
- 新增 `scripts/notarize-release.sh`：Developer ID 签名 + Apple 公证 + 装订的完整发布流水线。
  `build.sh` 在使用 Developer ID 身份时自动加上 hardened runtime 与安全时间戳（缺任一都会被公证拒绝），
  并且不再对分发签名用 `--deep`。

## 1.3.2

未发布——版本号从 1.3.1 直接跳到 1.3.3，没有对应的构建。

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
