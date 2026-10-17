import test from 'node:test'
import assert from 'node:assert/strict'
import { formatFeedback, sortFeedback } from '../src/export.ts'

const item = (start, quote, comment, located = true) => ({ id: String(start), start, end: start + quote.length, quote, comment, located })
const header = '以下是我对你方案的逐条反馈，请据此修改出下一版：'

test('exact format, document ordering, and general feedback', () => {
  const comments = [item(20, '后面的原文', '第二条意见'), item(0, '前面的原文', '第一条意见')]
  assert.equal(formatFeedback(comments, '  请简化方案  '), `${header}\n\n1. 原文：> 前面的原文\n   意见：第一条意见\n\n2. 原文：> 后面的原文\n   意见：第二条意见\n\n总体意见：请简化方案`)
  assert.equal(comments[0].start, 20, 'sorting must not mutate persisted order')
})
test('multiline quotes and comments including CRLF', () => {
  assert.equal(formatFeedback([item(0, '第一行\r\n第二行\n第三行', '意见一\r\n意见二\n\n意见三')]), `${header}\n\n1. 原文：> 第一行\n   > 第二行\n   > 第三行\n   意见：意见一\n   意见二\n   \n   意见三`)
})
test('empty general is omitted and empty sessions are supported', () => {
  assert.equal(formatFeedback([], ' \n '), header)
  assert.equal(formatFeedback([], '只保留核心功能'), `${header}\n\n总体意见：只保留核心功能`)
})
test('overlapping ranges and unlocated comments remain in export', () => {
  const items = [item(0, '丢失原文', '保留意见', false), item(8, '内部', '意见二'), item(2, '外部范围', '意见一')]
  assert.deepEqual(sortFeedback(items).map(({ start }) => start), [2, 8, 0])
  assert.match(formatFeedback(items), /3\. 原文：> 丢失原文\n   意见：保留意见$/)
})
test('user text stays literal, including markdown and punctuation', () => {
  assert.equal(formatFeedback([item(0, '<tag> **文本**', '保留 `code`：✅')]), `${header}\n\n1. 原文：> <tag> **文本**\n   意见：保留 \`code\`：✅`)
})
