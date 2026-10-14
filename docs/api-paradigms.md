# Coding API 调用范式

网关提供 OpenAI 兼容的聊天接口；Responses 及流式能力须按具体模型验收，不等同支持所有 OpenAI 端点。当前示例只使用仍开放且经过真实问答的 Flash-Lite：

```
BASE_URL = http://127.0.0.1:3000/v1
API_KEY  = <仅存放在本机的 new-api 网关令牌>
MODEL    = gemini-3.5-flash-lite
```

历史 `gpt-5.6` / `gpt-6` / `gpt-5.6-mini` 是 Gemini 别名，**不是真正的 GPT 模型且已禁用**，不要用作 Codex 默认模型。新注册账号赠送 `QuotaForNewUser=1000000000000` 内部额度，按既定基准价折算为 **10 亿基准 token 等值**，并非现金或跨模型固定 token 数。

## 1. Python / OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:3000/v1", api_key="sk-…")

# 非流式
resp = client.chat.completions.create(
    model="gemini-3.5-flash-lite",
    messages=[{"role": "user", "content": "Review this code:\n..."}],
)
print(resp.choices[0].message.content)

# 流式
stream = client.chat.completions.create(
    model="gemini-3.5-flash-lite",
    messages=[{"role": "user", "content": "写一个快速排序"}],
    stream=True,
)
for chunk in stream:
    delta = chunk.choices[0].delta
    if delta.content:
        print(delta.content, end="", flush=True)
```

## 2. Codex CLI（0.154+）

Codex 只支持 Responses 协议（`wire_api = "responses"`，旧版 `wire_api = "chat"` 已移除），
网关的 `POST /v1/responses` 已实现协议转换，直接可用。

1. 将 `config/codex/cpoxy.config.toml` 的内容合并到本机 `%USERPROFILE%\.codex\config.toml`，替换 `<GATEWAY-HOST>`（本机 `127.0.0.1`，可信内网用实际网关 IP）。
2. 在**本机进程环境**设置 `CPOXY_API_KEY` 为自己的网关令牌；模板只使用 `env_key`，**不要在 TOML、聊天或仓库中内联密钥**。例如仅对当前 PowerShell 会话：`$env:CPOXY_API_KEY = '<本人令牌>'`。不同用户使用自己的令牌。
3. 直接运行 `codex` 使用模板默认模型；若要保留官方默认配置，把模板前两行放入 `[profiles.cpoxy]`，再显式启动 `codex --profile cpoxy`。

   ```powershell
   codex --profile cpoxy
   ```

验证（非交互模式）：

```powershell
$env:CPOXY_API_KEY = "sk-…"
codex exec --skip-git-repo-check -C <工作目录> "Reply with exactly: OK"
```

使用 profile 时保留 `[model_providers.cpoxy]` 公共配置，并在上面的验证命令里加入 `--profile cpoxy`。Codex CLI 0.157.1 曾通过网关 Responses + Flash-Lite 返回真实回答。

## 3. Cursor / Cherry Studio / ChatBox 等 GUI

通用配置：

| 字段 | 值 |
|---|---|
| Provider 类型 | OpenAI / 自定义 OpenAI 兼容 |
| Base URL | `http://127.0.0.1:3000/v1`（要求不带 /v1 的就填 `http://127.0.0.1:3000`） |
| API Key | 网关令牌 |
| 模型 | 手动填 `gemini-3.5-flash-lite` |

## 4. PowerShell（原生，规避 curl 别名坑）

PowerShell 的 `curl` 是 `Invoke-WebRequest` 别名，会破坏 JSON 转义；统一用 `Invoke-RestMethod`：

```powershell
$body = @{
    model    = "gemini-3.5-flash-lite"
    messages = @(@{ role = "user"; content = "say OK" })
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText("$env:TEMP\req.json", $body)

Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3000/v1/chat/completions" `
    -ContentType "application/json" `
    -Headers @{ Authorization = "Bearer sk-…" } `
    -InFile "$env:TEMP\req.json"
```

## 5. cmd / bash（curl.exe）

```bash
curl http://127.0.0.1:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-…" \
  -d '{"model":"gemini-3.5-flash-lite","messages":[{"role":"user","content":"hi"}]}'
```

Windows cmd 下用 `curl.exe`（带 `.exe` 后缀避免别名），JSON 双引号需整体转义。

## 6. Agent 框架（LangChain / OpenAI Agents / LlamaIndex）

任何支持 `base_url` 覆盖的框架都适用，例如 LangChain：

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="gemini-3.5-flash-lite",
    base_url="http://127.0.0.1:3000/v1",
    api_key="sk-…",
)
```

## 7. 端点速查

| 端点 | 方法 | 说明 |
|---|---|---|
| `/v1/chat/completions` | POST | Flash-Lite 已通过普通和 SSE 问答；其他来源须单独验收 |
| `/v1/responses` | POST | Flash-Lite 已通过 Codex CLI 0.157.1 真实回答及 SSE；其他来源不能套用此结论 |
| `/v1/models` | GET | 可用模型列表，不代表问答成功 |
| `/v1/embeddings` | 取决于渠道 | 当前上游不支持，勿接入 |

| 来源 | OpenAI 聊天接口 | Codex Responses 状态 |
|---|---|---|
| Gemini Flash-Lite | 网关 `/v1/chat/completions`，当前开放 | 网关 `/v1/responses`，已用 CLI 验证 |
| Gemini Flash | 近期返回错误致歉，已禁用 | 不可用，复验后再配置 |
| 4 Argon 实验 | 新账号通过网关普通及 SSE 问答，实际模型 `4 Argon`，现已开放 | 网关 `/v1/responses` 普通及 SSE 正确回答；Codex CLI 0.157.1 基本文本任务实测通过，可将模板 `model` 改为 `gemini-4-argon`；复杂工具调用未验收 |
| 学习通课程 AI | 适配器有聊天接口，浏览器等待本人完成课程登录；网关渠道禁用 | 尚无真实问答，不开放 Codex；适配器的 SSE 是完整答案后输出 |
| ChatGPT Web | 网关 `chatgpt-web-active` → 网页 `auto`（当前模型可变，本次后端曾显示 `gpt-6-thinking`），普通及 SSE 正确回答；显式选模失败返回 422，避免将当前模型冒充指定版本 | 当前源站未实现 `/v1/responses`：网关返回 404，**不能接 Codex CLI**。需要另行实现 Responses 与工具调用适配并实测，不要与 Codex 官方账号登录混淆 |
| Grok Web | `grok-web-fast` → `Web/grok-chat-fast`，本机同出口代理下隔离上游及网关的普通/SSE 真实问答通过 | 网关 `/v1/responses` 普通及 SSE 简单文本问答成功；但 Codex CLI 基本任务的工具参数被上游以 HTTP 400 拒绝，**不可标为 Codex CLI 可用**。客户端 Key 有共用 2 RPM 限制，不要盲目重发 |

## 8. 已知行为边界

- 上游对带 `tools` 的请求是"缓冲后整发"，不是逐 token 流式
- 匿名模式下无 `reasoning_content`；配置 Cookie 后 `-thinking` 模型才返回思维链
- 实验 Argon 上游配置了每出口并发 5 / RPM 30 / RPH 80；但该构建也可能在账号或出口不可用时以 `ip_slot_full` 返回 429。先检查账号状态和管理端 `/admin/api/usage`，不能假设等待/盲目重试必然解决。
