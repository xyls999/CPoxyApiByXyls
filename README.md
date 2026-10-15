# CPoxyApiByXyls

[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)](#)
[![Shell](https://img.shields.io/badge/shell-PowerShell%205.1-5391FE?logo=powershell&logoColor=white)](#)
[![API](https://img.shields.io/badge/API-OpenAI%20Compatible-412991)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

本地 AI **Coding API 网关**整合方案：以 [new-api](https://github.com/QuantumNous/new-api) 作为统一 API 网关，
[gemini-web2api-go](https://github.com/zexadev/gemini-web2api-go) 作为上游模型来源，
对外交付一套 **OpenAI 兼容** 的 Coding API，可直接接入 Cursor / OpenAI SDK / Cherry Studio / 各类 Agent 框架。

> 无需 Google API Key，无官方配额限制。上游走 Gemini Web 协议（Chrome 指纹模拟）。

---

## 架构

```
┌─────────────────────┐   OpenAI 协议    ┌──────────────────────┐  OpenAI 兼容   ┌─────────────────────┐
│   Coding 客户端      │ ───────────────▶ │  new-api 网关 :3000  │ ─────────────▶ │ gemini-web2api-go   │
│  Cursor / SDK / IDE │   /v1/chat/...   │  计费·令牌·渠道·日志   │  :8083         │ Gemini Web 协议代理  │
└─────────────────────┘                  └──────────────────────┘                └─────────────────────┘
                                                                                          │
                                                                                          ▼
                                                                                  Gemini Web (Google)
```

| 组件 | 角色 | 默认端口 |
|---|---|---|
| new-api | API 网关：令牌发放、渠道管理、请求转发、用量统计 | 3000 |
| gemini-web2api-go | 上游：把 Gemini Web 页面协议转成 OpenAI 兼容 API | 8083 |
| Gemini Web | 实际模型后端（当前仅开放 gemini-3.5-flash-lite） | - |

---

## 来源接入状态与调用

现有 Gemini 仍由 `new-api` 转发。另提供独立的学习通 OpenAI 协议适配器，启动方式：

```powershell
.\scripts\start-chaoxing.ps1 -ChaoxingDir 'C:\Black hacker\chaoxing-ai-web'
.\scripts\check-sources.ps1 -ChatgptConfigPath 'E:\chatgpt-web2api-trial\.runtime\config.json'
```

| 来源 | 本机服务 | new-api 渠道 | 可用条件 |
|---|---|---|---|
| Gemini Web | `127.0.0.1:8083` | `gemini-web2api-go`；当前开放 Flash-Lite | 官方 v4.21.0，Flash-Lite 已通过真实回答和 SSE；Flash 近期返回错误致歉，已暂停 |
| 4 Argon（实验） | `127.0.0.1:18083` | `gemini-4-argon-experimental`，当前开放 | [上游 PR #37](https://github.com/zexadev/gemini-web2api-go/pull/37) 隔离构建；重新登录后经网关普通/SSE 问答通过，实际上游为 4 Argon；仍可能随时失效 |
| 学习通课程 AI | `127.0.0.1:8787` → 协议适配 `127.0.0.1:8788` | `chaoxing-course-ai`，模型 `chaoxing-course-ai` | 按用户要求停止服务、保持渠道禁用 |
| ChatGPT Web | ChatGPT-Web2API `127.0.0.1:18080` | `chatgpt-web-browser`，模型 `chatgpt-web-active` 映射 `auto` | 网页当前模型动态变化（本次后端曾显示 `gpt-6-thinking`）；修复 DOM 漏检后经网关普通/SSE 问答通过，显式选模失败会拒绝发送；不等于 Codex 官方 API |
| Grok Web（实验） | grok2api `127.0.0.1:18084` | `grok-web-isolated`，`grok-web-fast` 映射 `grok-chat-fast` | 本机 SSO 与同出口代理就绪；普通/SSE 问答已通过；Chat Completions 工具往返第一版补丁单次通过，最终构建复验遇上游瞬断/未选工具，审计显示 `Web/grok-chat-fast`；网页登录态/额度/出口变化可能使服务失效 |

当前实例的首页使用 [config/home-page.html](config/home-page.html) 作为 `HomePageContent`，保留 [Markdown 回退文案](config/home-page.md)。页面展示各来源的**人工验收快照**（不是持续在线监测），并使用 new-api 原有登录、注册与令牌系统；可在管理台系统设置中更新。未通过真实问答验收的来源须保留**禁用状态**。本机现已用官方校验和验证的 Gemini v4.21.0，通过 new-api 完成 `gemini-3.5-flash-lite` 的普通和 SSE 问答（均回答 OK）；`gemini-3.6-flash` 曾通过真实问答，但近次返回错误致歉，现已禁用；Argon 换用本机新会话后经本网关普通及 SSE 问答复验通过并开放；ChatGPT Web 修复回答漏检并通过同样验收后开放；Grok Web 经本机网页登录及同出口代理接入后，隔离服务与网关的普通/SSE 真实问答通过并开放；学习通按用户要求停止服务且仍禁用。仅监听、健康检查或模型列表返回 200 都不等于问答成功。学习通适配器只支持文本聊天：每次请求建立并释放一个独立上游会话；多轮 `messages` 会合并为有角色标记的文本，而不是原生学习通会话续聊。它等待完整答案后才输出 SSE，并非真实逐 token 流式输出。仅监听回环地址，密钥保存在被 Git 忽略的 `.runtime/chaoxing-keys.json`，禁止上传 `.runtime/`、日志、浏览器资料目录或真实调用凭据。

桌面快捷方式 **CPoxy 快速启动** 会启动 Gemini、Argon、ChatGPT Web、Grok Web 和 new-api，学习通保持停止。它还会打开专用 Gemini Edge（本机 CDP `19447`），检测到 Google 登录态后自动将 Gemini 域 Cookie 导入 Argon Cookie 池。Cookie 只在本机处理，不写入聊天、Git 或普通日志。内网首页为 `http://10.113.5.51:3000/`，API 为 `http://10.113.5.51:3000/v1`。

在 `E:\cpa\new-api` 这一已有配置的网关实例中启动时要显式指定目录，避免切换到 `bin\new-api` 里未初始化的另一份数据库：

```powershell
.\scripts\start-all.ps1 -NewApiDir 'E:\cpa\new-api' -GeminiProxy 'http://127.0.0.1:7897'
```

实验渠道的源码、编译器、配置和账号库保存在被 Git 忽略且仅本机用户可访问的 `.runtime/argon-trial/`；`auto-start.enabled` 标记存在时 `start-all.ps1` 会先验证/启动本机 `18083`，再启动网关。该二进制是**未合并 PR 的实验构建**，不是官方正式发行版；若缺少本机私有文件，启动会拒绝将未知服务冒充实验上游。不要上传 `.runtime/` 或公开浏览器登录态。

Grok Web 仍是独立实验服务：私有源码、可执行文件、配置、加密账号库与本地浏览器资料位于 `.runtime/research/`、`.runtime/grok-trial/`，服务仅监听 `127.0.0.1:18084`。已为分片函数调用解析缺陷保存[可复现补丁](patches/grok2api-web-stream-tools.patch)，第一版补丁曾经正式网关完成一次 Chat Completions 的真实函数工具往返，但最终复审构建尚未再次通过；**Codex CLI 和 Responses 工具结果续答也尚未通过**，不能据此宣称它们可用。Grok 需要与网页登录相同的 `127.0.0.1:7897` 出口；网关重启前须先确保 Grok 服务按 [研究记录](docs/research/grok2api-evaluation.md#本机启动与登录) 启动。当前 Grok 客户端 Key 限制为共用 2 RPM / 1 并发；限流或登录态失效时不要盲目重复发送可能已到达上游的问题。不要上传 `.runtime/` 或公开浏览器登录态。

`-GeminiProxy` 仅在**启动** Gemini 服务时生效；服务已在 8083 监听时脚本不会更改代理。`start-chaoxing.ps1` 启动时对 `.runtime/` 限制文件访问权限；关闭时使用 `stop-chaoxing.ps1`，会先让适配器拒绝新请求、等待活跃请求清理完成，超时则拒绝强制停止。Gemini 上游不读取 `HTTPS_PROXY` 环境变量，可用 `-GeminiProxy` 显式设置；若无需代理则省略该选项。渠道模板见 `config/additional-channels.example.json`，接入前请在管理台用实际密钥替换占位符，并保持 `status=2`，直到端到端问答验收成功。

> ChatGPT-Web2API 是独立的第三方试验依赖，脚本不自动安装它、不读取/复制 ChatGPT 登录态，也不自动开放其渠道。学习通网页账号告警需要本人处理，不自动重试结果不确定的发送请求。

## 特性

- **开箱即用**：一键启动脚本 + 一键连通性自检脚本
- **统一入口**：所有 coding 工具只需填一个 Base URL + 一个 API Key
- **完整 OpenAI 兼容**：`/v1/chat/completions`（含流式 SSE）、`/v1/models`
- **令牌与计费**：多令牌发放、额度控制、用量日志、渠道自动禁用/恢复
- **多渠道扩展**：new-api 原生支持 40+ 上游，随时可挂第二个模型来源

## 目录结构

```
CPoxyApiByXyls/
├── README.md                  # 本文件
├── LICENSE
├── bin/
│   ├── new-api/new-api.exe.zip        # 网关本体（官方 Release 打包）
│   └── gemini-web2api-go/             # 反代本体（官方 Release 二进制）
├── config/
│   ├── codex/cpoxy.config.toml        # Codex CLI profile 模板
│   └── channel.example.json           # new-api 渠道配置模板
├── docs/
│   ├── architecture.md        # 架构与请求链路
│   ├── deployment.md          # 从零部署手册
│   └── api-paradigms.md       # Coding API 调用范式（SDK/GUI/命令行）
└── scripts/
    ├── setup.ps1              # 解压 + 配置 + Defender 排除（幂等，可重复执行）
    ├── start-all.ps1          # 一键启动（上游 + 网关）
    ├── stop-all.ps1           # 一键停止
    └── test-api.ps1           # 端到端连通性自检
```

---

## 快速开始

### 0. 前置条件

- Windows 10/11，PowerShell 5.1+（系统自带）
- 无需 Go / Node / Bun：网关与反代本体已随仓库附带（`bin/`）

### 1. 克隆 + 安装

```powershell
git clone https://github.com/xyls999/CPoxyApiByXyls
cd CPoxyApiByXyls
.\scripts\setup.ps1
```

`setup.ps1` 做四件事：解压网关 → 校验/补齐反代 → 写入上游配置（仅监听 127.0.0.1）→
尝试加 Defender 排除目录。全部幂等，已就绪的组件自动跳过；`bin/` 缺失时自动回退为
从上游官方 Release 下载（带 SHA256 校验）。

### 2. 启动

```powershell
.\scripts\start-all.ps1
```

首次启动按 [docs/deployment.md](docs/deployment.md) 第 3 步完成初始化（管理员账号 + 渠道 + 令牌）。

### 3. 自检

```powershell
$env:CODING_API_KEY = "sk-你的网关令牌"
.\scripts\test-api.ps1
```

输出 models 列表、非流式回复、流式 SSE 分片全部正常即打通。

### 4. 接入 Coding 工具

| 字段 | 值 |
|---|---|
| Base URL | `http://127.0.0.1:3000/v1` |
| API Key | new-api 管理台发放的 `sk-…` 令牌 |
| Model | 当前开放 `gemini-3.5-flash-lite`、实验性 `gemini-4-argon`、`chatgpt-web-active`（网页当前模型）、实验性 `grok-web-fast`；学习通已暂停 |

只开放已通过网关真实问答的模型标识。配置模板中原有的 `gpt-*` 别名并非 GPT 模型，且尚未验证，已从当前实例的模型列表隐藏。新注册账号默认赠送 **10 亿基准 token 等值**内部额度：按本项目基准价 $0.002/千 token、500000 quota/USD 折算为 `QuotaForNewUser=1000000000000`（显示为 $2,000,000 站内额度，非真实现金）。不同模型和输入/输出单价会改变实际可用 token 数，**不是跨模型固定 10 亿 token 硬上限**；该站内积分仅供本机可信内网测试，公开运营前须补 HTTPS 和防批量注册。

**Codex CLI 专用**：将 [config/codex/cpoxy.config.toml](config/codex/cpoxy.config.toml) 合并到 `%USERPROFILE%\.codex\config.toml`，替换 `<GATEWAY-HOST>`；仅在本机环境变量 `CPOXY_API_KEY` 设置自己的网关令牌，不在 TOML 里写令牌。模板默认用已通过 Codex CLI 0.157.1 Responses 真实问答的 `gemini-3.5-flash-lite`；`config/codex/gemini4.config.toml` 提供 `gemini4` profile，使用实验性 `gemini-4-argon` 和 `model_reasoning_effort="high"`。当前网关令牌已实测 Gemini 4 普通/SSE 及 Codex 两个基础任务通过（复杂工具调用未验收）。ChatGPT Web 当前只有聊天接口、无 `/v1/responses`，不能作为 Codex CLI provider；Grok Web 的 Responses 简单文本与首次工具调用可用，但默认 Codex CLI 的 `namespace` 工具被拒绝；在隔离配置关闭 `features.multi_agent` 后，Windows `read-only` 沙箱又拒绝执行收到的命令，因此**不能当作可用的 Codex provider**。Grok 曾单次通过的 agent 范式是 [Chat Completions 函数工具往返](docs/api-paradigms.md#grok-web-agent实际验收的函数工具往返)，当前最终构建仍需稳定性复验，不是 Codex CLI。若希望不覆盖官方默认模型，将模板顶部两行放到 `[profiles.cpoxy]`，再运行 `codex --profile cpoxy`。分来源的接口状态见 [docs/api-paradigms.md](docs/api-paradigms.md)。

---

## 调用范式（速查）

Python（OpenAI SDK 原生兼容）：

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:3000/v1",
    api_key="sk-你的网关令牌",
)
resp = client.chat.completions.create(
    model="gemini-3.5-flash-lite",
    messages=[{"role": "user", "content": "解释这段代码"}],
)
print(resp.choices[0].message.content)
```

更多范式（GUI 工具、命令行、流式消费）见 [docs/api-paradigms.md](docs/api-paradigms.md)。

---

## 常见问题

**PowerShell 调用返回 invalid JSON / 空响应？**
PowerShell 的 `curl` 是 `Invoke-WebRequest` 别名，会破坏 JSON 引号转义。使用本仓库 `scripts/test-api.ps1`（基于 `Invoke-RestMethod`），或命令行统一用 `curl.exe`。

**杀毒软件 / Windows 安全拦截？**
两个组件均为未签名可执行文件。将组件目录加入 Defender 排除列表：
`Add-MpPreference -ExclusionPath "<目录>"`。

**上游限流？**
实验 Argon 上游配置了每出口并发 5 / RPM 30 / RPH 80。但 `ip_slot_full` 不一定表示计数真的打满：本次在计数未满时账号失效仍返回 429。先看管理端账号、出口及 `/admin/api/usage`，不要盲目重试或调高限额。

**哪些模型可用？**
运行 `GET /v1/models` 仅能查看配置，不能替代真实问答验收。当前开放 `gemini-3.5-flash-lite`、复验通过的实验性 `gemini-4-argon` 、`chatgpt-web-active`（网页当前模型，非固定版本）及实验性 `grok-web-fast`；Flash 已暂停，学习通已停止且仍禁用。原模板中的 `gpt-*` 只是 Gemini 映射别名，并非真正的 GPT 模型，当前已隐藏。

---

## 致谢与许可

`bin/` 包含第三方上游可执行文件；Gemini Web 代理已替换为 [官方 v4.21.0 Windows x64 release](https://github.com/zexadev/gemini-web2api-go/releases/tag/v4.21.0)，下载时已对照同一 release 的 `SHA256SUMS.txt` 校验。上游源码不在本仓库；第三方程序分别遵循自身许可证。本项目自编写的桥接器、脚本和文档以 [MIT](LICENSE) 发布。

- [new-api](https://github.com/QuantumNous/new-api)（Apache-2.0）— QuantumNous
- [gemini-web2api-go](https://github.com/zexadev/gemini-web2api-go)（MIT）— zexadev

## 免责声明

上游通过 Gemini Web 前端协议访问模型，非 Google 官方 API，可能受服务条款限制且接口随时变动；请自担风险，仅用于学习研究。
