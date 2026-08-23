<p align="center">
  <img src="Resources/AppIcon.png" width="116" alt="AI Quota icon">
</p>

<h1 align="center">AI Quota</h1>

<p align="center">
  把 Codex、Claude、OpenCode 和 DeepSeek 的剩余额度，收进一个安静的 macOS 菜单栏。
</p>

<p align="center">
  <img alt="Source 1.4.0" src="https://img.shields.io/badge/source-1.4.0-1769E8?style=flat-square">
  <img alt="Beta release" src="https://img.shields.io/badge/beta-1.3.0_beta_1-4A8BFF?style=flat-square">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-arm64-4A8BFF?style=flat-square">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-3DA639?style=flat-square">
</p>

<p align="center">
  <a href="README.en.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://github.com/FlyXingByte/ai-quota/releases/tag/v1.3.0-beta.1"><strong>下载 Beta</strong></a>
  &nbsp;·&nbsp;
  <a href="#第一次使用">第一次使用</a>
  &nbsp;·&nbsp;
  <a href="#隐私边界">隐私边界</a>
</p>

> **Current source · 1.4.0 Bilingual and Resilient**<br>
> 界面随系统语言在简体中文与英文间切换；读取失败保留上次读数并自动重试；预编译下载暂为 1.3.0 Beta 1。

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>一眼读完</h3>
      <p>菜单栏同一格上方显示 AI、下方显示额度；完整来源与重置时间留在面板。</p>
    </td>
    <td width="50%" valign="top">
      <h3>第一次就会用</h3>
      <p>首次启动自动打开向导，解释权限并完成 OpenCode、DeepSeek 配置。</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>Local-first</h3>
      <p>DeepSeek Key 直接写入 macOS 钥匙串；配置、日志和凭据不进入仓库。</p>
    </td>
    <td width="50%" valign="top">
      <h3>Calm Dashboard</h3>
      <p>正常状态统一蓝色；橙红只在低额度时出现，并自动适配系统主题。</p>
    </td>
  </tr>
</table>

<p align="center">
  <img src="docs/setup-preview.png" width="560" alt="AI Quota first-run setup">
</p>

<p align="center"><sub>首次运行先解释权限，再由用户选择数据源。</sub></p>

## 界面语言

界面跟随系统语言：App 内置**简体中文**与**English**，其他语言回落到英文，无需任何设置。

## 安装

1. 在 [v1.3.0-beta.1 Release](https://github.com/FlyXingByte/ai-quota/releases/tag/v1.3.0-beta.1) 下载：
   - `AI-Quota-1.3.0-beta.1-macOS-arm64.dmg`（推荐）
   - 或 `AI-Quota-1.3.0-beta.1-macOS-arm64.zip`
2. 打开 DMG，把 `AI Quota.app` 拖到 `Applications`。
3. 从“应用程序”打开 AI Quota，按首次配置向导完成设置。

> 这是 Apple Silicon Beta 构建，要求 macOS 14+。当前使用严格可验证的 ad-hoc 签名，但尚未经过 Apple 公证。

## 第一次使用

AI Quota **不会在启动瞬间读取钥匙串**。它会先打开配置向导，说明每个来源需要什么；只有点击
“保存并开始读取”后，才会访问已启用来源。

| 来源 | 开箱条件 | 首次设置 |
|---|---|---|
| **Codex** | 已安装并登录 `codex` CLI | 零配置，保持启用即可 |
| **Claude** | 已安装并登录 Claude Code | 零配置；开始读取时授权 `Claude Code-credentials` |
| **OpenCode** | Chrome 已登录 `opencode.ai` | 直接粘贴完整工作区 URL，App 自动提取 `wrk_…` |
| **DeepSeek** | 一个可用的 API Key | 在向导的 SecureField 中输入，直接保存到钥匙串 |

### 可能出现的钥匙串提示

根据启用来源，首次读取最多会出现：

- `Chrome Safe Storage`：仅 OpenCode 需要；
- `Claude Code-credentials`：仅 Claude 需要；
- `AI Quota DeepSeek API Key`：仅 DeepSeek 需要。

请核对名称后再允许。关闭某个来源，就不会读取它需要的凭据。

### OpenCode 工作区 ID 在哪里

打开 OpenCode 工作区页面，地址类似：

```text
https://opencode.ai/workspace/wrk_xxxxx/go
```

配置向导支持直接粘贴整条 URL，无需手动截取。

## 四个平台，一张面板

| 来源 | 面板内容 | 读取方式 |
|---|---|---|
| **Codex** | 5 小时、每周与模型分桶 | 本地 `codex app-server`，不读取 Token |
| **Claude** | 5 小时、每周与额外用量 | 只读 Claude Code 钥匙串凭据，不刷新令牌 |
| **OpenCode** | 滚动窗口、周/月额度、Zen 余额 | 复用 Chrome 的 `opencode.ai` 登录会话 |
| **DeepSeek** | CNY / USD 余额 | 官方 `/user/balance` API + App 专用钥匙串条目 |

所有百分比统一表示 **剩余量**：条越长，当前余量越充足。

## 菜单栏模式

在面板右下角选择 **「⋯ → 菜单栏显示」**，修改会立即生效。

| 模式 | 示例 | 适合 |
|---|---|---|
| Codex 每周 | `Cx 56%` | 默认，只盯主要周额度 |
| Claude 每周 | `Cl 87%` | Claude Code 主力用户 |
| OpenCode 每周 | `OC 48%` | OpenCode Go 主力用户 |
| DeepSeek 余额 | `DS ¥45` | 只关心 API 余额 |
| 剩余最少 | 自动切换来源 | 只想知道当前最紧张的额度 |

状态栏固定采用两行单指标样式，例如上方 `AI`、下方 `56%`，不再提供会占用多个位置的“全部并排”模式。

这个菜单只列出真正启用的来源；如果在设置里关掉了菜单栏当前指向的来源，它会自动改选一个仍在报数的来源。

## 后续修改设置

使用 **「⋯ → 数据源设置…」** 即可重新选择来源、更新 OpenCode URL 或覆盖 DeepSeek Key。

高级配置文件仍位于：

```text
~/Library/Application Support/AIQuota/config.json
```

文件权限会被保存为 `0600`。DeepSeek Key 从不写入该文件。

## 读取失败时

某个来源读取失败时不会清空卡片：错误显示在上一次成功读到的数字**旁边**，并标注这是沿用的读数，
菜单栏把该数字降为次要色而不是掉回 `!`。失败后 60 秒、180 秒各补一次重试；睡眠唤醒和网络恢复时也会主动刷新。

## 隐私边界

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>留在本机</h3>
      <p>配置、刷新日志、临时 Cookie 数据库副本和钥匙串凭据。</p>
    </td>
    <td width="50%" valign="top">
      <h3>不会进入 Git</h3>
      <p>API Key、OAuth Token、Cookie、Workspace 配置、真实邮箱和签名私钥。</p>
    </td>
  </tr>
</table>

- Codex 只调用本地 CLI 的只读额度接口。
- Claude Token 只用于额度查询，不刷新、不写回。
- OpenCode 正常请求使用临时 URLSession，并禁止自动重定向。
- DeepSeek Key 使用 App 专用钥匙串条目，不依赖 shell 环境变量。
- `config.json`、`.env`、证书和私钥文件均被 `.gitignore` 排除。
- 图标源文件已清理 C2PA/JUMBF 等可选生成元数据，像素内容保持一致。

## 从源码安装

```bash
gh repo clone FlyXingByte/ai-quota
cd ai-quota
./make-signing-cert.sh   # 只需一次：生成本地签名身份
./install.sh
```

构建需要 Apple Silicon Mac、macOS 14+ 和 Command Line Tools。

`make-signing-cert.sh` 会在登录钥匙串里生成一张自签名证书，它比看上去重要：macOS 把 TCC 和钥匙串授权
记在 App 的**指定要求**上，而 ad-hoc 签名没有身份，指定要求会退化成每次重编译都变的 cdhash——
于是每装一次就把之前授过的权限悄悄作废。有了这张证书，指定要求变成
`identifier "com.flyx.aiquota" and certificate root = H"…"`，跨构建稳定。证书**不需要**装成受信任根，
codesign 并不要求链信任。没有它时构建会回退到 ad-hoc，并明确提示这一点。

## 生成 Release 资产

```bash
./scripts/create-release.sh 1.3.0-beta.1
./scripts/verify-release.sh 1.3.0-beta.1
```

输出包括 ZIP、DMG 和 SHA-256 文件。

<details>
<summary><strong>常用诊断命令</strong></summary>

```bash
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --probe
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --identity
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --config
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --self-test
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --snapshot-setup
```

</details>

<details>
<summary><strong>新增或修改界面文案</strong></summary>

所有面向用户的文案都经过 `L("some.key")`，并且必须同时定义在
`Resources/en.lproj/Localizable.strings` 和 `Resources/zh-Hans.lproj/Localizable.strings` 里。
`scripts/check-localization.sh`（`build.sh` 和 CI 都会跑）会在键缺失、或者表里有代码不再使用的键时让构建失败。

诊断输出（`--probe`、`--dump`、`last-refresh.log`、`last-launch.log`）刻意只用英文：它们是贴进 issue 的东西。

</details>

<details>
<summary><strong>实现细节：Chrome Cookie</strong></summary>

OpenCode 没有公开额度 API，因此 AI Quota 会复制 Chrome Cookie SQLite 数据库，仅查询匹配
`opencode.ai` 的条目，在临时 Session 中请求页面并解析 SSR hydration 数据。数据库副本在读取结束后删除。

实现位于 [`Sources/ChromeCookies.swift`](Sources/ChromeCookies.swift) 与
[`Sources/OpenCodeProvider.swift`](Sources/OpenCodeProvider.swift)。

</details>

## 已知边界

- 仅支持 Chrome，不支持 Canary、Edge 或 Brave。
- OpenCode 页面结构变化后可能需要更新解析器。
- Claude 使用 Claude Code 当前登录状态；令牌过期时由 Claude Code 自己刷新。
- DeepSeek 仅提供余额，不提供网页控制台中的详细 Token 曲线。
- Beta 构建未经过 Apple 公证；大规模分发前应使用 Developer ID 并完成 notarization。
- Fork 若要以自己的产品名发布，应修改 `com.flyx.aiquota` Bundle ID。

## License

[MIT](LICENSE) © 2026 FlyXingByte

## 开源与贡献

- 贡献流程：[CONTRIBUTING.md](CONTRIBUTING.md)
- 安全问题：[SECURITY.md](SECURITY.md)
- Fork 发布自己的版本前，请更换 `com.flyx.aiquota` Bundle ID 与产品标识。

---

<p align="center">Built for a quieter menu bar.</p>
