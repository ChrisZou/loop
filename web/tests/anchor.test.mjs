import test from 'node:test'
import assert from 'node:assert/strict'
import { normalizeQuote, reanchor } from '../src/anchor.ts'

const item = (quote, start = 0, end = quote.length) => ({ id: 'test', quote, start, end, comment: '意见', located: true })

test('normalizes whitespace while preserving Chinese and emoji', () => {
  assert.equal(normalizeQuote(' 方案\n\t  ✅  '), '方案 ✅')
})
test('keeps valid offsets, even when an earlier identical quote exists', () => {
  const comment = item('原文', 3, 5)
  reanchor([comment], '原文 原文')
  assert.equal(comment.start, 3)
  assert.equal(comment.end, 5)
  assert.equal(comment.located, true)
})
test('reanchors shifted quotes against normalized whitespace and UTF-16 offsets', () => {
  const comment = item('方案 ✅ 完成')
  const text = '前言\n方案\n\t✅   完成\n尾注'
  reanchor([comment], text)
  assert.equal(comment.located, true)
  assert.equal(comment.start, 3)
  assert.equal(normalizeQuote(text.slice(comment.start, comment.end)), comment.quote)
})
test('retains missing comments and recovers them if text returns', () => {
  const comment = item('原来的一段')
  reanchor([comment], '全新文档')
  assert.equal(comment.located, false)
  assert.equal(comment.quote, '原来的一段')
  assert.equal(comment.comment, '意见')
  reanchor([comment], '前言：原来的一段')
  assert.equal(comment.located, true)
  assert.equal(comment.start, 3)
})
test('an empty quote cannot accidentally match an empty document', () => {
  const comment = item('')
  reanchor([comment], '')
  assert.equal(comment.located, false)
})
