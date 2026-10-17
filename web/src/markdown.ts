import { marked } from 'marked'
import DOMPurify from 'dompurify'

export function renderMarkdown(article: HTMLElement, source: string): void {
  article.innerHTML = DOMPurify.sanitize(marked.parse(source, { async: false, gfm: true }), {
    // Keep the document inert so arbitrary HTML cannot mimic app controls.
    FORBID_TAGS: ['input', 'textarea', 'button', 'select', 'form', 'style', 'iframe', 'video', 'audio'],
    FORBID_ATTR: ['style', 'id', 'class', 'tabindex', 'autofocus', 'contenteditable'],
    ALLOW_DATA_ATTR: false,
  })
  article.querySelectorAll('table').forEach((table) => {
    const wrapper = document.createElement('div')
    wrapper.className = 'table-scroll'
    wrapper.tabIndex = 0
    wrapper.setAttribute('role', 'region')
    wrapper.setAttribute('aria-label', '表格，可横向滚动')
    table.before(wrapper)
    wrapper.append(table)
  })
  article.querySelectorAll('pre').forEach((pre) => {
    pre.tabIndex = 0
    pre.setAttribute('aria-label', '代码，可横向滚动')
  })
  article.querySelectorAll('a').forEach((link) => {
    link.target = '_blank'
    link.rel = 'noopener noreferrer'
  })
  article.querySelectorAll('img').forEach((image) => { image.loading = 'lazy' })
}

export const sample = `# 个人知识库 · 产品方案

让收集的内容，成为随时可用的知识。

## 1. 核心流程

用户保存文章、灵感和读书笔记，在需要时通过搜索快速找回。

- **快速收集**：粘贴链接或文字，自动保存到收件箱。
- **轻量整理**：支持标签与收藏，不强制建立文件夹。
- **智能检索**：用自然语言描述问题，返回相关片段。

## 2. 交互设计

首页默认展示最近保存的内容。顶部提供搜索框，右下角放置新建入口。

> 保存后立即返回列表，整理操作可以稍后完成。

移动端采用单列卡片，每张卡片显示标题、摘要和最多三个标签。长按卡片进入多选模式，支持批量归档。

## 3. 技术选择

| 模块 | 方案 | 说明 |
| --- | --- | --- |
| 前端 | TypeScript + Vite | 静态部署，快速加载 |
| 数据 | 本地存储 | 首版离线可用 |
| 搜索 | 关键词匹配 | 后续加入语义检索 |

数据结构示例：

\`\`\`typescript
interface Note {
  id: string
  title: string
  content: string
  tags: string[]
  createdAt: number
}
\`\`\`

## 4. 首版范围

1. 新建、编辑和删除笔记。
2. 标签筛选与全文搜索。
3. 导出 Markdown 备份。

暂不支持多人协作和跨设备同步。
`
