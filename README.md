# AI Quota

macOS 菜单栏 App，一眼看完 Codex / OpenCode / DeepSeek 三家的配额。

菜单栏常驻显示「剩余最少的那个额度还剩百分之几」，点开是完整面板。数据每 10 分钟自动刷新一次（可调），
打开面板时也会立即刷一次。

**所有百分比都是剩余量，不是已用量**——进度条随着消耗往回缩，绿→橙（剩 25% 以下）→红（剩 10% 以下）。
上游三家给的都是「已用」，转换在展示层做（`QuotaWindow.remainingPercent`），provider 里存的仍是 API 原值。

## 三个数据源怎么取的

| 来源 | 取数方式 | 需要什么 |
|---|---|---|
| **Codex** | 本地 `codex app-server` 的 JSON-RPC：`initialize` → `account/rateLimits/read` | 已登录的 codex CLI。App 不经手任何 token |
| **OpenCode** | 复用 Chrome 会话抓 `opencode.ai/workspace/<id>/go` 与 `/billing`，解析 SolidStart 的 SSR hydration 负载 | Chrome 里保持登录 + 钥匙串授权 |
| **DeepSeek** | 官方 `GET api.deepseek.com/user/balance` | 钥匙串里的 API key |

三条路径都是刻意选的：

- **Codex 走本地 app-server**，而不是拿 `~/.codex/auth.json` 里的 access token 去打
  `chatgpt.com/backend-api`。CLI 自己会处理续期和账号切换，我们只读结果。
- **OpenCode 只能走网页会话**。它没有余额/用量 API（[anomalyco/opencode#10448](https://github.com/anomalyco/opencode/issues/10448)
  提过但没实现），`/zen/v1/balance` 是 404。SolidStart 的服务端函数 ID 每次部署都会变，
  所以解析 SSR 负载比调 `/_server` 稳。
- **DeepSeek 不走网页**。`platform.deepseek.com` 的 API 用 `Authorization: Bearer`，
  token 存在 localStorage（Chrome 的 LevelDB 里），既难读又会过期；官方余额接口稳定得多。
  代价是拿不到 token 用量曲线——那个还是得看网页控制台，面板里的链接可以直接跳。

## Chrome cookie 是怎么读的

macOS 上 Chrome 的 cookie 用 AES-128-CBC 加密，密钥是钥匙串条目
`Chrome Safe Storage` 的密码经 PBKDF2-HMAC-SHA1（salt `saltysalt`，1003 轮，16 字节）派生，
IV 是 16 个空格。Chrome 130 以后明文前面还会多 32 字节的 `sha256(host_key)` 前缀。

实现见 [`Sources/ChromeCookies.swift`](Sources/ChromeCookies.swift)。要点：

- 读的是 cookie 库的**副本**（连 `-wal` / `-shm` 一起复制），Chrome 开着也不会冲突。
- 只读 `host_key LIKE '%opencode.ai'`，不碰其它站点。
- 首次运行 macOS 会弹一次钥匙串授权框，点「始终允许」之后就不再打扰。

> 重新编译会改变二进制签名，钥匙串授权可能需要重新点一次。

## 签名与系统权限

`build.sh` 用登录钥匙串里的自签名证书 `AI Quota Local Signing` 签名，没有就跑
`./make-signing-cert.sh` 生成一次（**不需要**装信任根，codesign 不要求）。

这不是为了过 Gatekeeper，是为了 TCC。系统设置 → 隐私与安全性的授权是按 App 的
**指定要求（designated requirement）**记的，两种签名差别很大：

| 签名方式 | 指定要求 | 后果 |
|---|---|---|
| ad-hoc (`--sign -`) | `cdhash H"5eac…"` | cdhash 每次重编译都变，授权随之作废 |
| 自签名证书 | `identifier "com.local.aiquota" and certificate root = H"2175…"` | 跨构建稳定 |

> **调试时别从 shell 直接 exec 这个二进制。** macOS 把权限记在 *responsible
> process* 上：经 LaunchServices 启动（`open` / 访达 / 聚焦）的 App 责任进程是它
> 自己；而从 shell 直接 exec 出来的进程**继承父进程的责任进程**。所以在终端里跑
> `.../AIQuota --probe` 触发的授权会被记到终端（或 `claude`）名下，权限列表里就
> 看不到「AI Quota」这一条。要让它以自己的名义申请权限，就走 `open -a "AI Quota"`。

## 用法

```bash
./install.sh
```

编译 → 装到 `/Applications/AI Quota.app` → 启动。菜单栏右上角出现仪表盘图标。

命令行自检（不启动 GUI）：

```bash
"/Applications/AI Quota.app/Contents/MacOS/AIQuota" --probe
```

注意这条会把触发的系统授权记到调用它的终端名下，见上面「签名与系统权限」。
只想确认 App 本身能不能拿到权限，就用 `open -a "AI Quota"` 看菜单栏。

其它参数：`--snapshot`（把面板渲染成图片）、`--dump opencode|billing|codex`（抓原始响应排查）、
`--config`（打印配置）、`--help`。

## 配置

`~/Library/Application Support/AIQuota/config.json`，也可以在 App 的「设置」里改：

```json
{
  "opencodeWorkspaceID": "wrk_…",
  "refreshMinutes": 10,
  "deepseekKeychainService": "DeepSeek API Key",
  "deepseekKeychainAccount": "codex",
  "showCodex": true,
  "showOpenCode": true,
  "showDeepSeek": true
}
```

DeepSeek 的 key 默认从钥匙串取（复用 codex 那份），也可以改用环境变量 `DEEPSEEK_API_KEY`。

「开机自动启动」在设置面板里勾选，走 `SMAppService`。

## 加一个新来源

实现 `QuotaProvider`（`id` / `name` / `fetch() async -> ProviderCard`），
在 `Config.providers` 里加一行即可。一个 `ProviderCard` 装若干 `QuotaWindow`，
`usedPercent` 填 API 给的**已用**百分比（展示层自己换算成剩余），只有 `value` 的就当成余额那样右对齐显示。

## 菜单栏图标看不见怎么办

菜单栏塞满时，macOS 会把新的状态项推到**刘海底下**——AppKit 认为它「可见」，但你点不到。

App 每次启动都会把图标的实际位置写进
`~/Library/Application Support/AIQuota/last-launch.log`：

```
按钮窗口 frame = {{801, 1084}, {51, 33}}
刘海左侧可用区 = {{0, 1085}, {771, 32}}
刘海右侧可用区 = {{956, 1085}, {772, 32}}
能否点到 = false
```

按钮 x 落在两个可用区之间（771–956）就是被刘海挡住了。这时候：

- **双击 `/Applications/AI Quota.app`** 会直接弹出面板窗口（`applicationShouldHandleReopen`
  检测到图标点不到，自动改用窗口而不是气泡）。面板里有「设置」和「退出」。
- 想让图标回到菜单栏上，得腾出空间：`System Settings → Control Center` 把用不上的项设成
  「不在菜单栏中显示」，或者按住 <kbd>⌘</kbd> 把图标拖出菜单栏。少两三个就够了。

## 已知边界

- 只支持 Chrome（不是 Chrome Canary / Edge / Brave）。多 profile 会自动挑 cookie 最多的那个。
- OpenCode 依赖页面结构；改版了 `--dump opencode` 能直接看到原始负载，解析器在
  `Payload`（`Sources/OpenCodeProvider.swift`），已经处理了 seroval 的反向引用和重复 key。
- DeepSeek 只有余额，没有 token 用量曲线。
