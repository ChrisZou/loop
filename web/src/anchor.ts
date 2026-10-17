import type { Feedback } from './export'

export interface Anchor { start: number; end: number; quote: string }
export const normalizeQuote = (text: string): string => text.replace(/\s+/g, ' ').trim()

function textNodes(root: Node): Text[] {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  const nodes: Text[] = []
  let node: Node | null
  while ((node = walker.nextNode())) nodes.push(node as Text)
  return nodes
}

const BLOCK = 'p,li,h1,h2,h3,h4,h5,h6,pre,blockquote,td,th,dt,dd,figcaption,div'
const squash = (text: string): string => text.replace(/\s+/g, '')

/** Quote text that keeps block boundaries (paragraphs, list items, headings, code lines) as newlines. */
export function blockQuote(root: HTMLElement, start: number, end: number): string {
  const lines: string[] = []
  let current = ''
  let block: Element | null = null
  let position = 0
  for (const node of textNodes(root)) {
    const nodeStart = position
    position += node.length
    const from = Math.max(0, start - nodeStart)
    const to = Math.min(node.length, end - nodeStart)
    if (from >= to) continue
    const piece = node.data.slice(from, to)
    if (!piece.trim()) continue
    const owner = node.parentElement?.closest(BLOCK) ?? null
    if (owner !== block) {
      if (current.trim()) lines.push(current)
      current = ''
      block = owner
    }
    current += piece
  }
  if (current.trim()) lines.push(current)
  return lines
    .flatMap((line) => line.split('\n'))
    .map((line) => line.replace(/[ \t\f\v\u00a0\u3000]+/g, ' ').trim())
    .filter(Boolean)
    .join('\n')
}

function offsetAt(root: HTMLElement, node: Node, offset: number): number {
  const prefix = document.createRange()
  prefix.selectNodeContents(root)
  prefix.setEnd(node, offset)
  return textNodes(prefix.cloneContents()).reduce((sum, text) => sum + text.length, 0)
}

export function selectionAnchor(root: HTMLElement, selection: Selection | null): Anchor | null {
  if (!selection || selection.isCollapsed || !selection.rangeCount) return null
  const range = selection.getRangeAt(0)
  if (!root.contains(range.startContainer) || !root.contains(range.endContainer)) return null
  const start = offsetAt(root, range.startContainer, range.startOffset)
  const end = offsetAt(root, range.endContainer, range.endOffset)
  const quote = blockQuote(root, start, end)
  return quote && end > start ? { start, end, quote } : null
}

export function rangeFromOffsets(root: HTMLElement, start: number, end: number): Range | null {
  if (start < 0 || end <= start) return null
  const range = document.createRange()
  let position = 0
  let foundStart = false
  for (const node of textNodes(root)) {
    const next = position + node.length
    if (!foundStart && start < next) {
      range.setStart(node, start - position)
      foundStart = true
    }
    if (foundStart && end <= next) {
      range.setEnd(node, end - position)
      return range
    }
    position = next
  }
  return null
}

export function reanchor(items: Feedback[], text: string): void {
  // Map normalized UTF-16 offsets back to the original textContent offsets.
  const normalized: string[] = []
  const starts: number[] = []
  const ends: number[] = []
  for (let i = 0; i < text.length; i++) {
    const character = text[i]!
    if (/\s/.test(character)) {
      if (normalized.at(-1) === ' ') ends[ends.length - 1] = i + 1
      else { normalized.push(' '); starts.push(i); ends.push(i + 1) }
    } else { normalized.push(character); starts.push(i); ends.push(i + 1) }
  }
  const searchable = normalized.join('')
  for (const item of items) {
    const quote = normalizeQuote(item.quote)
    if (quote && item.end <= text.length && squash(text.slice(item.start, item.end)) === squash(item.quote)) {
      item.located = true
      continue
    }
    const exact = text.indexOf(item.quote)
    const match = quote ? searchable.indexOf(quote) : -1
    if (quote && exact !== -1) {
      item.start = exact
      item.end = exact + item.quote.length
      item.located = true
    } else if (match !== -1) {
      item.start = starts[match]!
      item.end = ends[match + quote.length - 1]!
      item.located = true
    } else item.located = false
  }
}

export function wrapHighlights(root: HTMLElement, items: readonly Feedback[]): void {
  // Called on freshly rendered markdown. Text-node splitting never changes textContent.
  for (const item of items) {
    if (!item.located) continue
    let position = 0
    for (const node of textNodes(root)) {
      const nodeStart = position
      position += node.length
      const start = Math.max(0, item.start - nodeStart)
      const end = Math.min(node.length, item.end - nodeStart)
      if (start >= end) continue
      // Whitespace between block elements (e.g. inside <ul>/<table>) must stay unwrapped.
      if (!node.data.slice(start, end).trim()) continue
      if (end < node.length) node.splitText(end)
      const segment = start > 0 ? node.splitText(start) : node
      const mark = document.createElement('mark')
      mark.className = 'hl'
      mark.dataset.id = item.id
      mark.tabIndex = 0
      mark.setAttribute('role', 'button')
      mark.setAttribute('aria-label', `查看批注：${item.comment}`)
      segment.before(mark)
      mark.append(segment)
    }
  }
}
