<p align="center">
  <img src="Resources/AppIcon.png" width="116" alt="AI Quota icon">
</p>

<h1 align="center">AI Quota</h1>

<p align="center">
  把 Codex、Claude、OpenCode 和 DeepSeek 的剩余额度，收进一个安静的 macOS 菜单栏。
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-arm64-1769E8?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-native-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Local first" src="https://img.shields.io/badge/data-local--first-4A8BFF?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/FlyXingByte/ai-quota/releases/latest"><strong>下载最新版本</strong></a>
  &nbsp;·&nbsp;
  <a href="#从源码安装">从源码安装</a>
  &nbsp;·&nbsp;
  <a href="#隐私边界">隐私边界</a>
</p>

> **1.2.0 · Calm Dashboard**<br>
> 统一品牌蓝、轻量卡片、动态深浅色，以及更安静的菜单栏状态表达。

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>01 · 一眼读完</h3>
      <p>菜单栏直接显示最关心的周额度、余额，或四个平台并排状态。</p>
    </td>
    <td width="50%" valign="top">
      <h3>02 · Calm Dashboard</h3>
      <p>正常状态统一蓝色；橙色与红色只在真的需要注意时出现。</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>03 · Local-first</h3>
      <p>配置与日志留在本机；凭据从 macOS 钥匙串读取，不进入仓库。</p>
    </td>
    <td width="50%" valign="top">
      <h3>04 · Native Swift</h3>
      <p>SwiftUI + AppKit 原生实现，无第三方运行时依赖，自动跟随系统主题。</p>
    </td>
  </tr>
</table>

## 四个平台，一张面板

| 来源 | 面板内容 | 读取方式 |
|---|---|---|
| **Codex** | 5 小时、每周与模型分桶 | 本地 `codex app-server`，不读取 Token |
| **Claude** | 5 小时、每周与额外用量 | 只读 Claude Code 钥匙串凭据，不刷新令牌 |
| **OpenCode** | 滚动窗口、周/月额度、Zen 余额 | 复用 Chrome 的 `opencode.ai` 登录会话 |
| **DeepSeek** | CNY / USD 余额 | 官方 `/user/balance` API + 钥匙串 Key |

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
| 全部并排 | `Cx 56% Cl 87% OC 48% DS ¥45` | 菜单栏空间充足 |

## 安装

### 下载 Release

1. 在 [Releases](https://github.com/FlyXingByte/ai-quota/releases/latest) 下载 `AI-Quota-1.2.0-macOS-arm64.zip`。
2. 解压，将 `AI Quota.app` 放入 `/Applications`。
3. 首次打开后，根据 macOS 提示授予必要的钥匙串访问权限。

> 当前 Release 是私人本地构建，使用可验证的 ad-hoc 签名，但未经过 Apple 公证。

### 从源码安装

```bash
gh repo clone FlyXingByte/ai-quota
cd ai-quota
./install.sh
```

要求：Apple Silicon Mac、macOS 14 或更高版本，以及 Command Line Tools。

## 配置

配置文件位于：

```text
~/Library/Application Support/AIQuota/config.json
```

面板右下角的 **「⋯ → 打开配置文件…」** 可以直接打开。保存后无需重启，下次刷新自动生效。

```json
{
  "opencodeWorkspaceID": "wrk_…",
  "menuBarSource": "codex-weekly",
  "refreshMinutes": 10,
  "deepseekKeychainService": "DeepSeek API Key",
  "deepseekKeychainAccount": "codex",
  "showCodex": true,
  "showClaude": true,
  "showOpenCode": true,
  "showDeepSeek": true
}
```

## 隐私边界

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>留在本机</h3>
      <p>配置、刷新日志、Chrome Cookie 数据库副本和临时诊断文件。</p>
    </td>
    <td width="50%" valign="top">
      <h3>不会进入 Git</h3>
      <p>API Key、OAuth Token、Cookie、Workspace 配置和本机签名材料。</p>
    </td>
  </tr>
</table>

- Codex 只调用本地 CLI 的只读额度接口。
- Claude 的 OAuth Token 只用于查询额度，不刷新、不写回。
- OpenCode 正常请求使用临时 URLSession，并禁止自动重定向。
- DeepSeek Key 从钥匙串读取，只发送到官方余额接口。
- `config.json`、`.env`、证书和私钥文件都已被 `.gitignore` 排除。

## 常用命令

```bash
# 文本自检
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --probe

# 查看 App 身份、图标和登录项状态
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --identity

# 打印配置路径与当前设置
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --config
```

<details>
<summary><strong>实现细节：Chrome Cookie</strong></summary>

OpenCode 没有公开额度 API，因此 AI Quota 会：

1. 复制 Chrome `Cookies` SQLite 数据库及 WAL/SHM；
2. 从 macOS 钥匙串读取 `Chrome Safe Storage`；
3. 仅查询匹配 `opencode.ai` 的 Cookie；
4. 用临时 Session 请求 OpenCode 页面并解析 SSR hydration 数据；
5. 刷新结束后删除数据库副本。

实现位于 [`Sources/ChromeCookies.swift`](Sources/ChromeCookies.swift) 与
[`Sources/OpenCodeProvider.swift`](Sources/OpenCodeProvider.swift)。

</details>

<details>
<summary><strong>实现细节：增加 Provider</strong></summary>

实现 `QuotaProvider`，并在 `Config.providers` 中加入实例即可。每个 `ProviderCard` 可以包含多个
`QuotaWindow`。要让某个窗口可被固定到菜单栏，为它提供稳定 `key`，再在 `MenuBarSource` 增加对应项。

</details>

## 已知边界

- 仅支持 Chrome，不支持 Canary、Edge 或 Brave。
- OpenCode 页面结构变化后可能需要更新解析器。
- Claude 使用 Claude Code 当前的本机登录状态；令牌过期时需由 Claude Code 自己刷新。
- DeepSeek 仅提供余额，不提供网页控制台中的详细 Token 曲线。
- App 是本地私人工具，目前没有 Apple 公证或公开分发承诺。

---

<p align="center">
  Built for a quieter menu bar.
</p>
