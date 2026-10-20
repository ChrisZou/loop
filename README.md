# Loop

人在回路 · 方案批注。像 Google Docs 评论一样在 AI 生成的方案上选中原文逐条批注，整理成一条结构化反馈交回给 AI，让它修改下一版。Mac 版由 AI 发起审阅、提交即回传；Web 版粘贴方案、一键复制反馈。

| 目录 | 形态 | 说明 |
| --- | --- | --- |
| [`web/`](web/README.md) | 纯静态网页（Vite + TypeScript） | 移动端优先，主要在 iPhone Safari 上使用，桌面浏览器同样可用；会话存在 localStorage |
| [`mac/`](mac/README.md) | 原生 SwiftUI macOS App | 只做审阅：AI 用 `loop review` 发起，提交后反馈自动回传；居中阅读栏、隐藏 Markdown 符号；行内批注（原文高亮 + 末尾序号圆标，悬停看、点击改） |

两端互相独立，不共享数据。构建、运行和限制见各自的 README。

## AI 发起审阅（Mac）

```sh
loop review 方案.md    # 打开审阅窗口并等待；用户点「提交」后把反馈打印到标准输出
```

AI 代理在后台运行这条命令，命令一结束就读输出拿到反馈，改出下一版再发起下一轮审阅，不需要人工复制粘贴。安装方式见 [mac/README.md](mac/README.md#构建与安装)。

```sh
# web
cd web && npm install && npm run test && npm run build   # 产物在 web/dist/

# mac
cd mac && swift build -c release && .build/release/Loop --selftest
./build-app.sh
ln -sf "$PWD/bin/loop" ~/.local/bin/loop
```
