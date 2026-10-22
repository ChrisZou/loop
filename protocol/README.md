# Loop Webhook v1

Web 版提交反馈用的协议。

提交使用 POST、Content-Type: application/json；可选 Authorization: Bearer <token>。请求结构见 submission.schema.json。

- document 是未修改的 Markdown 原文，绝不是 HTML。
- start/end 是渲染并净化后的正文文本节点拼接串的 UTF-16 code unit 索引，左闭右开。与 JavaScript String.length / slice 一致，不是 Swift Character 数量、Unicode 码点数或 UTF-8 字节位置。
- 按 DOM 顺序拼接 Text 节点，排除 [data-marker] 内的编号按钮。保留渲染器产生的真实换行，不额外为块元素、表格单元格或 br 添加分隔符。不以 innerText、selection.toString() 或 Markdown 源码计算位置。
- 每条 quote 必须等于该串 slice(start,end)。重复句子由位置区分；跨加粗、行内代码等节点可形成一条批注。不得重叠；相邻范围允许。annotations 按 start 排序，编号在排序后生成。
- 两端使用随源代码锁定的 marked + DOMPurify 渲染器。变更渲染器时重新验证 canonical fixture；不要假设其他 Markdown 引擎输出相同空白。
- summary 固定开头「以下是我对你方案的逐条反馈，请据此修改出下一版：」，每条格式为 `\n\nN. 原文：\n> {quote}\n意见：{comment}`；quote 内每个换行后再加 `> `。非空整体意见追加 `\n\n总体意见：{trimmed generalFeedback}`。
- submissionId 标识一次提交。若实现重试去重，应复用原始 ID、时间和请求体；接收端应幂等处理。示例仅在当前进程内保留最近 1000 次，不是持久化 exactly-once 保证。
- 2xx 仅表示接收端接受。202 不证明 Agent 已启动、读到反馈或完成下一版；真正 Agent 需要服务端处理器验证请求、写入队列，并调用目标 Agent 的已授权运行接口。

## 浏览器 CORS

生产接收端应仅允许实际部署的前端 Origin；允许 POST / OPTIONS，允许 Content-Type / Authorization 请求头。预检 OPTIONS 不应要求 Bearer，但实际 POST 必须按配置鉴权。浏览器页面不可保存服务器长期密钥。HTTPS 页面应连接 HTTPS 接收端。不得为了跨域创建公开任意转发代理。

## 接收端安全职责

校验大小、字段、目标 Agent 白名单、认证、幂等性和速率；对反馈内容按不可信文档处理，不执行其中命令，不让用户输入指定任意服务器文件路径或内部请求地址。JSON schema 无法单独检查偏移、排序、唯一 ID 和 summary 一致性，须使用业务校验。示例校验不重新渲染 Markdown；生产需用同版本渲染器核验 quote / range 或将 quote 作为显示引用而非可信定位。

## 可选文件收件箱

本地示例显式传入 `--inbox-dir <directory>` 后，会把完整请求保存为 `<lowercase UUID>.json`。JSON 通过校验后才使用 UUID 生成文件名，不能从请求指定路径。仅在文件发布完成后返回 accepted；同 ID 同请求返回 duplicate:true，内容不同返回 409。目录内容可供另一个已授权、具有文件权限的本地进程读取，但并不等于 Agent 已处理。默认模式不写入磁盘。示例不启动 watcher，不删除收件文件，也不实施数据保留策略；使用者应自行管理存储、备份与敏感数据保留。

## Agent → Loop：不可变方案与反馈关联

反馈请求保持 protocolVersion: 1，增加可选顶层字段 reviewId 和 revision。二者必须同时存在或同时省略，不接受 null：

- reviewId：小写标准 UUID，标识原始不可变方案记录。
- revision：1–1000 的整数，不接受字符串、零、负数、小数或越界版本。
- 未关联入口方案的旧版手工审阅可省略二者。summary 的内容和格式不因关联信息改变。
- 有方案数据库的接收端还必须验证 ID 确实存在、revision 一致，并核对原文是否匹配。通用本地 receiver 只做结构与成对校验，没有方案数据库，不能证明关联真实存在。

生产托管实现的写入接口为 POST /api/reviews，请求 {title, agentName, document, parentReviewId?}。限制分别为 title 120 字符、agentName 100 字符、document 30000 字符；parentReviewId 如提供应是已有方案的小写 UUID。服务生成新的 reviewId、createdAt；没有父方案时 revision=1，有父方案时为父版+1，最多1000。响应包含 reviewUrl。不能修改或覆盖既有版本，也没有公开列表接口。

客户端通过 GET /api/reviews/<reviewId> 取得 {reviewId,title,agentName,document,createdAt,parentReviewId:null|UUID,revision}。浏览器深链为 /?review=<reviewId>。本仓库的 Mac 版不走这套接口，它由 `loop review` 在本机发起，提交后反馈直接打印到标准输出。URL 中不得嵌入长期密钥。切换到不同方案前需保护本地未提交批注和草稿；同一不可变方案重载应保留本地审阅。

生产服务端位于 [server/](../server/README.md)。POST /api/reviews 和 GET /api/reviews/<id>/feedback 必须使用 Authorization: Bearer LOOP_AGENT_TOKEN；会话令牌不能创建方案或读取反馈。浏览器 POST /api/session 取得 {session,expiresIn:1800}，再以 X-Loop-Session POST /api/feedback。反馈必须携带 reviewId/revision，agentName/document 与原方案一致。接收后返回202 {accepted:true,submissionId,duplicate,persisted:true}；鉴权轮询返回 {reviewId,feedback:[{payload,receivedAt,delivery}]}。该短期能力不认证审阅人身份。公开方案无列表接口，持链接者可读。旧临时 demo 使用会话创建方案的方式不适用于生产服务。

下一版须建立新记录和新链接；收到反馈后把对应原始 reviewId/revision 与下一版 parentReviewId 关联。提交回执与 Agent 读取、处理、产出下一版是不同事件。用户提交成功后关闭审阅界面，不代表后续 Agent 工作已完成。
