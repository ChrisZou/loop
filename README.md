# Loop

人在回路 · 方案批注。把 AI 生成的方案粘贴进来，像 Google Docs 评论一样选中原文逐条批注，再一键导出为一条结构化反馈，粘贴回 AI 让它修改下一版。

| 目录 | 形态 | 说明 |
| --- | --- | --- |
| [`web/`](web/README.md) | 纯静态网页（Vite + TypeScript） | 移动端优先，主要在 iPhone Safari 上使用，桌面浏览器同样可用；会话存在 localStorage |
| [`mac/`](mac/README.md) | 原生 SwiftUI macOS App | 行内批注（原文高亮 + 末尾小图标，悬停看、点击改）；支持 `loop review` 让 AI 直接发起审阅，提交后反馈自动回传 |

两端互相独立，不共享数据。构建、运行和限制见各自的 README。

## AI 发起审阅（Mac）

```sh
loop review 方案.md    # 打开审阅窗口并等待；用户点「提交」后把反馈打印到标准输出
```

AI 代理在后台运行这条命令，命令一结束就读输出拿到反馈，改出下一版再发起下一轮审阅，不需要人工复制粘贴。安装方式见 [mac/README.md](mac/README.md#让-ai-发起审阅)。

```sh
# web
cd web && npm install && npm run test && npm run build   # 产物在 web/dist/

# mac
cd mac && swift build -c release && .build/release/Loop --selftest
./build-app.sh && open build/Loop.app
ln -sf "$PWD/bin/loop" ~/.local/bin/loop
```
