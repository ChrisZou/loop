# Loop hosted server

Node.js 22+，原生 `node:http` / ESM，无服务端依赖或构建步骤。Web 构建需要 Node.js 22.12+。一个进程拥有一个本机数据目录；适合单机部署，不支持多个进程共享此目录或 NFS。

## 运行

```sh
# 仓库根目录
npm ci --prefix web
npm run build
# 通过环境或受保护的环境文件设置 LOOP_AGENT_TOKEN，不写入源码/网页
npm start
```

`npm start` 在 `server/` 中运行 `node index.mjs`。也可 `cd server && node index.mjs`。默认访问 http://127.0.0.1:3020；方案入口为 `/?review=<UUID>`，首页不加载示例方案。

| 环境变量 | 默认值 | 用途 |
| --- | --- | --- |
| `PORT` | `3020` | 监听端口 |
| `HOST` | `127.0.0.1` | 监听地址 |
| `LOOP_AGENT_TOKEN` | 必填 | Agent 创建方案和读取反馈的 Bearer；不发送给浏览器 |
| `LOOP_DATA_DIR` | `./data` | 方案和反馈目录，相对进程工作目录 |
| `LOOP_WEB_DIST` | `../web/dist` | Web 构建目录，相对进程工作目录 |
| `LOOP_PUBLIC_URL` | `http://<HOST>:<PORT>` | 对外 origin，例如 `https://loop.weallwitness.com`；用于 reviewUrl 和浏览器 Origin 校验，生产部署必须设置 |
| `LOOP_WEBHOOKS_FILE` | `<data dir>/../webhooks.json` | Agent 名称到 Webhook 的映射 |

复制 `webhooks.example.json` 到配置路径并设置权限 `0600`。每个 Agent 对应 `{ "url": "https://agent.example/feedback", "bearer": "..." }`；空 URL 或无映射跳过转发，反馈仍可轮询。URL 只能来自此服务端配置，支持 HTTPS，以及本机调试用 localhost/127.0.0.1/[::1] HTTP。拒绝 URL 用户信息、片段和跳转。配置在每次投递时重新读取。密钥不要放在 URL 中。

## API

所有写入 JSON 请求上限 1 MiB；错误为 `{error}`。无跨域 CORS 接口。

- `GET /api/health` → `{ok:true}`。
- `POST /api/reviews`：必须 `Authorization: Bearer <LOOP_AGENT_TOKEN>`，会话令牌不能替代。JSON `{title,agentName,document,parentReviewId?}`。字段上限分别 120、100、30000 个 UTF-16 单元，均非空；parentReviewId 如提供必须是已存在的小写 UUID，不接受 null。返回 201 `{reviewId,title,agentName,document,createdAt,parentReviewId,revision,reviewUrl}`。新建 revision=1，父版+1，最多1000；每次创建新 UUID v4，不能覆盖，创建重试可能产生多个版本。
- `GET /api/reviews/<id>`：公开返回 `{reviewId,title,agentName,document,createdAt,parentReviewId,revision}`，无列表接口。任何持有链接的人都能读取该方案。
- `POST /api/session`：空请求体，返回 `{session,expiresIn:1800}`。浏览器 Origin 必须与 PUBLIC_URL 一致；非浏览器可省略 Origin。能力仅保存在页面内存，最多30次反馈尝试，重启后失效。它允许提交反馈，不认证审阅人或 Agent 身份。
- `POST /api/feedback`：`X-Loop-Session: <session>` 和 `Content-Type: application/json`；正文为 [Webhook v1](../protocol/README.md)，必须包含 reviewId/revision。校验原方案存在、revision、agentName 和 document 完全匹配。反馈持久化后返回202 `{accepted:true,submissionId,duplicate,persisted:true}`。同 ID 同内容幂等（含重启和并发），同 ID 不同内容409。submissionId 使用小写 UUID。
- `GET /api/reviews/<id>/feedback`：必须 Agent Bearer；返回 `{reviewId,feedback:[{payload,receivedAt,delivery}]}`，按接收时间排序。payload 是完整原始 Webhook v1 JSON；无反馈为空数组。投递状态不会泄露 Webhook 地址或密钥。

反馈最多100条批注，总体意见5000字符，单条意见5000字符、引用30000字符、ID 100字符、summary 200000字符，偏移上限200000。检查偏移为整数、UTF-16长度、排序、非重叠、唯一批注ID和 summary 一致性。为保持零依赖，服务端不重复运行浏览器渲染器；quote/start/end 是不可信的显示引用，**不得直接用于自动修改原文**。Agent 应结合完整 Markdown 核验反馈。

## 存储和投递

`data/reviews/<reviewId>.json` 存不可变方案，`data/feedback/<submissionId>.json` 存 `{payload,receivedAt,delivery}`。文件权限0600，新目录0700。临时文件先 fsync，再通过硬链接原子发布或 rename 更新，目录也 fsync；返回 accepted 前已持久化。不要从 Web 静态目录公开数据目录。

后台每5秒检查待投递反馈，先存储再 POST 原始 payload（含 summary、reviewId、revision、原 Agent 名称）。每次超时10秒，最多5次，失败按指数退避；重启会继续 `pending`。`delivery` 含 `status`（pending/delivered/skipped/failed）、`attempts`，投递后含 `updatedAt`、可选 `httpStatus`/`nextAttemptAt`（Unix毫秒）。2xx标记 delivered，仅表示目标接受，不证明 Agent 完成工作。

这是至少一次投递：接收端必须按 submissionId 幂等。崩溃可能发生在目标已接受但本地未记录状态之间。failed/skipped 不再自动投递；Agent 可通过鉴权轮询补取，修复配置后也可停服、备份记录，将 delivery 改为 `{"status":"pending","attempts":0,"nextAttemptAt":0}` 再启动，保持 payload 不变。磁盘故障时反馈写入返回500，不会报告成功。备份整个 data 目录并自行制定保留策略；服务不自动删除反馈。轮询与后台扫描使用文件遍历，大规模部署应迁移到数据库/队列。

会话最多10000个，30分钟过期；会话和反馈接口按 TCP 对端地址合计限制120次/分钟。反向代理时后端看到代理地址，故这是部署总量上限；不信任客户端转发 IP 头。nginx 可再按真实连接 IP 限速。链接属于公开读取能力，勿将 Agent Token 放入页面、链接或浏览器存储。

## systemd + nginx

以下以 `/opt/loop` 为仓库，`loop` 为无登录服务用户。先构建 web/dist；创建 `/var/lib/loop`（loop 所有、0700）和 `/etc/loop`（受保护目录）。将 Agent Token 和部署变量写入 `/etc/loop/loop.env`，由 root 管理、0600；Webhook 配置 `/etc/loop/webhooks.json` 设 root:loop、0640。环境文件内容（token 使用实际生成值，不提交）：

```ini
HOST=127.0.0.1
PORT=3020
LOOP_AGENT_TOKEN=<a-long-random-token>
LOOP_DATA_DIR=/var/lib/loop
LOOP_WEB_DIST=/opt/loop/web/dist
LOOP_WEBHOOKS_FILE=/etc/loop/webhooks.json
LOOP_PUBLIC_URL=https://loop.weallwitness.com
```

`/etc/systemd/system/loop.service`（确认 Node 22+ 的实际路径）：

```ini
[Unit]
Description=Loop hosted reviews
After=network.target

[Service]
Type=simple
User=loop
Group=loop
WorkingDirectory=/opt/loop/server
EnvironmentFile=/etc/loop/loop.env
ExecStart=/usr/bin/node /opt/loop/server/index.mjs
Restart=on-failure
RestartSec=3
TimeoutStopSec=45
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/loop

[Install]
WantedBy=multi-user.target
```

nginx 的 `http` 块内声明限速区，再配置站点（先签发域名证书，路径按实际修改）：

```nginx
limit_req_zone $binary_remote_addr zone=loop_writes:10m rate=30r/m;

server {
    listen 80;
    server_name loop.weallwitness.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name loop.weallwitness.com;
    ssl_certificate /etc/letsencrypt/live/loop.weallwitness.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/loop.weallwitness.com/privkey.pem;
    client_max_body_size 1m;
    # 避免默认日志保存 review 链接；如需日志，应使用不含查询参数的格式。
    access_log off;

    location ~ ^/api/(session|feedback)$ {
        limit_req zone=loop_writes burst=10 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:3020;
        proxy_set_header Host $host;
        proxy_read_timeout 35s;
    }
    location / {
        proxy_pass http://127.0.0.1:3020;
        proxy_set_header Host $host;
        proxy_read_timeout 35s;
    }
}
```

静态 HTML 也经过 Node，才能注入 `window.LOOP_HOSTED=true`。不要用 nginx 直接绕过 index.html 注入。执行 `systemctl daemon-reload && systemctl enable --now loop`、`nginx -t && systemctl reload nginx`，检查 `https://loop.weallwitness.com/api/health`。更新时重新构建 web/dist 并 `systemctl restart loop`，沿用数据目录与凭证；只向外开放80/443。

## 验证

仓库根目录：`npm test`（全部 Node 测试 + Web 单测）、`npm run build`、`npm run test:e2e`（本机 Chrome）。仅服务端：`npm run test:server`；也可 `cd server && npm test`。Node HTTP 集成测试需要允许监听 loopback，使用临时目录和本机 mock Webhook，不访问外部 Agent。
