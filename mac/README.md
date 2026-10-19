# Loop

原生 SwiftUI macOS 批注工具：在 AI 写的方案上选中文字逐条批注。AI 可以用 `loop review` 把方案直接交给你审阅，你点「提交」后反馈自动回到 AI 那边，不用复制粘贴；也可以自己粘贴方案，一键复制结构化反馈。

需要 macOS 14+、Xcode Command Line Tools（Swift 5.9+），无第三方依赖。

## 构建与运行

```sh
swift build -c release
.build/release/Loop
```

裸可执行文件也会以常规前台 App 启动，显示窗口和菜单。

```sh
./build-app.sh
open build/Loop.app
```

脚本生成 `build/Loop.app`，Bundle ID 为 `com.chris.loop`，使用团队 `W4SX57U6XB` 的 Developer ID Application 证书签名，找不到证书时退回 ad-hoc 签名。此构建未公证。

## 让 AI 发起审阅

```sh
ln -sf "$PWD/bin/loop" ~/.local/bin/loop   # 一次性安装，~/.local/bin 需在 PATH 中

loop review 方案.md          # 或：生成方案的命令 | loop review -
```

`loop review` 打开一个只读的审阅窗口（标题「审阅 · 文件名」），然后阻塞等待：

- 点「提交」或按 `⇧⌘↩`：反馈打印到标准输出，退出码 0。没有批注也没有总体意见时会先确认，提交内容为「我看过了这版方案，没有修改意见，可以按这版继续。」
- 没提交就关窗：标准错误输出「未提交」，退出码 1。批注暂存在 `~/Library/Application Support/Loop/reviews/`，再次审阅同一份方案会恢复，提交后删除。

AI 代理在后台运行这条命令，命令结束就是用户提交了，读取输出即可拿到反馈。每次审阅是独立进程（`open -n`），不影响平时用的 Loop 会话。也可以直接运行 `Loop --review <文件> [--out <反馈文件>]`，不传 `--out` 时反馈写到标准输出。

## 使用

- 批注是行内的：被批注的原文高亮，最后一个字后面有一个小图标。鼠标悬停图标显示批注内容，点击图标编辑或删除。同一处结尾的多条批注并排显示多个图标。
- 选中文字后按 `⌘↩`，或点击工具栏 / 选区旁的「批注」，在弹出框里写意见，`⌘↩` 或「保存」确认，`Esc` 或「取消」放弃。弹出框打开时点别处会自动保存已输入的内容。
- 窗口底部是「总体意见」，可选填，右侧显示批注数量；审阅模式下这里还有「提交」按钮。
- 普通模式：左上角「新建」（`⌘N`，已有内容时先确认）；`⇧⌘C` 或工具栏「导出反馈」复制已保存批注及总体意见。提示中的批注数量不包含总体意见，填写总体意见时另标注「（含总体意见）」；两者均为空时提示「还没有批注」，不改动剪贴板。「预览导出」可先查看完整文本。
- Markdown 标题、列表、行内代码和加粗只改样式，保留原始文本；图标的位置靠字距让出，也不改动原文，所以批注范围始终有效。

批注按文档位置排序，使用 UTF-16 范围与 NSTextView 对齐。普通模式下可以边改原文边批注：插入 / 删除会调整范围，完全删除或完全替换原文会移除对应批注，引文随原文同步更新。正文支持系统撤销；已移除的批注不会随正文撤销恢复。

普通模式的正文、已保存批注和总体意见在修改后约 0.5 秒自动保存，退出时再次保存：

`~/Library/Application Support/Loop/session.json`

## 演示与自检

```sh
LOOP_DEMO=1 .build/release/Loop
LOOP_DEMO=1 LOOP_DEMO_PREVIEW=1 .build/release/Loop
.build/release/Loop --selftest
```

演示模式使用中文待办 App 方案、3 条真实范围批注和总体意见，不读写已有会话。第二个命令在启动时自动打开导出预览。

`--selftest` 不启动界面、不读写会话，使用独立剪贴板和临时目录，校验导出完整格式、导出提示及空内容保护、保存后的选区与重复批注入口、多行引文 / 意见、排序、UTF-16 范围调整、行内图标位置、审阅参数解析、提交内容与反馈文件写入、演示数据和 JSON 往返；失败时返回非零退出码。

导出纯函数位于 `Sources/Loop/FeedbackExporter.swift`：`FeedbackExporter.export(text:comments:general:)`。
