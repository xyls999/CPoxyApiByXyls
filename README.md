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
| Gemini Web | 实际模型后端（gemini-3.6-flash / gemini-3.5-flash-lite） | - |

---

## 来源接入状态与调用

现有 Gemini 仍由 `new-api` 转发。另提供独立的学习通 OpenAI 协议适配器，启动方式：

```powershell
.\scripts\start-chaoxing.ps1 -ChaoxingDir 'C:\Black hacker\chaoxing-ai-web'
.\scripts\check-sources.ps1 -ChatgptConfigPath 'E:\chatgpt-web2api-trial\.runtime\config.json'
```

| 来源 | 本机服务 | new-api 渠道 | 可用条件 |
|---|---|---|---|
| Gemini Web | `127.0.0.1:8083` | `gemini-web2api-go` | 官方 v4.21.0，已验证两种 Flash 模型 |
| 4 Argon（实验） | `127.0.0.1:18083` | `gemini-4-argon-experimental`，模型 `gemini-4-argon` | [上游 PR #37](https://github.com/zexadev/gemini-web2api-go/pull/37) 指定提交的隔离构建；已核对实际上游模型并通过网关普通/SSE 问答，未合并、可能失效 |
| 学习通课程 AI | `127.0.0.1:8787` → 协议适配 `127.0.0.1:8788` | `chaoxing-course-ai`，模型 `chaoxing-course-ai` | 本人正常登录课程、机器人就绪、真实问答成功后才启用 |
| ChatGPT Web | ChatGPT-Web2API `127.0.0.1:18080` | `chatgpt-web-browser`，模型 `chatgpt-web-auto` 映射 `auto` | 独立浏览器已登录且真实问答成功后才启用；不要复用 Codex Full 模式 |

当前实例的首页使用 [config/home-page.md](config/home-page.md) 作为 `HomePageContent`，展示各来源的**人工验收快照**（不是持续在线监测），可在管理台系统设置中更新。未通过真实问答验收的来源须保留**禁用状态**。本机现已用官方校验和验证的 Gemini v4.21.0，通过 new-api 完成 `gemini-3.5-flash-lite` 的普通和 SSE 问答（均回答 OK）；`gemini-3.6-flash` 也已通过 new-api 真实问答。Gemini 与隔离的 Argon 实验渠道启用，学习通和 ChatGPT Web 仍禁用。仅监听、健康检查或模型列表返回 200 都不等于问答成功。学习通适配器只支持文本聊天：每次请求建立并释放一个独立上游会话；多轮 `messages` 会合并为有角色标记的文本，而不是原生学习通会话续聊。它等待完整答案后才输出 SSE，并非真实逐 token 流式输出。仅监听回环地址，密钥保存在被 Git 忽略的 `.runtime/chaoxing-keys.json`，禁止上传 `.runtime/`、日志、浏览器资料目录或真实调用凭据。

在 `E:\cpa\new-api` 这一已有配置的网关实例中启动时要显式指定目录，避免切换到 `bin\new-api` 里未初始化的另一份数据库：

```powershell
.\scripts\start-all.ps1 -NewApiDir 'E:\cpa\new-api' -GeminiProxy 'http://127.0.0.1:7897'
```

实验渠道的源码、编译器、配置和账号库保存在被 Git 忽略且仅本机用户可访问的 `.runtime/argon-trial/`；`auto-start.enabled` 标记存在时 `start-all.ps1` 会先验证/启动本机 `18083`，再启动网关。该二进制是**未合并 PR 的实验构建**，不是官方正式发行版；若缺少本机私有文件，启动会拒绝将未知服务冒充实验上游。不要上传 `.runtime/` 或公开浏览器登录态。

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
| Model | `gemini-3.5-flash-lite` / `gemini-3.6-flash` / `gemini-4-argon`（最后一个为实验渠道） |

当前仅开放真实 Gemini 名称。配置模板中原有的 `gpt-*` 别名并非 GPT 模型，且尚未验证，已从当前实例的模型列表隐藏。新注册账号默认赠送 $1,000,000 额度（这是本机配置，不代表实际付费余额）。

**Codex CLI 专用**：把 [config/codex/cpoxy.config.toml](config/codex/cpoxy.config.toml) 复制为
`%USERPROFILE%\.codex\cpoxy.config.toml`，替换其中的 `<GATEWAY-HOST>` 和 `<GATEWAY-TOKEN>`
（密钥直接内联在 `experimental_bearer_token`，无需环境变量），然后 `codex --profile cpoxy` 启动：

```powershell
codex --profile cpoxy
```

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
gemini-web2api-go 默认每 IP 并发 5 / RPM 30 / RPH 80。频繁 429 时可在其管理台调高，或接入 Cookie 池 / 代理池（见其官方文档）。

**哪些模型可用？**
运行 `GET /v1/models` 查看当前开放模型。本机已验证 `gemini-3.5-flash-lite` 与 `gemini-3.6-flash` 的真实回答，并在独立实验渠道验证了 `gemini-4-argon` 的实际模型、普通与 SSE 问答；学习通和 ChatGPT Web 暂未开放。原模板中的 `gpt-*` 只是 Gemini 映射别名，并非真正的 GPT 模型，因此当前已隐藏。

---

## 致谢与许可

`bin/` 包含第三方上游可执行文件；Gemini Web 代理已替换为 [官方 v4.21.0 Windows x64 release](https://github.com/zexadev/gemini-web2api-go/releases/tag/v4.21.0)，下载时已对照同一 release 的 `SHA256SUMS.txt` 校验。上游源码不在本仓库；第三方程序分别遵循自身许可证。本项目自编写的桥接器、脚本和文档以 [MIT](LICENSE) 发布。

- [new-api](https://github.com/QuantumNous/new-api)（Apache-2.0）— QuantumNous
- [gemini-web2api-go](https://github.com/zexadev/gemini-web2api-go)（MIT）— zexadev

## 免责声明

上游通过 Gemini Web 前端协议访问模型，非 Google 官方 API，可能受服务条款限制且接口随时变动；请自担风险，仅用于学习研究。
