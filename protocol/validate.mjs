// Shared Webhook v1 structural and business validation. Quotes are display references, not verified DOM anchors.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function validatePayload(p) {
  if (!p || Array.isArray(p) || typeof p !== 'object') return 'Expected JSON object';
  if(p.protocolVersion!==1 || !uuid.test(p.submissionId)) return 'Invalid protocol or submissionId';
  if(!['agentName','document','generalFeedback','submittedAt','summary'].every(k=>typeof p[k]==='string')) return 'Missing string fields';
  if(!p.agentName.trim() || !/^\d{4}-\d\d-\d\dT/.test(p.submittedAt) || !Number.isFinite(Date.parse(p.submittedAt))) return 'Invalid agent or timestamp';
  const hasReview=Object.hasOwn(p,'reviewId'),hasRevision=Object.hasOwn(p,'revision');
  if(hasReview!==hasRevision || (hasReview && (typeof p.reviewId!=='string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(p.reviewId) || !Number.isInteger(p.revision) || p.revision<1 || p.revision>1000)))return 'reviewId and revision must be a valid pair';
  if(!Array.isArray(p.annotations)) return 'Missing annotations';
  let previousEnd=0; const ids=new Set();
  for(const a of p.annotations) {
    if(!a || typeof a.id!=='string' || !a.id || ids.has(a.id) || typeof a.quote!=='string' || !a.quote.trim() || typeof a.comment!=='string' || !a.comment.trim()) return 'Invalid annotation';
    if(!Number.isSafeInteger(a.start)||!Number.isSafeInteger(a.end)||a.start<previousEnd||a.end<=a.start||a.end-a.start!==a.quote.length) return 'Invalid, unsorted or overlapping offsets';
    previousEnd=a.end; ids.add(a.id);
  }
  if(Object.hasOwn(p,'checks')){
    if(!Array.isArray(p.checks)||p.checks.length>200) return 'Invalid checks';
    for(const c of p.checks) if(!c||typeof c!=='object'||Object.keys(c).some(k=>!['text','checked'].includes(k))||typeof c.text!=='string'||!c.text.trim()||c.text.length>5000||typeof c.checked!=='boolean') return 'Invalid checks';
  }
  const checks=Array.isArray(p.checks)?p.checks:[];
  const tasks=checks.length?'\n\n待办的勾选状态改为：'+checks.map(c=>`\n- [${c.checked?'x':' '}] ${c.text.trim()}`).join(''):'';
  const summary='以下是我对你方案的逐条反馈，请据此修改出下一版：'+p.annotations.map((a,i)=>`\n\n${i+1}. 原文：\n> ${a.quote.replaceAll('\n','\n> ')}\n意见：${a.comment}`).join('')+tasks+(p.generalFeedback.trim()?`\n\n总体意见：${p.generalFeedback.trim()}`:'');
  if(p.summary!==summary) return 'Summary does not match annotations';
  return null;
}
