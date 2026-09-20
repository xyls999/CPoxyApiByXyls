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
├── config/
│   └── channel.example.json   # new-api 渠道配置模板
├── docs/
│   ├── architecture.md        # 架构与请求链路
│   ├── deployment.md          # 从零部署手册（构建 + 初始化 + 配置）
│   └── api-paradigms.md       # Coding API 调用范式（SDK/GUI/命令行）
└── scripts/
    ├── start-all.ps1          # 一键启动（上游 + 网关）
    ├── stop-all.ps1           # 一键停止
    └── test-api.ps1           # 端到端连通性自检
```

---

## 快速开始

### 0. 前置条件

- Windows 10/11，PowerShell 5.1+（系统自带）
- 已就绪两个组件（获取方式见 [docs/deployment.md](docs/deployment.md)）：
  - `new-api.exe`（new-api 网关，编译或 Release 下载）
  - `gemini-web2api-go`（上游，Release 下载单文件即可）

### 1. 配置路径

脚本通过环境变量定位组件，编辑后运行，或在运行前设置：

```powershell
$env:NEWAPI_DIR      = "E:\cpa\new-api"                          # new-api 所在目录（含 new-api.exe）
$env:GEMINI_API_DIR  = "E:\gemini-webapi-go\gemini-web2api-go"   # 上游所在目录（含 bin\gemini-web2api-go.exe）
```

不设置时使用上述同款默认值。

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
| Model | `gemini-3.6-flash`（首选）/ `gemini-3.5-flash-lite`（低延迟） |

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
    model="gemini-3.6-flash",
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
匿名模式：`gemini-3.6-flash`、`gemini-3.5-flash-lite`。`gemini-3.1-pro` 及 `-thinking` 变体需要在上游配置 Google 账号 Cookie。

---

## 致谢与许可

本仓库只包含**部署脚本、配置模板与文档**，不包含任何上游源码或二进制。

- [new-api](https://github.com/QuantumNous/new-api)（Apache-2.0）— QuantumNous
- [gemini-web2api-go](https://github.com/zexadev/gemini-web2api-go)（MIT）— zexadev

本项目文件以 [MIT](LICENSE) 发布。

## 免责声明

上游通过 Gemini Web 前端协议访问模型，非 Google 官方 API，可能受服务条款限制且接口随时变动；请自担风险，仅用于学习研究。
