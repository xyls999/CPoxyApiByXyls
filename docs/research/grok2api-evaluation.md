# grok2api（siinclair/grok2api）接入可行性，2026-10-14

> 本轮复验更新：用户在独立 Edge 登录 Grok 后，已将 SSO 与 Cloudflare 登录态仅在本机导入隔离服务，并为 Grok Web 账号绑定与浏览器一致的回环代理出口。首次未配出口的真实问答为 `502 upstream_timeout`，**没有重发该问题**；修正后隔离上游普通/SSE 与正式网关普通/SSE 均以不同新题返回正确答案。审计确认来源 `grok_web` / `Web/grok-chat-fast`。现已开放 `grok-web-fast` 文本聊天；隔离上游补丁修复了分片 XML 工具调用缓存错误，第一版补丁经正式网关的 Chat Completions 流式函数调用 → 本地工具结果 → 正确续答已实测，但复审后构建的工具往返遭遇上游瞬断/未选工具，尚未再次通过。Responses 的工具结果续答及 Codex CLI 的真实工具执行**仍未验收**（分别出现 XML 泄露、Windows 沙箱拒绝）。进程重启后账号、代理、客户端 Key 均持久保留；`/readyz` 为 HTTP 200 但 Web 组件为 `degraded`，不等同持续稳定或 SLA。

## 结论

**它确实包含 Grok Web 网页接口转 OpenAI 协议的反向适配，但不仅是网页反代。** 项目提供三个独立 Provider：Grok Build（OAuth）、Grok Web（SSO）和 Grok Console（SSO）；统一暴露 `POST /v1/chat/completions`、`/v1/responses` 等。此结论来自[项目说明](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md)和[Web Provider 能力声明](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/definition.go)。

Grok Web 适配代码默认请求 `https://grok.com`，其私有实时网关使用 `/ws/mgw/` WebSocket，并以 Web SSO/Cloudflare Cookie 组成认证头；不是官方 `api.x.ai` API。证据：[默认上游](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/adapter.go#L62-L70)、[WebSocket URL 与认证头](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/gateway.go#L184-L210)、[账号 SSO 约束](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/definition.go#L20-L30)。

## 本机可验证范围

- `siinclair/grok2api` 是 `chenyme/grok2api` 的 fork；检查时二者 `HEAD` 均为 `7c889a960e2638341b4dae9a5c81af0e0f38c87f`，故当前 fork 没有独立代码变更。[Fork](https://github.com/siinclair/grok2api)、[上游](https://github.com/chenyme/grok2api)。仓库自身 Docker Compose 默认拉上游的 `ghcr.io/chenyme/grok2api:latest`，并非 fork 单独构建的镜像：[docker-compose.yml](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/docker-compose.yml#L4-L9)。建议跟进原仓库，固定提交或镜像 digest；不要把未经锁定的 `latest` 当作稳定可复现构建。
- 在 Windows 上用本机 Go 1.26.9 编译 `./cmd/grok2api` **成功**；`go test ./internal/infra/provider/web` **通过**。初次试跑测试时额外传入了不存在的 `./internal/transport/http/gateway` 包路径并失败，这只是所给路径错误；重新运行 Web Provider 测试通过。
- **初次调研时**无 Grok Web SSO 会话、无真实回答、未接入网关；上述情况已由本轮复验改变。健康检查、能编译和 mock 测试仍不能替代上游回答。Web 认证可能因 SSO 过期、Cloudflare Clearance/出口 IP/浏览器指纹不一致而失败。[README 出口与 Cloudflare](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#出口与-cloudflare)、[上游反机器人报错](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/chat.go)。
- 当前 Windows 主机没有 Docker 命令；原项目提供[源码运行](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#源码运行)。已经用 `pnpm install --frozen-lockfile && pnpm build` 构建管理前端、用 Go 1.26.9 编译后端；构建放在 Git 忽略的私有 `.runtime/research/`。
- 已使用私有配置启动 `127.0.0.1:18084`：`GET /healthz`、管理 UI 返回 200；本机管理员登录成功且未输出凭据。初次调研 `/readyz` 为 503、Web/Console 无账号。现在 Web 有一条本机账号及独立客户端 Key，`/readyz` HTTP 200 但 Web 为 `degraded`，Console 仍无账号；网关 id 5 仅接入 `grok-web-fast`，服务仅监听回环。**管理 UI 和 `/readyz` 仍不能替代已单独通过的真实回答。**

## Grok 工具调用补丁与验收范围

第三方源码固定于本机 `E:\cpa\CPoxyApiByXyls\.runtime\research\grok2api` 的原提交 `7c889a960e2638341b4dae9a5c81af0e0f38c87f`；本仓库保存可复现的本地补丁 [`patches/grok2api-web-stream-tools.patch`](../../patches/grok2api-web-stream-tools.patch)。在**干净的对应上游提交**执行 `git apply <本仓库补丁路径>`，然后在 `backend/` 执行 `go test -count=1 ./internal/infra/provider/web` 和 `go build -o <本机私有目录>/grok2api-trial.exe ./cmd/grok2api`。不要将配置、账号库、日志或浏览器资料带入补丁或版本库。该补丁候选二进制已在本机编译，但因最终构建的 SSE 新题复验出现 `upstream_stream_interrupted`，当前隔离服务已回滚到 `.runtime/research/grok2api-trial-pre-tool-sieve.exe`；服务仅监听 `127.0.0.1:18084`。候选及回滚文件均留在私有 `.runtime/research/`，不提交版本库。

- **TDD 复现**：原 `toolStreamSieve.Feed` 只缓存打开 `<tool_calls>` 的第一个分片，后续分片丢弃先前 XML，还把内部标记泄露为安全文本。新增测试按 1、7、23 字节切片，原代码 `calls=0, leaked=true`；补丁后每种分片恰好 1 个已声明的 `exec_command`，无 XML 泄露。复审进一步发现有效调用后的普通文本会丢失、未闭合 XML 可无界累积；另两条先红后绿的测试现覆盖调用前后文本和超过 1 MiB 的失败关闭。Web Provider 包测试通过。
- `go test -count=1 ./...` 在**未修改的** `internal/infra/egress` 包 `TestPinnedHTTPSClientSOCKS5HReceivesPinnedIP` 失败：Windows `wsarecv` 提示连接被本机软件中止；单独复现亦失败。故**不能称全量 Go 测试通过**，相关 stdout/stderr 仅留本机私有 `.runtime/research/grok2api-go-full-tests.*.log`。
- 正式网关 `/v1/chat/completions` 的真实流式首轮返回 `get_local_token` 函数调用；将上游未知的本机随机值按同一 `tool_call_id` 的 `role=tool` 放入完整消息历史，第二轮非流式准确回答该值，且没有额外工具调用或 XML 泄露（第一版分片修复构建）。具体调用形状见 [Coding API 调用范式](../api-paradigms.md#grok-web-agent实际验收的函数工具往返)。复审后的最终构建专项测试通过且不同的普通非流式新题正确回答，但两道**不同的新工具流式题**在约一秒出现 `upstream_stream_interrupted`，另一道非流式 `tool_choice=required` 新题返回普通文本、未给出工具调用；均未重发原题。故最终构建的 agent 往返**尚未再次实测通过**，不能把第一版的单次成功推广为当前持续可靠的承诺，调用方必须检查工具事件并失败关闭。
- Responses 的简单文本及首次 SSE `function_call` 通过；但一次用 `previous_response_id` + `function_call_output` 续答未采用随机工具结果，反而把函数调用 XML 作为文本输出，**不能把该路径当作已验收 agent 接口**。
- Codex CLI 0.157.1 默认附带 `multi_agent_v1` 的 `namespace`，Grok Web 返回 400 `invalid_tools`；独立私有配置 `features.multi_agent=false` 移除了 namespace。补丁前模型给出的工具 XML 原样泄露；补丁后成功发出 `exec_command` 并收到工具反馈，但 Windows `read-only` 沙箱拒绝启动 PowerShell，未读到文件。另一轮 `workspace-write` 试验则未自动选择工具。**不修改用户默认 Codex 配置，也不推荐 `danger-full-access` 绕过沙箱；Codex CLI 仍不可标为可用。**

## 本机启动与登录

当前服务已启动。打开 <http://127.0.0.1:18084/>，初始管理员名为 `admin`。初始密码仅保存在本机 ACL 限制的 `E:\cpa\CPoxyApiByXyls\.runtime\research\grok2api-config.yaml` 的 `bootstrapAdmin.password`，只在本机打开文件查看；不要粘贴到聊天、截图或仓库。登录后更改管理员密码，并在重启前从配置中删除 `bootstrapAdmin` 节；保留 `secrets.credentialEncryptionKey`，否则已有账号资料将无法解密。

若进程结束，在 PowerShell 重新启动现有配置和二进制（**先确认 18084 无监听**）：

```powershell
$r = 'E:\cpa\CPoxyApiByXyls\.runtime\research'
Start-Process -FilePath "$r\grok2api-trial.exe" `
  -WorkingDirectory "$r\grok2api" `
  -ArgumentList @('--config', "$r\grok2api-config.yaml", '--listen', '127.0.0.1:18084') `
  -WindowStyle Hidden `
  -RedirectStandardOutput "$r\grok2api.stdout.log" `
  -RedirectStandardError "$r\grok2api.stderr.log"
```

随后只在本机管理端“账号 → Grok Web”录入自己的 Grok 网页会话、同步额度；Cookie/SSO 不能发到聊天。未验证前 `readyz` 可能保持 503，这是预期的失败关闭状态。

## 接入步骤与其他机器的复验条件

以下 Web 文本路径已在本机逐项执行；如迁移到其他机器、换账号/出口或 Cookie 失效，必须重新实测。

1. 只在 `127.0.0.1:18084` 隔离启动本机编译版本；强随机管理 JWT/凭据加密密钥，账号写入后不得随意更换加密密钥。Docker 的默认 `8000:8000` 端口映射会暴露到所有接口，应改成 `127.0.0.1:18084:8000`，不复用内网公开的 :3000。[配置示例](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/config.example.yaml#L6-L41)、[Compose 映射](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/docker-compose.yml#L3-L10)。
2. 用户只在本机管理端安全录入 Grok Web 的 SSO；不得把会话 Cookie 发到聊天、Git 或日志。使用账号实测 Web 类别的真实文本回答，例如最低 Basic 类别的 `grok-chat-fast`；不要用 Build/Console 的成功替代 Web 验收。[Web 模型等级表](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#-grok-web)。
3. 由本机 Grok2API 生成独立客户端 Key，在 new-api 中创建**默认禁用**的 OpenAI 兼容渠道，Base URL 为 `http://127.0.0.1:18084`（由 new-api 追加 `/v1/...`）。只有 Grok2API **和** new-api 两层都返回真实回答，并核实实际上游类别后，才启用已验证模型；失败则保持禁用。图片/视频/语音不因文本成功而自动验收。
4. 项目自述仅用于研究学习，使用时遵守 Grok 条款；不要把非官方网页协议视为稳定 SLA。[README 免责声明](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#项目简介)。
