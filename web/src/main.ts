import './style.css'
import { renderMarkdown, sample } from './markdown'
import { selectionAnchor, rangeFromOffsets, reanchor, wrapHighlights } from './anchor'
import type { Anchor } from './anchor'
import { formatFeedback, sortFeedback } from './export'
import type { Feedback } from './export'
import { emptySession, loadSession, saveSession } from './store'

const icons = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  edit: '<path d="m16 3 5 5-12 12H4v-5L16 3Z"/><path d="m13 6 5 5"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
  eye: '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  arrow: '<path d="M7 17 17 7M7 7h10v10"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  comment: '<path d="M21 11a9 9 0 0 1-9 9H4l-3 2 2-7a9 9 0 1 1 18-4Z"/>',
}
function icon(name: keyof typeof icons): string {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`
}
function get<T extends HTMLElement>(selector: string): T {
  const element = document.querySelector<T>(selector)
  if (!element) throw new Error(`Missing element: ${selector}`)
  return element
}

get('#app').innerHTML = `
  <header class="topbar">
    <div class="brand"><span class="brand-symbol" aria-hidden="true">∞</span><div><h1>Loop</h1><p>人在回路 · 方案批注</p></div></div>
    <nav aria-label="文档操作">
      <button id="new" class="icon-button" title="新建" aria-label="新建">${icon('plus')}</button>
      <button id="edit-source" class="icon-button reading-control" title="编辑原文" aria-label="编辑原文">${icon('edit')}</button>
      <button id="preview" class="icon-button reading-control" title="预览" aria-label="预览">${icon('eye')}</button>
      <button id="export" class="primary reading-control">导出反馈${icon('arrow')}</button>
    </nav>
  </header>
  <main>
    <section id="paste-view" class="paste-view" aria-label="粘贴方案">
      <div class="paste-heading"><label for="source">方案原文</label><button id="sample" class="text-button">载入示例</button></div>
      <textarea id="source" placeholder="在这里粘贴 AI 生成的方案…" spellcheck="false"></textarea>
      <p id="edit-warning" class="warning" hidden>修改原文可能影响批注定位；无法匹配的批注会保留为“未定位”。</p>
      <div class="paste-footer"><span id="source-count" class="muted"></span><button id="start" class="primary">开始批注${icon('arrow')}</button></div>
    </section>
    <div id="read-view" class="workspace" hidden>
      <article id="article" class="article" aria-label="方案原文"></article>
      <aside id="panel" class="panel" aria-label="批注列表">
        <button id="panel-toggle" class="panel-toggle" aria-expanded="false" aria-controls="panel-body"><span class="handle" aria-hidden="true"></span><span id="panel-title">批注 (0)</span><span class="chevron" aria-hidden="true"></span></button>
        <div id="panel-body" class="panel-body">
          <ol id="comments" class="comments"></ol>
          <div class="general"><label for="general">总体意见 <span class="muted">（可选）</span></label><textarea id="general" rows="3" placeholder="补充总体意见…"></textarea></div>
        </div>
      </aside>
    </div>
  </main>
  <button id="annotate" class="primary annotate" hidden>${icon('comment')}批注</button>
  <dialog id="editor" aria-labelledby="editor-title">
    <form id="editor-form">
      <div class="dialog-heading"><h2 id="editor-title">添加批注</h2><button type="button" id="editor-close" class="icon-button" aria-label="取消" title="取消">${icon('close')}</button></div>
      <blockquote id="editor-quote"></blockquote>
      <label class="sr-only" for="comment-input">批注意见</label><textarea id="comment-input" placeholder="写下你的意见…" rows="5" required autofocus></textarea>
      <div class="dialog-actions"><button type="button" id="cancel">取消</button><button type="submit" class="primary">保存</button></div>
    </form>
  </dialog>
  <dialog id="export-dialog" aria-labelledby="export-title">
    <div class="dialog-heading"><h2 id="export-title">反馈预览</h2><button id="export-close" class="icon-button" aria-label="关闭" title="关闭">${icon('close')}</button></div>
    <label class="sr-only" for="export-text">反馈内容</label><textarea id="export-text" readonly></textarea>
    <p id="copy-hint" class="muted" hidden>请长按全选后复制</p>
    <div class="dialog-actions"><button id="copy-preview" class="primary">复制</button></div>
  </dialog>
  <div id="toast" class="toast" role="status" aria-live="polite" hidden></div>
`

let session = loadSession()
const source = get<HTMLTextAreaElement>('#source')
const article = get<HTMLElement>('#article')
const panel = get<HTMLElement>('#panel')
const general = get<HTMLTextAreaElement>('#general')
const annotate = get<HTMLButtonElement>('#annotate')
const editor = get<HTMLDialogElement>('#editor')
const commentInput = get<HTMLTextAreaElement>('#comment-input')
const exportDialog = get<HTMLDialogElement>('#export-dialog')
const exportText = get<HTMLTextAreaElement>('#export-text')
const mobile = window.matchMedia('(max-width: 899px)')
const touch = window.matchMedia('(pointer: coarse)')
let selected: Anchor | null = null
let editing: { id: string | null; anchor: Anchor } | null = null
let activeId: string | null = null
let selectionTimer = 0
let toastTimer = 0
let storageWarningShown = false
let returnFocus: HTMLElement | null = null

function toast(message: string): void {
  const element = get('#toast')
  element.textContent = message
  element.hidden = false
  window.clearTimeout(toastTimer)
  toastTimer = window.setTimeout(() => { element.hidden = true }, 3000)
}
function persist(): void {
  if (!saveSession(session) && !storageWarningShown) {
    storageWarningShown = true
    toast('无法保存到本机，请及时导出反馈')
  }
}
function setPanel(open: boolean): void {
  panel.classList.toggle('expanded', open)
  get('#panel-toggle').setAttribute('aria-expanded', String(open || !mobile.matches))
  get('#panel-body').inert = mobile.matches && !open
}
function clearSelection(): void {
  selected = null
  annotate.hidden = true
  window.clearTimeout(selectionTimer)
  window.getSelection()?.removeAllRanges()
}
function renderArticle(): void {
  renderMarkdown(article, session.source)
  reanchor(session.comments, article.textContent ?? '')
  wrapHighlights(article, session.comments)
}
function renderList(): void {
  const list = get<HTMLOListElement>('#comments')
  list.replaceChildren()
  const sorted = sortFeedback(session.comments)
  get('#panel-title').textContent = `批注 (${sorted.length})`
  sorted.forEach((item, index) => {
    const li = document.createElement('li')
    li.className = 'comment-card'
    li.dataset.id = item.id
    li.classList.toggle('active', activeId === item.id)
    const jump = document.createElement('button')
    jump.className = 'comment-jump'
    jump.title = item.located ? '定位原文' : '原文未定位'
    const number = document.createElement('span')
    number.className = 'comment-number'
    number.textContent = String(index + 1).padStart(2, '0')
    const quote = document.createElement('span')
    quote.className = 'comment-quote'
    quote.textContent = item.quote
    jump.append(number, quote)
    jump.addEventListener('click', () => focusComment(item.id, true))
    const body = document.createElement('p')
    body.className = 'comment-text'
    body.textContent = item.comment
    const actions = document.createElement('div')
    actions.className = 'comment-actions'
    if (!item.located) {
      const badge = document.createElement('span')
      badge.className = 'unlocated'
      badge.textContent = '未定位'
      actions.append(badge)
    }
    const edit = document.createElement('button')
    edit.className = 'icon-button'
    edit.title = '编辑批注'
    edit.setAttribute('aria-label', `编辑第 ${index + 1} 条批注`)
    edit.innerHTML = icon('edit')
    edit.addEventListener('click', () => openEditor(item))
    const remove = document.createElement('button')
    remove.className = 'icon-button delete-button'
    remove.title = '删除批注'
    remove.setAttribute('aria-label', `删除第 ${index + 1} 条批注`)
    remove.innerHTML = icon('trash')
    remove.addEventListener('click', () => {
      if (!window.confirm('删除这条批注？')) return
      session.comments = session.comments.filter((entry) => entry.id !== item.id)
      clearSelection()
      renderArticle()
      renderList()
      persist()
    })
    actions.append(edit, remove)
    li.addEventListener('click', (event) => {
      if (!(event.target as Element).closest('button')) focusComment(item.id, true)
    })
    li.append(jump, body, actions)
    list.append(li)
  })
}
function updateSourceState(): void {
  get<HTMLButtonElement>('#start').disabled = !source.value.trim()
  get('#source-count').textContent = source.value.length ? `${source.value.length.toLocaleString()} 字符` : ''
}
function renderStep(): void {
  const reading = session.step === 'read'
  document.body.classList.toggle('reading', reading)
  get('#paste-view').hidden = reading
  get('#read-view').hidden = !reading
  document.querySelectorAll<HTMLElement>('.reading-control').forEach((control) => { control.hidden = !reading })
  source.value = session.draft
  general.value = session.general
  get('#edit-warning').hidden = !session.comments.length
  updateSourceState()
  if (reading) { renderArticle(); renderList() }
  setPanel(false)
}
function focusComment(id: string, scrollArticle: boolean): void {
  activeId = id
  clearSelection()
  const item = session.comments.find((entry) => entry.id === id)
  if (!item) return
  const card = Array.from(get('#comments').children).find((node) => (node as HTMLElement).dataset.id === id) as HTMLElement | undefined
  get('#comments').querySelectorAll<HTMLElement>('.comment-card').forEach((node) => node.classList.toggle('active', node.dataset.id === id))
  if (scrollArticle && item.located) {
    if (mobile.matches) setPanel(false)
    const mark = Array.from(article.querySelectorAll<HTMLElement>('mark.hl')).find((node) => node.dataset.id === id)
    mark?.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' })
  } else {
    setPanel(true)
    if (card) {
      const scroller = get('#panel-body')
      scroller.scrollTo({ top: card.offsetTop - 12, behavior: 'smooth' })
      card.querySelector<HTMLButtonElement>('button')?.focus({ preventScroll: true })
    }
  }
  article.querySelectorAll<HTMLElement>('mark.hl').forEach((mark) => {
    if (mark.dataset.id !== id) return
    mark.classList.remove('flash')
    void mark.offsetWidth
    mark.classList.add('flash')
  })
}
function openEditor(item?: Feedback): void {
  const anchor = item ?? selected
  if (!anchor) return
  returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
  editing = { id: item?.id ?? null, anchor: { start: anchor.start, end: anchor.end, quote: anchor.quote } }
  get('#editor-title').textContent = item ? '编辑批注' : '添加批注'
  get('#editor-quote').textContent = anchor.quote
  commentInput.value = item?.comment ?? ''
  commentInput.setCustomValidity('')
  clearSelection()
  editor.showModal()
  document.body.classList.add('modal-open')
  // Synchronous focus keeps iOS keyboard activation in the user's tap gesture.
  commentInput.focus()
}
function closeEditor(): void { editor.close() }
editor.addEventListener('close', () => {
  editing = null
  document.body.classList.remove('modal-open')
  if (returnFocus?.isConnected && returnFocus !== annotate) returnFocus.focus({ preventScroll: true })
})
get('#editor-close').addEventListener('click', closeEditor)
get('#cancel').addEventListener('click', closeEditor)
get<HTMLFormElement>('#editor-form').addEventListener('submit', (event) => {
  event.preventDefault()
  if (!editing) return
  const comment = commentInput.value.trim()
  if (!comment) { commentInput.setCustomValidity('请输入批注意见'); commentInput.reportValidity(); return }
  const existing = session.comments.find((item) => item.id === editing?.id)
  if (existing) existing.comment = comment
  else {
    const id = globalThis.crypto?.randomUUID?.() ?? `comment-${Date.now()}-${Math.random().toString(36).slice(2)}`
    session.comments.push({ id, ...editing.anchor, comment, located: true })
    activeId = id
  }
  closeEditor()
  renderArticle()
  renderList()
  persist()
  toast(existing ? '批注已更新' : '批注已保存')
})
commentInput.addEventListener('input', () => commentInput.setCustomValidity(''))
commentInput.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && (event.ctrlKey || event.metaKey) && !event.isComposing) {
    event.preventDefault()
    get<HTMLFormElement>('#editor-form').requestSubmit()
  }
})

function positionAction(): void {
  if (!selected) return
  annotate.classList.toggle('touch-action', touch.matches || mobile.matches)
  if (touch.matches || mobile.matches) return
  const range = rangeFromOffsets(article, selected.start, selected.end)
  if (!range) return
  const rects = range.getClientRects()
  const rect = rects[rects.length - 1] ?? range.getBoundingClientRect()
  annotate.style.left = `${Math.max(12, Math.min(rect.left, window.innerWidth - 112))}px`
  annotate.style.top = `${Math.max(80, Math.min(rect.bottom + 10, window.innerHeight - 60))}px`
}
function captureSelection(): void {
  if (session.step !== 'read' || editor.open || exportDialog.open) return
  const anchor = selectionAnchor(article, window.getSelection())
  window.clearTimeout(selectionTimer)
  if (anchor) {
    // Capture immediately; native selection may collapse before the button's click.
    selected = anchor
    selectionTimer = window.setTimeout(() => {
      if (mobile.matches) setPanel(false)
      annotate.hidden = false
      positionAction()
    }, 80)
  } else selectionTimer = window.setTimeout(() => { annotate.hidden = true }, 180)
}
document.addEventListener('selectionchange', captureSelection)
article.addEventListener('pointerup', captureSelection)
article.addEventListener('touchend', captureSelection, { passive: true })
for (const event of ['pointerdown', 'mousedown']) {
  annotate.addEventListener(event, (e) => { e.preventDefault(); window.clearTimeout(selectionTimer) })
}
annotate.addEventListener('click', () => openEditor())
document.addEventListener('pointerdown', (event) => {
  const target = event.target as Node
  if (!article.contains(target) && !annotate.contains(target)) { selected = null; annotate.hidden = true }
})
window.addEventListener('scroll', positionAction, { passive: true })
window.addEventListener('resize', positionAction)
function activateHighlight(event: MouseEvent | KeyboardEvent): void {
  const target = (event.target as Element).closest<HTMLElement>('mark.hl')
  if (!target?.dataset.id) return
  if (event instanceof KeyboardEvent) {
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
  } else if (!window.getSelection()?.isCollapsed) return
  event.preventDefault()
  focusComment(target.dataset.id, false)
}
article.addEventListener('click', activateHighlight)
article.addEventListener('keydown', activateHighlight)
get('#panel-toggle').addEventListener('click', () => {
  if (mobile.matches) setPanel(!panel.classList.contains('expanded'))
})
mobile.addEventListener('change', () => setPanel(panel.classList.contains('expanded')))
let handleY = 0
get('#panel-toggle').addEventListener('touchstart', (event) => { handleY = event.touches[0]?.clientY ?? 0 }, { passive: true })
get('#panel-toggle').addEventListener('touchend', (event) => {
  const delta = (event.changedTouches[0]?.clientY ?? handleY) - handleY
  if (Math.abs(delta) > 25 && mobile.matches) { event.preventDefault(); setPanel(delta < 0) }
}, { passive: false })

source.addEventListener('input', () => { session.draft = source.value; updateSourceState(); persist() })
get('#sample').addEventListener('click', () => {
  if (source.value.trim() && !window.confirm('用示例替换当前输入的原文？')) return
  source.value = sample
  session.draft = sample
  updateSourceState()
  persist()
})
get('#start').addEventListener('click', () => {
  if (!source.value.trim()) return
  session.source = source.value
  session.draft = source.value
  session.step = 'read'
  renderStep()
  persist()
  window.scrollTo(0, 0)
})
get('#edit-source').addEventListener('click', () => {
  clearSelection()
  session.step = 'paste'
  session.draft = session.source
  renderStep()
  persist()
  window.scrollTo(0, 0)
})
get('#new').addEventListener('click', () => {
  if ((session.comments.length || session.general.trim()) && !window.confirm('新建将清空原文和所有批注，确定继续？')) return
  clearSelection()
  session = emptySession()
  activeId = null
  renderStep()
  persist()
  window.scrollTo(0, 0)
})
general.addEventListener('input', () => { session.general = general.value; persist() })

function showPreview(manual = false): void {
  exportText.value = formatFeedback(session.comments, session.general)
  get('#copy-hint').hidden = !manual
  if (!exportDialog.open) exportDialog.showModal()
  document.body.classList.add('modal-open')
  if (manual) { exportText.focus(); exportText.select(); exportText.setSelectionRange(0, exportText.value.length) }
}
function legacyCopy(text: string): boolean {
  const field = document.createElement('textarea')
  field.value = text
  field.readOnly = true
  field.className = 'clipboard-helper'
  // A modal makes the rest of the document inert; copy from within it when open.
  ;(exportDialog.open ? exportDialog : document.body).append(field)
  const previous = document.activeElement as HTMLElement | null
  field.focus()
  field.select()
  field.setSelectionRange(0, text.length)
  let success = false
  try { success = document.execCommand('copy') } catch { /* Manual fallback below. */ }
  field.remove()
  previous?.focus({ preventScroll: true })
  return success
}
async function copyFeedback(): Promise<void> {
  const hasGeneral = Boolean(session.general.trim())
  if (!session.comments.length && !hasGeneral) { toast('还没有批注'); return }
  const text = formatFeedback(session.comments, session.general)
  let copied = false
  try {
    if (navigator.clipboard?.writeText) { await navigator.clipboard.writeText(text); copied = true }
  } catch { /* Try the synchronous legacy API next. */ }
  if (!copied) copied = legacyCopy(text)
  if (copied) {
    if (exportDialog.open) exportDialog.close()
    toast(`已复制 ${session.comments.length} 条批注${hasGeneral ? '（含总体意见）' : ''}`)
    get('#copy-hint').hidden = true
  }
  else showPreview(true)
}
get('#export').addEventListener('click', () => { void copyFeedback() })
get('#preview').addEventListener('click', () => showPreview())
get('#copy-preview').addEventListener('click', () => { void copyFeedback() })
get('#export-close').addEventListener('click', () => exportDialog.close())
exportDialog.addEventListener('close', () => document.body.classList.remove('modal-open'))

// Keep modal actions visible above the iOS software keyboard.
function syncViewport(): void {
  const viewport = window.visualViewport
  document.documentElement.style.setProperty('--viewport-height', `${viewport?.height ?? window.innerHeight}px`)
  document.documentElement.style.setProperty('--viewport-top', `${viewport?.offsetTop ?? 0}px`)
}
window.visualViewport?.addEventListener('resize', syncViewport)
window.visualViewport?.addEventListener('scroll', syncViewport)
window.addEventListener('resize', syncViewport)
syncViewport()
renderStep()
if (session.step === 'read') persist()
