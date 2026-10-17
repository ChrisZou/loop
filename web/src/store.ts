import type { Feedback } from './export'

export interface Session {
  source: string
  draft: string
  comments: Feedback[]
  general: string
  step: 'paste' | 'read'
}

const KEY = 'loop.session.v1'
export const emptySession = (): Session => ({ source: '', draft: '', comments: [], general: '', step: 'paste' })

function isFeedback(value: unknown): value is Feedback {
  if (!value || typeof value !== 'object') return false
  const item = value as Partial<Feedback>
  return typeof item.id === 'string' && typeof item.quote === 'string' &&
    typeof item.comment === 'string' && typeof item.located === 'boolean' &&
    typeof item.start === 'number' && Number.isSafeInteger(item.start) && item.start >= 0 &&
    typeof item.end === 'number' && Number.isSafeInteger(item.end) && item.end >= item.start
}

export function loadSession(): Session {
  try {
    const data: unknown = JSON.parse(localStorage.getItem(KEY) ?? 'null')
    if (!data || typeof data !== 'object') return emptySession()
    const value = data as Partial<Session>
    return {
      source: typeof value.source === 'string' ? value.source : '',
      draft: typeof value.draft === 'string' ? value.draft : typeof value.source === 'string' ? value.source : '',
      comments: Array.isArray(value.comments) ? value.comments.filter(isFeedback) : [],
      general: typeof value.general === 'string' ? value.general : '',
      step: value.step === 'read' && value.source ? 'read' : 'paste',
    }
  } catch { return emptySession() }
}

export function saveSession(session: Session): boolean {
  try {
    localStorage.setItem(KEY, JSON.stringify(session))
    return true
  } catch { return false }
}
