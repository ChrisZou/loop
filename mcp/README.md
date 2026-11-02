# Loop MCP

stdio MCP server：把现有的网页审阅脚本和本机 `loop` CLI 暴露成四个工具，方便 Claude Desktop / Cursor 等直接调。

## 工具

| 工具 | 作用 |
| --- | --- |
| `loop_web_create` | 创建手机网页审阅，返回 `reviewUrl` |
| `loop_web_wait` | 轮询网页反馈（超时可续等） |
| `loop_mac_detach` | 本机 `loop review --detach` |
| `loop_mac_wait` | 本机 `loop wait` |

## 运行

```sh
# 网页工具需要 Agent Token
export LOOP_AGENT_TOKEN=…
# 可选：LOOP_URL、LOOP_BIN（默认 loop）

node mcp/server.mjs
```

Claude Desktop / Cursor 配置示例：

```json
{
  "mcpServers": {
    "loop": {
      "command": "node",
      "args": ["/绝对路径/loop/mcp/server.mjs"],
      "env": {
        "LOOP_AGENT_TOKEN": "你的 token"
      }
    }
  }
}
```

本机 Mac 工具需要已安装 `loop`（`mac/build-app.sh` + `ln -sf … ~/.local/bin/loop`）。
