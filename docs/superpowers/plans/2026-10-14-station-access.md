# 内网 AI 中转站实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 new-api 保留安全认证与真实渠道状态的前提下，完成响应式入口、基准 token 等值赠额并对其余来源实施真实问答验收。

**Architecture:** CPoxy 仓库持有可审计的首页 HTML 与配置验收记录；new-api 原有注册服务端执行赠额，入口 API 与登录注册路由不重写。非 Gemini 来源分别独立通过问答后才能启用。

**Tech Stack:** Windows PowerShell、SQLite 快照、new-api Go 服务、官方 `HomePageContent` HTML 渲染、Node 适配器。

**Spec:** `docs/superpowers/specs/2026-10-14-station-access-design.md`

## Global Constraints

- 内部 quota 单位每美元 500000；基准价格每千 token $0.002；10 亿基准 token 等值为 1000000000000 quota 单位，不是跨模型硬 token 上限。
- 上游和浏览器资料仅绑定本机；不上传真实凭据或 `.runtime/`。
- 学习通与 ChatGPT Web 保持禁用，直到各自经 new-api 真实返回答案。

---

### Task 1: 验证注册赠额并配置内网边界

**Files:** 修改本机 `E:/cpa/new-api/one-api.db` 的 `QuotaForNewUser` 选项；不修改 new-api 源码。私有备份放 CPoxy `.runtime/`。

**Interfaces:** 消费 `model.User.Insert` 的 `common.QuotaForNewUser`，产出新用户的内部 quota 1000000000000。

- [ ] **Step 1:** 用 Python `sqlite3.Connection.backup` 保存 new-api 数据库到 `.runtime/new-api-before-gift.db`，确认新备份仅当前用户和 SYSTEM 可读。
- [ ] **Step 2:** 在隔离的数据库副本启动另一端口的 new-api，创建一个随机测试用户；先断言新用户 quota 为旧值 `500000000000`，确认测试识别了旧行为。
- [ ] **Step 3:** 在副本 `options` 表执行 `INSERT OR REPLACE INTO options (key,value) VALUES ('QuotaForNewUser','1000000000000')`；重启副本，用 `/api/user/register` 注册不同的测试用户，断言其 quota 为 `1000000000000`、旧用户未改变、重复用户名未获得二次赠额。
- [ ] **Step 4:** 更新正式数据库相同选项后重启本机网关；复核 `GET /api/status` 和数据库值，确认登录/注册入口仍可访问。将 Windows 端口 3000 入站规则的 `RemoteAddress` 从 Any 收紧为 `LocalSubnet`，不开放上游端口。
- [ ] **Step 5:** 清理测试数据库副本中的测试账号文件（不删除正式账号），记录成功与残余 HTTP 风险。

### Task 2: 优化入口与认证导览

**Files:** 新增 `config/home-page.html`；保持 `config/home-page.md` 为回退参考；修改 `README.md` 的入口与赠额说明。

**Interfaces:** new-api 的 `HomePageContent` 接收 HTML 字符串；站内链接 `/sign-in`、`/sign-up`、`/playground`、`/models`。

- [ ] **Step 1:** 编写可离线检查的首页结构测试：确认四条站内链接、四个来源卡片、“等值/非固定 token 数”文案、无 `<script>` 与无密钥字样；运行并先见失败。
- [ ] **Step 2:** 写入响应式 HTML/CSS，避免依赖外部 CDN、运行时脚本或凭据。来源卡片必须把未验收渠道标为禁用，Argon 标为实验。
- [ ] **Step 3:** 运行结构测试转绿；检查 new-api 源码 `HtmlContent` 净化允许 `<style>` 而屏蔽 `<script>`，将新 HTML 写入正式数据库 `HomePageContent` 并重启网关。
- [ ] **Step 4:** 用浏览器验证桌面/移动排版与登录、注册 CTA，检查根页及 `/api/home_page_content` HTTP 200；运行原有 Node 适配器测试和 `git diff --check`。

### Task 3: 学习通真实验收（外部登录门控）

**Files:** `scripts/check-sources.ps1` 的运行输出与学习通 `.runtime` 服务状态；失败前不改启用状态。

**Interfaces:** 上游 8787 → 适配 8788 → new-api `chaoxing-course-ai`。

- [ ] **Step 1:** 检查上游浏览器和适配器状态；本人尚未完成课程登录时记录 `LOGIN_REQUIRED`/offline 并保持渠道状态 2。
- [ ] **Step 2:** 登录完成后先通过适配器完成一次文本问答，核对会话释放；再临时启用对应 channel/ability，经 new-api 问答成功才保留启用，否则回滚。

### Task 4: ChatGPT Web 真实验收（上游修复门控）

**Files:** 独立试验服务和私有日志；失败前不改 new-api 渠道状态。

**Interfaces:** 上游 18080 → new-api `chatgpt-web-browser`。

- [ ] **Step 1:** 只读检查上次 504 `generation_stuck` 证据与隔离试验进程，不自动重复可能已发送的问题。
- [ ] **Step 2:** 在用户本人确认浏览器账号正常后发一次新的、可识别的测试提示；上游有真实回答才临时启用渠道并经 new-api 复测，失败则保持禁用并报告具体阶段。

## Self-review

- 覆盖来源门控、入口布局、既有认证复用与基准等值赠额；没有把监听成功写成问答成功。
- 不引入新数据库结构，避免跨 SQLite/MySQL/Postgres 的迁移验证问题。
- 认证操作沿用已存在的服务端校验；新首页不得收集密码。
