# AI Quota

macOS 菜单栏 App，一眼看完 Codex / Claude / OpenCode / DeepSeek 四家的配额。

菜单栏常驻一行读数，点开是完整面板。数据每 10 分钟自动刷新一次（可调），打开面板时也会立即刷一次。

菜单栏显示哪个额度，在面板右下角 **「…」→「菜单栏显示」** 里切换，选完立刻生效并写回
`config.json` 的 `menuBarSource`：

| 取值 | 菜单栏 | 适合 |
|---|---|---|
| `codex-weekly`（默认） | `⏱ Cx 57%` — Codex 的账号周额度 | 只盯一个数，且菜单栏很挤 |
| `claude-weekly` | `⏱ Cl 88%` — Claude 订阅的每周额度 | 主力在 Claude Code |
| `opencode-weekly` | `⏱ OC 48%` — opencode Go 的周额度 | 主力在 opencode |
| `deepseek-balance` | `⏱ DS ¥48.39` — DeepSeek 余额 | 只关心还剩多少钱 |
| `tightest` | 剩得最少的那个，会在来源之间跳 | 只想知道「最紧的还剩多少」 |
| `all` | `⏱ Cx 57%  Cl 88%  OC 48%  DS ¥46` — 四家并排 | 一眼看全 |

前四个是**钉死**在某个具体窗口上的：读数不会随用量在来源之间跳。定位靠 provider 打的标记
（`codex.weekly` / `claude.weekly` / `opencode.weekly` / `deepseek.balance`），不匹配显示文本，上游改文案不会失效。
钉住的那个源取不到时，会临时用「剩余最少」顶上，并在 tooltip 里注明是代替品。

`all` 还有个副作用值得知道：状态项是**从右往左**排的，读数越长左边界越往左伸。菜单栏被挤到
刘海底下时，加宽反而能把可点区域拽回可见范围——见最后一节。

**所有百分比都是剩余量，不是已用量**——进度条随着消耗往回缩，绿→橙（剩 25% 以下）→红（剩 10% 以下）。
上游给的都是「已用」，转换在展示层做（`QuotaWindow.remainingPercent`），provider 里存的仍是 API 原值。

## 四个数据源怎么取的

| 来源 | 取数方式 | 需要什么 |
|---|---|---|
| **Codex** | 本地 `codex app-server` 的 JSON-RPC：`initialize` → `account/rateLimits/read` | 已登录的 codex CLI。App 不经手任何 token |
| **Claude** | 钥匙串取 OAuth 令牌，`GET api.anthropic.com/api/oauth/usage` | 已登录的 Claude Code + 钥匙串授权 |
| **OpenCode** | 复用 Chrome 会话抓 `opencode.ai/workspace/<id>/go` 与 `/billing`，解析 SolidStart 的 SSR hydration 负载 | Chrome 里保持登录 + 钥匙串授权 |
| **DeepSeek** | 官方 `GET api.deepseek.com/user/balance` | 钥匙串里的 API key |

四条路径都是刻意选的：

- **Codex 走本地 app-server**，而不是拿 `~/.codex/auth.json` 里的 access token 去打
  `chatgpt.com/backend-api`。CLI 自己会处理续期和账号切换，我们只读结果。
- **Claude 的令牌只读，绝不刷新**。凭证在钥匙串条目 `Claude Code-credentials` 里，
  Claude Code 自己管刷新周期；在这里刷新会把 refresh token 轮换掉，可能把 CLI 挤下线。
  所以令牌过期时是报错让你去终端跑一次 `claude`，而不是自作主张续期。
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
| 自签名证书 | `identifier "com.flyx.aiquota" and certificate root = H"2175…"` | 跨构建稳定 |

> 别用 `security find-identity -v` 去判断证书能不能用。没装信任根的自签名证书在那里
> 会被算成 `CSSMERR_TP_NOT_TRUSTED` 而过滤掉，但 codesign 照签不误，`--verify --strict`
> 也照过——它查的是签名完整性，不是证书链信任。按 `-v` 来判断的结果是每次构建都
> 悄悄退回 ad-hoc。`build.sh` 改成直接签、签失败再退回。

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

其它参数：`--snapshot`（把面板渲染成图片）、`--dump opencode|billing|codex|claude`（抓原始响应排查）、
`--config`（打印配置）、`--help`。

## 配置

没有设置面板，`~/Library/Application Support/AIQuota/config.json` 就是全部设置：

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

面板底部的「⋯」里有「打开配置文件…」，文件不存在时会先写一份默认值出来。**改完保存不用重启**：
每次刷新都会重读这个文件，改了 `refreshMinutes` 连定时器也会跟着重建。

同一个「⋯」菜单里还有「菜单栏显示」（切换主显示的额度来源）、「立即刷新」、
「开机自动启动」（走 `SMAppService`）和「退出」。

DeepSeek 的 key 默认从钥匙串取（复用 codex 那份），也可以改用环境变量 `DEEPSEEK_API_KEY`。

## 加一个新来源

实现 `QuotaProvider`（`id` / `name` / `fetch() async -> ProviderCard`），
在 `Config.providers` 里加一行即可。一个 `ProviderCard` 装若干 `QuotaWindow`，
`usedPercent` 填 API 给的**已用**百分比（展示层自己换算成剩余），只有 `value` 的就当成余额那样右对齐显示。

想让某个窗口能被选进菜单栏：给它一个稳定的 `key`（照 `codex.weekly` 的样子），
再往 `MenuBarSource` 加一个 case，`title` 写菜单里的名字、`pinned` 返回 `(cardID, windowKey)`。
菜单里的选项是 `MenuBarSource.allCases` 直接铺出来的，不用再改 UI。

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
  检测到图标点不到，自动改用窗口而不是气泡）。面板底部的「⋯」里有全部操作。
- **把 `menuBarSource` 设成 `all`**。读数变长 → 左边界往左伸 → 露出来的可点区域变多。
  判定阈值是「可见区里至少有 24pt」，不是「大部分可见」——半个身子在刘海底下照样点得到。
- 想让图标回到菜单栏上，得腾出空间：`System Settings → Control Center` 把用不上的项设成
  「不在菜单栏中显示」，或者按住 <kbd>⌘</kbd> 把图标拖出菜单栏。少两三个就够了。

## 已知边界

- 只支持 Chrome（不是 Chrome Canary / Edge / Brave）。多 profile 会自动挑 cookie 最多的那个。
- OpenCode 依赖页面结构；改版了 `--dump opencode` 能直接看到原始负载，解析器在
  `Payload`（`Sources/OpenCodeProvider.swift`），已经处理了 seroval 的反向引用和重复 key。
- DeepSeek 只有余额，没有 token 用量曲线。
- Claude 的 `seven_day_opus` / `seven_day_sonnet` 分桶在响应里存在但常为 `null`，
  有值时会自动多出两行。`utilization` 是 0–100 的百分比（**不是** 0–1 的小数）。
