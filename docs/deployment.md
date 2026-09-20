# 部署手册

从零把整套 Coding API 网关跑通。全程 Windows / PowerShell。

## 1. 获取组件

### 1.1 gemini-web2api-go（上游）

方式 A：Release 直下（推荐，零构建）

到 <https://github.com/zexadev/gemini-web2api-go/releases> 下载对应平台的单文件（Windows 为
`gemini-web2api-go_windows_amd64.exe` 之类命名），放到任意目录，例如：

```
E:\gemini-webapi-go\gemini-web2api-go\
└── bin\gemini-web2api-go.exe
```

方式 B：源码构建（需要 Go 1.21+）

```powershell
git clone https://github.com/zexadev/gemini-web2api-go E:\gemini-webapi-go\gemini-web2api-go
cd E:\gemini-webapi-go\gemini-web2api-go
go build -o bin\gemini-web2api-go.exe .
```

### 1.2 new-api（网关）

方式 A：Release 下载

到 <https://github.com/QuantumNous/new-api/releases> 下载 Windows 二进制，放到
`E:\cpa\new-api\new-api.exe`。

方式 B：源码构建（本方案验证过的路径）

前置：Go 1.25+、Bun（前端构建用）。

```powershell
git clone https://github.com/QuantumNous/new-api E:\cpa\new-api
cd E:\cpa\new-api\web
bun install
bun run build          # 产物 web\dist，后端 go:embed 需要
cd ..
go build -o new-api.exe .
```

> 注意：必须先构建前端，否则 `go build` 报 `pattern web/dist: no matching files found`。

## 2. 启动

```powershell
$env:NEWAPI_DIR     = "E:\cpa\new-api"
$env:GEMINI_API_DIR = "E:\gemini-webapi-go\gemini-web2api-go"
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
