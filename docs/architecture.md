# 架构说明

## 组件与职责

```
CPoxyApiByXyls（本仓库：脚本 + 文档 + 配置模板）
        │ 编排
        ├──▶ new-api          —— API 网关（Go + Gin + GORM，SQLite）
        ├──▶ gemini-web2api-go —— 上游协议代理（Go 单文件）
        └──▶ Gemini Web        —— Google 前端协议
```

### new-api（网关层）

- 对客户端暴露标准 OpenAI 协议：`/v1/chat/completions`、`/v1/models`
- 令牌（Token）体系：发放、额度、过期、模型白名单、IP 白名单
- 渠道（Channel）体系：把"网关模型名 → 上游渠道"做映射；支持多渠道加权、失败重试、自动禁用与恢复
- 计费与日志：按 token 用量记账，请求级日志落库（SQLite：`one-api.db`）

### gemini-web2api-go（上游层）

- 把 Gemini Web 页面内部协议封装为 OpenAI 兼容 API
- utls 模拟 Chrome 146 真实 TLS 指纹，降低封锁概率
- SQLite 记录请求元数据（`data/gemini.db`），不存正文
- 管理 UI：`http://127.0.0.1:8083/admin`

## 请求链路

```
客户端
  │  POST /v1/chat/completions
  │  Authorization: Bearer sk-<new-api 令牌>
  ▼
new-api :3000
  │  1. 令牌鉴权 / 额度检查 / 模型→渠道路由
  │  2. 改写 Authorization 为上游渠道 Key（sk-gemini-…）
  │  3. 透传请求体（含 stream 标志）
  ▼
gemini-web2api-go :8083
  │  4. 协议翻译为 Gemini Web RPC（流式增量）
  ▼
Gemini Web
  │  5. 响应逐层回传
  ▼
new-api 统计 usage 并把 SSE 原样透传给客户端
```

## 端口与数据文件

| 项 | 值 | 说明 |
|---|---|---|
| 网关 HTTP | 127.0.0.1:3000 | 客户端唯一入口 |
| 上游 HTTP | 127.0.0.1:8083 | 仅网关访问，勿暴露公网 |
| 网关数据 | `new-api` 目录下 `one-api.db` | SQLite（WAL） |
| 上游数据 | 上游目录下 `data/gemini.db` | SQLite |
| 网关管理台 | `http://127.0.0.1:3000` | Web UI |
| 上游管理台 | `http://127.0.0.1:8083/admin` | Web UI |

## 安全边界

- 上游服务绑定 `0.0.0.0` 时有独立 API Key 鉴权；本地使用建议绑定 `127.0.0.1`（`data/local.config.json` 中 `host` 字段）
- new-api 令牌是唯一对外凭据；泄露可在管理台一键吊销，不影响上游 Key
- 渠道 Key 存于网关数据库，仅在管理台可见（打码显示）
- 两套 SQLite 均默认仅监听本机进程，不涉及网络落盘
