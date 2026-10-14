# grok2api（siinclair/grok2api）接入可行性，2026-10-14

## 结论

**它确实包含 Grok Web 网页接口转 OpenAI 协议的反向适配，但不仅是网页反代。** 项目提供三个独立 Provider：Grok Build（OAuth）、Grok Web（SSO）和 Grok Console（SSO）；统一暴露 `POST /v1/chat/completions`、`/v1/responses` 等。此结论来自[项目说明](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md)和[Web Provider 能力声明](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/definition.go)。

Grok Web 适配代码默认请求 `https://grok.com`，其私有实时网关使用 `/ws/mgw/` WebSocket，并以 Web SSO/Cloudflare Cookie 组成认证头；不是官方 `api.x.ai` API。证据：[默认上游](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/adapter.go#L62-L70)、[WebSocket URL 与认证头](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/gateway.go#L184-L210)、[账号 SSO 约束](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/definition.go#L20-L30)。

## 本机可验证范围

- `siinclair/grok2api` 是 `chenyme/grok2api` 的 fork；检查时二者 `HEAD` 均为 `7c889a960e2638341b4dae9a5c81af0e0f38c87f`，故当前 fork 没有独立代码变更。[Fork](https://github.com/siinclair/grok2api)、[上游](https://github.com/chenyme/grok2api)。仓库自身 Docker Compose 默认拉上游的 `ghcr.io/chenyme/grok2api:latest`，并非 fork 单独构建的镜像：[docker-compose.yml](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/docker-compose.yml#L4-L9)。建议跟进原仓库，固定提交或镜像 digest；不要把未经锁定的 `latest` 当作稳定可复现构建。
- 在 Windows 上用本机 Go 1.26.9 编译 `./cmd/grok2api` **成功**；`go test ./internal/infra/provider/web` **通过**。初次试跑测试时额外传入了不存在的 `./internal/transport/http/gateway` 包路径并失败，这只是所给路径错误；重新运行 Web Provider 测试通过。
- **尚无 Grok Web SSO 登录会话，尚未做真实 Grok 问答；所以不能断言该机当前可用，也未接入或开放 new-api。** 健康检查、能编译和 mock 测试都不能替代上游回答。Web 认证可能因 SSO 过期、Cloudflare Clearance/出口 IP/浏览器指纹不一致而失败。[README 出口与 Cloudflare](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#出口与-cloudflare)、[上游反机器人报错](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/backend/internal/infra/provider/web/chat.go)。
- 当前 Windows 主机没有 Docker 命令；原项目提供[源码运行](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#源码运行)。已经用 `pnpm install --frozen-lockfile && pnpm build` 构建管理前端、用 Go 1.26.9 编译后端；构建放在 Git 忽略的私有 `.runtime/research/`。
- 已使用私有配置启动 `127.0.0.1:18084`：`GET /healthz`、管理 UI 返回 200；本机初始化管理员的登录、鉴权查询与退出均成功，未输出凭据。`GET /readyz` 仍返回 503：模型路由和账本正常，但 Grok Web/Console 无账号而不可用。**管理 UI 启动不等于 Grok 真正可调用。** 无公网监听或 new-api Grok 渠道。

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

## 如果随后接入

1. 只在 `127.0.0.1:18084` 隔离启动本机编译版本；强随机管理 JWT/凭据加密密钥，账号写入后不得随意更换加密密钥。Docker 的默认 `8000:8000` 端口映射会暴露到所有接口，应改成 `127.0.0.1:18084:8000`，不复用内网公开的 :3000。[配置示例](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/config.example.yaml#L6-L41)、[Compose 映射](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/docker-compose.yml#L3-L10)。
2. 用户只在本机管理端安全录入 Grok Web 的 SSO；不得把会话 Cookie 发到聊天、Git 或日志。使用账号实测 Web 类别的真实文本回答，例如最低 Basic 类别的 `grok-chat-fast`；不要用 Build/Console 的成功替代 Web 验收。[Web 模型等级表](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#-grok-web)。
3. 由本机 Grok2API 生成独立客户端 Key，在 new-api 中创建**默认禁用**的 OpenAI 兼容渠道，Base URL 为 `http://127.0.0.1:18084`（由 new-api 追加 `/v1/...`）。只有 Grok2API **和** new-api 两层都返回真实回答，并核实实际上游类别后，才启用已验证模型；失败则保持禁用。图片/视频/语音不因文本成功而自动验收。
4. 项目自述仅用于研究学习，使用时遵守 Grok 条款；不要把非官方网页协议视为稳定 SLA。[README 免责声明](https://github.com/siinclair/grok2api/blob/7c889a960e2638341b4dae9a5c81af0e0f38c87f/README.zh-CN.md#项目简介)。
