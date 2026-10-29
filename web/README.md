# Loop Web

轻量中文 Markdown 审阅界面，Vite + TypeScript，无后端依赖、无 CDN、无遥测。字体使用系统字体。

来自 Codex 做的 Loop（`cf66c1f`），2026-10-20 合并进本仓库，替换了原先「粘贴方案 + 复制反馈」的版本。反馈通过 Webhook 提交，提交格式见 [protocol/](../protocol/README.md)。

## 运行

需要 Node.js 22.12+。

```sh
npm ci
npm run dev            # http://127.0.0.1:5173
npm test               # vitest + jsdom
npm run build
npm run test:e2e       # Playwright，用本机安装的 Google Chrome
```

生产文件在 `dist/`，可用任意静态 HTTP 服务部署。不要直接用 `file://` 打开。生产建议 HTTPS；UUID 与 Clipboard 等浏览器能力依赖安全上下文，localhost 可用于开发。

## 使用

1. Markdown 标签页粘贴原文，应用修改。
2. 在审阅页选中文字，点击浮动「批注」或 Alt+Enter。保存后显示黄色高亮及编号。
3. 悬停编号或点击高亮/编号打开编辑卡；Tab 可聚焦编号，Enter 打开。移动端使用系统文字选择，再点浮动按钮。Esc 关闭卡片。
4. 可填写底部总体意见。在设置中添加一个或多个 Agent，填写其 Webhook。可选密钥以 Authorization: Bearer 发送。
5. 顶部选择目标，点击提交。已打开的未保存批注、未应用的 Markdown 修改必须先处理。

不预设任何 Agent 的回调地址。普通 AI 对话链接不是 Webhook。

本地联调可以用仓库根目录的示例收件器：`node examples/receiver.mjs`，在设置里把 Webhook 填成 `http://127.0.0.1:8787/webhook`。加 `--inbox-dir <目录>` 会把每次提交存成 JSON 文件，`examples/watch-inbox.mjs` 可以读取。收件器只接受 5173/4173 端口的本机网页。

## 数据和安全

- 原文、批注、总体意见、Agent 名称和地址、上次选择保存在 localStorage（同源/当前浏览器）。不提供云同步或加密。
- 密钥只在当前页内存中保留；刷新/关闭即清除。不要在 Webhook URL 中放入密钥。存储不可用会在状态中显示。
- 输入中的 Markdown 和批注草稿另存于 localStorage；刷新后显示「继续编辑」提示。切回审阅或关闭批注卡不会丢弃草稿。只有「放弃修改」「放弃草稿」、新建、应用或保存对应内容会清理相关草稿。草稿不改变已应用原文及其锚点。
- 原文改动时需明确确认清空已有原文批注；总体意见保留。新建需确认，保留 Agent 设置。
- 标注不允许重叠，相邻选择允许。修改已有标注或删除再重新选择。
- Markdown 原始 HTML 显示为文字；DOMPurify 净化输出。图片直接显示：只接受 http(s) 和 base64 的行内位图（png/jpeg/gif/webp/avif），其他地址退化成替代文字；图片 `loading="lazy"`、`referrerpolicy="no-referrer"`，所以懒加载图片只在滚到附近时才向图床发请求，且不带来源页地址。相对路径按网页自身地址解析，本地文件路径显示不出来。链接只有用户点击才打开。
- `- [ ]` / `- [x]` 任务项画成方框，点一下切换勾选（键盘可用空格 / 回车）：方案原本的勾是灰勾，你改过的勾是绿色实心块，你取消的是绿色空心框；改过的项随提交回传为「待办的勾选状态改为：- [x] …」，方案本身不动。方框不带文字节点，批注位置不受影响。
- 地址允许 HTTPS 及 localhost/127.0.0.1/[::1] HTTP。拒绝 URL 用户名、密码和片段。HTTP 只建议本地调试。
- 提交时做不可变快照；不清空原文/批注。15 秒超时，网络/CORS/HTTP 错误保留所有反馈。HTTP 2xx 仅说明接口接受，不证明 Agent 已生成回复。跳转被拒绝，避免密钥转发到其他地址。
- 超时或连接中断可能已被服务器接收，请先核对接收端再重试。内容和目标未变时重试复用原请求体、submissionId 和时间（刷新后也保留）；修改反馈后生成新 ID，服务端应以 ID 去重。

## 集成协议

详见 [protocol/README.md](../protocol/README.md) 和 JSON Schema。POST application/json:

```json
{
  "protocolVersion": 1,
  "submissionId": "UUID",
  "agentName": "方案助手",
  "document": "原始 Markdown",
  "annotations": [{"id":"UUID","quote":"所选原文","comment":"意见","start":0,"end":4}],
  "generalFeedback": "总体意见",
  "submittedAt": "ISO 8601 UTC",
  "summary": "以下是我对你方案的逐条反馈，请据此修改出下一版：\n\n1. 原文：\n> 所选原文\n意见：意见\n\n总体意见：总体意见"
}
```

start/end 是净化后的 Markdown DOM 中所有文字节点拼接后的 UTF-16 code unit 偏移，左闭右开。不增加块分隔符；保留渲染器生成的真实空白。排除批注编号节点，原始 Markdown 的字符偏移不可与此混用。annotations 按 start 排序；quote 用于二次校验。

接收端需要处理 OPTIONS，允许网页来源、POST、Content-Type 和可选 Authorization。跨域只在服务端能正确解决，前端不能绕过 CORS。HTTPS 页面调用 HTTP localhost 还可能受混合内容/本地网络访问策略限制，优先同源代理或可信 HTTPS。

## 验证情况

- `npm run build`：通过。
- `npm test`：31 项通过，覆盖重复引用、嵌套粗体/列表、多节点标注、代码/表格、UTF-16、编号排除、重叠、HTML/脚本/图片安全、URL、排序/快照，以及 UI 增删改、快捷键、草稿恢复、会话密钥、HTTP 错误/成功、改文与新建确认。Node 25+ 自带的 localStorage 会盖掉 jsdom 的，`vitest.config.ts` 里已用 `--no-experimental-webstorage` 关掉。
- `npm run test:e2e`：3 个桌面/390px 手机视口流程在本机 Chrome 中通过。
- 用示例收件器实际提交过一次：2 条批注加总体意见，收件器收到的 summary 与 Mac 版回传格式一致。
- 未在 iPhone Safari 真机上验证长按选字、系统键盘和提交后自动关闭页面。

## 托管模式

仓库的 [server/](../server/README.md) 提供 `/api/session`、`/api/feedback`、`/api/reviews`，并在 index.html 中注入 `window.LOOP_HOSTED=true`。独立静态部署不会请求这些接口。

### 生产托管模式

通过 `/?review=<UUID>` 打开不可变方案；仅显示提交、原文、批注和总体意见，不显示演示或虚构内容提示，也不预载示例方案。新建、设置、目标选择和 Markdown 编辑隐藏并禁用。提交强制走同源 `/api/session` 与 `/api/feedback`，保留原方案 agentName/reviewId/revision，不使用浏览器中旧外部 Webhook。Agent 长期凭证只在服务端使用。切换保护、草稿恢复、幂等重试和完成页沿用现有逻辑。无有效方案时不能提交，加载另一方案失败也不能误提交旧方案。宽表格/代码可在正文内横向滚动，手机按钮扩大触控范围。

### 可选托管演示模式

仅当宿主页在 bundle 前明确注入 `window.LOOP_DEMO=true` 时，启用同源演示收件箱预设。提交先 POST `/api/session` 取得一次页面内存中使用的短期能力，再用 `X-Loop-Session` POST `/api/feedback`。不会把能力写入存储；仅校验 accepted 且 submissionId 与本次匹配才报告入箱。显示公开演示/虚构内容/云端提交警告，不声称已启动 Agent。独立版无此标志时保持通用 Webhook 行为。

### Agent 主动发送方案

收到 `?review=<UUID>` 链接时，同源 GET `/api/reviews/<UUID>` 获取不可变方案与标题、Agent、revision 元数据。空白/初始演示页面自动打开；已有原文、批注、总体意见或草稿时必须确认切换。取消或加载失败保持当前内容，并允许重新打开。同一 reviewId 刷新只恢复本地状态，不覆盖修改。反馈关联顶层 `reviewId` 和 `revision`。点新建或应用实际改变的 Markdown 会清除该关联和地址栏 review 参数，转为手动文档；未改变原文的应用操作保留关联。独立静态模式不请求此 API。

方案链接可由任意持有链接的人读取；反馈没有公开读取接口，Agent 通过鉴权轮询或配置的服务端 Webhook 接收。提交成功表示反馈已落盘，投递与 Agent 处理为后续事件。仅旧 demo 模式限于虚构测试内容。

## 极简审阅与提交完成

审阅页只显示必要操作、原文、行内批注与总体意见；说明位于设置。确认成功响应后调用 `window.close()`。浏览器不允许关闭时显示空白的「已提交」完成页，不再显示编辑器。同一会话刷新相同方案仍为完成页；打开新的 review 链接可继续审阅。网络错误、超时或无效回执不会关闭编辑器。完成态是 sessionStorage 标记；用户资料与草稿仍在本地保留。浏览器/iPhone Safari 是否允许真实关闭仍需实机验证。

### 当前会话专属审阅模式

托管演示中的 Agent 方案链接只显示提交操作、原文、行内批注和总体意见。新建、设置、目标选择和 Markdown 编辑入口隐藏且禁用；提交强制使用当前会话同源接收端，不受旧浏览器外部 Agent 选择影响。独立通用工具仍保留多 Agent 设置和手动 Markdown 模式。既有未保存草稿的恢复/放弃入口保留，避免丢失内容。
