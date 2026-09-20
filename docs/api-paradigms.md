# Coding API 调用范式

网关对外 100% OpenAI 兼容。以下所有示例的三个常量：

```
BASE_URL = http://127.0.0.1:3000/v1
API_KEY  = sk-<new-api 网关令牌>
MODEL    = gemini-3.6-flash   # 或 gemini-3.5-flash-lite
```

## 1. Python / OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:3000/v1", api_key="sk-…")

# 非流式
resp = client.chat.completions.create(
    model="gemini-3.6-flash",
    messages=[{"role": "user", "content": "Review this code:\n..."}],
)
print(resp.choices[0].message.content)

# 流式
stream = client.chat.completions.create(
    model="gemini-3.6-flash",
    messages=[{"role": "user", "content": "写一个快速排序"}],
    stream=True,
)
for chunk in stream:
    delta = chunk.choices[0].delta
    if delta.content:
        print(delta.content, end="", flush=True)
```

## 2. Cursor / Cherry Studio / ChatBox 等 GUI

通用配置：

| 字段 | 值 |
|---|---|
| Provider 类型 | OpenAI / 自定义 OpenAI 兼容 |
| Base URL | `http://127.0.0.1:3000/v1`（要求不带 /v1 的就填 `http://127.0.0.1:3000`） |
| API Key | 网关令牌 |
| 模型 | 手动填 `gemini-3.6-flash` |

## 3. PowerShell（原生，规避 curl 别名坑）

PowerShell 的 `curl` 是 `Invoke-WebRequest` 别名，会破坏 JSON 转义；统一用 `Invoke-RestMethod`：

```powershell
$body = @{
    model    = "gemini-3.6-flash"
    messages = @(@{ role = "user"; content = "say OK" })
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText("$env:TEMP\req.json", $body)

Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3000/v1/chat/completions" `
    -ContentType "application/json" `
    -Headers @{ Authorization = "Bearer sk-…" } `
    -InFile "$env:TEMP\req.json"
```

## 4. cmd / bash（curl.exe）

```bash
curl http://127.0.0.1:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-…" \
  -d '{"model":"gemini-3.6-flash","messages":[{"role":"user","content":"hi"}]}'
```

Windows cmd 下用 `curl.exe`（带 `.exe` 后缀避免别名），JSON 双引号需整体转义。

## 5. Agent 框架（LangChain / OpenAI Agents / LlamaIndex）

任何支持 `base_url` 覆盖的框架都适用，例如 LangChain：

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="gemini-3.6-flash",
    base_url="http://127.0.0.1:3000/v1",
    api_key="sk-…",
)
```

## 6. 端点速查

| 端点 | 方法 | 说明 |
|---|---|---|
| `/v1/chat/completions` | POST | 对话补全，支持 `stream: true` |
| `/v1/models` | GET | 可用模型列表 |
| `/v1/embeddings` | 取决于渠道 | 当前上游不支持，勿接入 |

## 7. 已知行为边界

- 上游对带 `tools` 的请求是"缓冲后整发"，不是逐 token 流式
- 匿名模式下无 `reasoning_content`；配置 Cookie 后 `-thinking` 模型才返回思维链
- 上游限流：每 IP 并发 5 / RPM 30 / RPH 80，429 属上游节流，退避重试即可
