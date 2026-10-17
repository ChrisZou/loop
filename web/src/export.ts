export interface Feedback {
  id: string
  start: number
  end: number
  quote: string
  comment: string
  located: boolean
}

export function sortFeedback(items: readonly Feedback[]): Feedback[] {
  return [...items].sort((a, b) => {
    if (a.located !== b.located) return a.located ? -1 : 1
    return a.start - b.start || a.end - b.end
  })
}

export function formatFeedback(items: readonly Feedback[], general = ''): string {
  const sections = ['以下是我对你方案的逐条反馈，请据此修改出下一版：']
  sortFeedback(items).forEach((item, index) => {
    const quote = item.quote.trim().replace(/\r\n?/g, '\n').replace(/\n/g, '\n   > ')
    const comment = item.comment.trim().replace(/\r\n?/g, '\n').replace(/\n/g, '\n   ')
    sections.push(`${index + 1}. 原文：> ${quote}\n   意见：${comment}`)
  })
  if (general.trim()) sections.push(`总体意见：${general.trim()}`)
  return sections.join('\n\n')
}
