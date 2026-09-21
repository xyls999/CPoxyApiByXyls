# 部署手册

从零把整套 Coding API 网关跑通。全程 Windows / PowerShell。

## 1. 获取组件

### 方式 A：仓库自带（推荐）

本体已随仓库附带：`bin/new-api/new-api.exe.zip`（网关）与
`bin/gemini-web2api-go/gemini-web2api-go.exe`（反代）。克隆后运行
`.\scripts\setup.ps1` 即完成解压与配置，无需下载与构建。

### 方式 B：官方 Release 直下（bin/ 缺失时的自动回退）

`setup.ps1` 会自动从上游官方 Release 下载并做 SHA256 校验：

- 网关：<https://github.com/QuantumNous/new-api/releases>
- 反代：<https://github.com/zexadev/gemini-web2api-go/releases>

### 方式 C：源码构建

需要 Go 1.21+（反代）/ Go 1.25+ 与 Bun（网关）：

```powershell
# 反代
git clone https://github.com/zexadev/gemini-web2api-go <任意目录>\gemini-web2api-go
cd <任意目录>\gemini-web2api-go
go build -o gemini-web2api-go.exe .

# 网关（必须先构建前端，go:embed 需要 web\dist）
git clone https://github.com/QuantumNous/new-api <任意目录>\new-api
cd <任意目录>\new-api\web
bun install
bun run build
cd ..
go build -o new-api.exe .
```

自建组件放到 `bin\new-api\` 与 `bin\gemini-web2api-go\`（与仓库默认路径一致），
或用环境变量 `NEWAPI_DIR` / `GEMINI_API_DIR` 指向任意位置。

> 注意：必须先构建前端，否则 `go build` 报 `pattern web/dist: no matching files found`。

## 2. 启动

```powershell
.\scripts\start-all.ps1
```

脚本会先拉起上游（8083），再拉起网关（3000），并轮询两个端口直到监听成功。

上游首次启动会生成 API Key，在启动日志 / `data\server.stdout.log` 的
`API key: sk-…` 一行可找到完整值；也可在上游管理台 Settings 页查看。

## 3. 首次初始化（仅一次）

### 3.1 初始化网关管理员

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3000/api/setup" `
    -ContentType "application/json" `
    -Body '{"username":"root","password":"你的强密码","confirmPassword":"你的强密码","SelfUseModeEnabled":true,"DemoSiteEnabled":false}'
```

或直接浏览器打开 `http://127.0.0.1:3000` 走页面引导。

### 3.2 登录并创建渠道

浏览器登录管理台 → 渠道 → 添加渠道：

| 字段 | 值 |
|---|---|
| 类型 | OpenAI |
| 名称 | 任意，如 `gemini-web2api-go` |
| Base URL | `http://127.0.0.1:8083` |
| 密钥 | 上游的 `sk-…` API Key |
| 模型 | `gemini-3.6-flash,gemini-3.5-flash-lite` |

也可用 `config/channel.example.json` 模板通过 API 提交（把 `key` 换成真实上游 Key）。

### 3.3 发放对外令牌

管理台 → 令牌 → 添加：额度设无限或按需，得到 `sk-…` 网关令牌。客户端一律使用网关令牌，上游 Key 永不外发。

## 4. 验证

```powershell
$env:CODING_API_KEY = "sk-你的网关令牌"
.\scripts\test-api.ps1
```

三项全绿（models / 非流式 / 流式）即部署完成，按 README 第 4 步接入工具。

## 5. 端口自定义

- 网关端口：启动前设置 `PORT` 环境变量（new-api 支持）
- 上游端口/绑定地址：编辑上游目录 `data\local.config.json` 的 `port` / `host`

## 6. 故障排查

| 现象 | 处理 |
|---|---|
| `go build` 找不到 web/dist | 先完成前端构建（步骤 1.2 方式 B） |
| go 拉取依赖慢/失败 | 配置代理 `go env -w GOPROXY=https://goproxy.cn,direct` |
| 上游返回 invalid JSON | 检查客户端 JSON 转义，改用本仓库脚本或 `Invoke-RestMethod` |
| Defender 拦截 exe | `Add-MpPreference -ExclusionPath "<组件目录>"` |
| 网关 502/渠道禁用 | 管理台看渠道测试；确认上游在监听、Key 未轮换 |
| 令牌报 401 | 用管理台完整 Key，别用打码显示值 |
