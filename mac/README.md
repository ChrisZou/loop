# Loop

原生 SwiftUI macOS 批注工具：粘贴 AI 方案，选中文字添加批注，一键复制结构化反馈。

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

脚本生成 `build/Loop.app`，Bundle ID 为 `com.chris.loop`，使用团队 `W4SX57U6XB` 的 Developer ID Application 证书签名；缺少有效证书时构建会报错。此构建未公证。

## 使用

- 左侧粘贴或编辑方案；空白时显示操作提示，提示不写入正文。Markdown 标题、列表、行内代码和加粗仅使用属性渲染，保留原始文本。
- 选中文字后按 `⌘↩`，或点击工具栏 / 选区旁的「批注」。在右侧输入意见后按 `⌘↩` 或「保存」；`Esc` 取消。
- 点击批注卡片（包括留白）选中并滚动到原文；卡片提供编辑、删除按钮及右键菜单，编辑期间卡片留白不触发定位。保存后正文选区收起到末尾；精确选中已有批注或正在编辑草稿时不显示浮动「批注」按钮。
- 「总体意见」可选填。`⇧⌘C` 或工具栏「导出反馈」复制已保存批注及总体意见；提示中的批注数量不包含总体意见，填写总体意见时另标注「（含总体意见）」。两者均为空时提示「还没有批注」，保留剪贴板内容。「预览导出」可先查看完整文本，导出格式不变。
- `⌘N` 新建；已有内容时会先确认。未保存的批注草稿不参与导出或会话保存。

批注按文档位置排序，使用 UTF-16 范围与 NSTextView 对齐。插入 / 删除会调整范围，完全删除或完全替换原文会移除对应批注。引文随原文同步更新。正文支持系统撤销；已移除的批注不会随正文撤销恢复。

正文、已保存批注和总体意见在修改后约 0.5 秒自动保存，退出时再次保存：

`~/Library/Application Support/Loop/session.json`

## 演示与自检

```sh
LOOP_DEMO=1 .build/release/Loop
LOOP_DEMO=1 LOOP_DEMO_PREVIEW=1 .build/release/Loop
.build/release/Loop --selftest
```

演示模式使用中文待办 App 方案、3 条真实范围批注和总体意见，不读写已有会话。第二个命令在启动时自动打开导出预览。

`--selftest` 不启动界面、不读写会话，使用独立剪贴板，校验导出完整格式、导出提示及空内容保护、保存后的选区与重复批注入口、多行引文 / 意见、排序、UTF-16 范围调整、演示数据和 JSON 往返；失败时返回非零退出码。

导出纯函数位于 `Sources/Loop/FeedbackExporter.swift`：`FeedbackExporter.export(text:comments:general:)`。
