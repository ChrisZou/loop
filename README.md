# Loop

人在回路 · 方案批注。像 Google Docs 评论一样在 AI 生成的方案上选中原文逐条批注，整理成一条结构化反馈交回给 AI，让它修改下一版。Mac 版由 AI 发起审阅、提交即回传；Web 版粘贴方案批注，提交到 Agent 的 Webhook。

| 目录 | 形态 | 说明 |
| --- | --- | --- |
| [`web/`](web/README.md) | 纯静态网页（Vite + TypeScript） | 桌面和手机都能用；批注后通过 Webhook 提交给 Agent，可配置多个 Agent；原文、批注和草稿存在 localStorage。来自 Codex 版 Loop，2026-10-20 合并进来 |
| [`mac/`](mac/README.md) | 原生 SwiftUI macOS App | 只做审阅：AI 用 `loop review` 发起，提交后反馈自动回传；「红笔批改」风格（白纸、衬线标题、隐藏 Markdown 符号）；行内批注（朱红下划线 + 末尾圈码，悬停看、点击改） |
| [`server/`](server/README.md) | Node.js 22+ 托管服务 | Agent 鉴权创建不可变方案，公开链接审阅，反馈落盘、Webhook 投递与鉴权轮询 |
| [`protocol/`](protocol/README.md) | 文档 + JSON Schema | Web 版提交反馈的格式（Webhook v1） |
| [`skills/loop-review/`](skills/loop-review/SKILL.md) | Agent Skill（SKILL.md） | 教 AI 代理怎么用 Loop：把方案写成便于批注的 Markdown、发起 `loop review`、读退出码和反馈格式、改完再审直到认可。软链到 `~/.claude/skills/`、`~/.codex/skills/` 等目录即可启用 |
| [`examples/`](examples/) | Node 脚本 | 本地示例收件器 `receiver.mjs` 和收件箱读取器 `watch-inbox.mjs`，用来本机联调 Web 版提交；测试在 `tests/` |

两端互相独立，不共享数据。构建、运行和限制见各自的 README。

## AI 发起审阅（Mac）

```sh
loop review 方案.md    # 打开审阅窗口并等待；用户点「提交」后把反馈打印到标准输出
```

AI 代理在后台运行这条命令，命令一结束就读输出拿到反馈，改出下一版再发起下一轮审阅，不需要人工复制粘贴。安装方式见 [mac/README.md](mac/README.md#构建与安装)。

```sh
# web
cd web && npm ci && npm test && npm run build   # 产物在 web/dist/
npm run test:e2e                                 # Playwright，用本机 Chrome

# 托管服务（在仓库根目录，先设置 LOOP_AGENT_TOKEN）
npm start                                      # http://127.0.0.1:3020
npm test                                       # Node + Web 单测

# 示例收件器（在仓库根目录）
node --test tests/*.test.mjs
node examples/receiver.mjs                       # http://127.0.0.1:8787/webhook

# mac
cd mac && swift build -c release && .build/release/Loop --selftest
./build-app.sh
ln -sf "$PWD/bin/loop" ~/.local/bin/loop
```
