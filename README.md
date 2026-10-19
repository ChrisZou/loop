# Loop

人在回路 · 方案批注。把 AI 生成的方案粘贴进来，像 Google Docs 评论一样选中原文逐条批注，再一键导出为一条结构化反馈，粘贴回 AI 让它修改下一版。

| 目录 | 形态 | 说明 |
| --- | --- | --- |
| [`web/`](web/README.md) | 纯静态网页（Vite + TypeScript） | 移动端优先，主要在 iPhone Safari 上使用，桌面浏览器同样可用；会话存在 localStorage |
| [`mac/`](mac/README.md) | 原生 SwiftUI macOS App | NSTextView 编辑器，原文可边改边批注，范围自动跟随；会话存在 `~/Library/Application Support/Loop/session.json` |

两端互相独立，不共享数据。构建、运行和限制见各自的 README。

```sh
# web
cd web && npm install && npm run test && npm run build   # 产物在 web/dist/

# mac
cd mac && swift build -c release && .build/release/Loop --selftest
./build-app.sh && open build/Loop.app
```
