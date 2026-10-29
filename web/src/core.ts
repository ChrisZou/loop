import { marked } from 'marked';
import DOMPurify from 'dompurify';
export interface Annotation { id: string; quote: string; comment: string; start: number; end: number }
export interface Agent { id: string; name: string; webhook: string }
export interface Task { index: number; text: string; checked: boolean }
export function renderMarkdown(raw: string): string {
  // Raw HTML is shown as text. Images load lazily and without a referrer; DOMPurify still drops unsafe URLs.
  const renderer = new marked.Renderer();
  let tasks = 0;
  renderer.html = ({text}) => text.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
  // Only http(s) and inline raster images are sources; anything else keeps its alt text as plain text.
  renderer.image = ({href, text}) => {
    const safe = /^(https?:|data:image\/(png|jpe?g|gif|webp|avif);base64,)/i.test(href);
    if (!safe) return text;
    const escape = (value: string) => value.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
    return `<img src="${escape(href)}" alt="${escape(text)}" loading="lazy" referrerpolicy="no-referrer">`;
  };
  // A `- [ ]` item renders as a toggle the reviewer can click; it carries no text node, so anchors stay put.
  renderer.listitem = function (item) {
    if (!item.task) return `<li>${this.parser.parse(item.tokens)}</li>\n`;
    // The `[ ]` token carries the box's own text; the span replaces it.
    const index = tasks++;
    return `<li class="task"><span class="task-check" role="checkbox" tabindex="0" aria-checked="${item.checked}" data-task="${index}" data-checked="${item.checked}"></span>${this.parser.parse(item.tokens.filter(t => t.type !== 'checkbox'))}</li>\n`;
  };
  return DOMPurify.sanitize(marked.parse(raw, {renderer, async:false, gfm:true}) as string, {
    FORBID_TAGS:['iframe','style','input'], FORBID_ATTR:['style'],
    ADD_ATTR:['loading','referrerpolicy','data-task','data-checked','aria-checked','tabindex']
  });
}
/** The task items a rendered document shows, in order. */
export function documentTasks(root: HTMLElement): Task[] {
  return [...root.querySelectorAll<HTMLElement>('.task-check')].map((box, i) => {
    const item = box.closest('li');
    return { index: i, text: (item?.textContent ?? '').replace(/\s+/g, ' ').trim(), checked: box.getAttribute('data-checked') === 'true' };
  });
}
export function textNodes(root: Node): Text[] {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {acceptNode(n) {
    return (n.parentElement?.closest('[data-marker]')) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
  }});
  const nodes: Text[] = []; let n; while ((n=walker.nextNode())) nodes.push(n as Text); return nodes;
}
export function canonicalText(root: Node): string { return textNodes(root).map(n=>n.data).join(''); }
export function rangeOffsets(root: HTMLElement, range: Range): {start:number;end:number;quote:string}|null {
  if (!root.contains(range.startContainer) || !root.contains(range.endContainer) || range.collapsed) return null;
  const point = (container: Node, offset:number) => {
    const r=document.createRange(); r.selectNodeContents(root); r.setEnd(container,offset);
    return canonicalText(r.cloneContents()).length;
  };
  const start=point(range.startContainer,range.startOffset), end=point(range.endContainer,range.endOffset);
  const quote=canonicalText(root).slice(start,end);
  return quote.trim() ? {start,end,quote}:null;
}
export function overlaps(a: {start:number;end:number}, b: {start:number;end:number}) { return a.start < b.end && b.start < a.end; }
export function paintAnnotations(root: HTMLElement, annotations: Annotation[]) {
  const sorted=[...annotations].sort((a,b)=>a.start-b.start);
  const nodes=textNodes(root); let pos=0;
  for (const node of nodes) {
    const start=pos, end=pos+node.length; pos=end;
    const hits=sorted.filter(a=>a.start<end && a.end>start); if (!hits.length) continue;
    const fragment=document.createDocumentFragment(); let cursor=0;
    for (const a of hits) {
      const from=Math.max(0,a.start-start), to=Math.min(node.length,a.end-start);
      fragment.append(node.data.slice(cursor,from));
      const mark=document.createElement('mark'); mark.dataset.annotation=a.id; mark.textContent=node.data.slice(from,to); fragment.append(mark);
      if (a.end<=end) {
        const button=document.createElement('button'); button.type='button'; button.dataset.marker='true'; button.dataset.annotation=a.id;
        button.className='annotation-pin'; button.textContent=String(sorted.indexOf(a)+1); button.setAttribute('aria-label',`批注 ${sorted.indexOf(a)+1}：${a.comment}`); fragment.append(button);
      }
      cursor=to;
    }
    fragment.append(node.data.slice(cursor)); node.replaceWith(fragment);
  }
}
export function validateWebhook(value:string): string|null {
  try { const url=new URL(value); if(url.hash) return '地址不能包含片段（#）'; if(url.username||url.password) return '地址不能包含用户名或密码';
    if(url.protocol==='https:') return null;
    if(url.protocol==='http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname)) return null;
    return '请使用 HTTPS，或本机 localhost HTTP 地址';
  } catch { return '请输入有效的 Webhook 地址'; }
}
export interface CheckedTask { text: string; checked: boolean }
/** The submitted summary: comments in document order, then the tasks the reviewer changed, then the general note. */
export function makePayload(document:string, annotations:Annotation[], generalFeedback:string, agentName:string, submissionId:string=crypto.randomUUID(), checks:CheckedTask[]=[]) {
  const sorted=[...annotations].sort((a,b)=>a.start-b.start);
  const changed=checks.filter(c=>c.text.trim());
  const tasks=changed.length?`\n\n待办的勾选状态改为：`+changed.map(c=>`\n- [${c.checked?'x':' '}] ${c.text.trim()}`).join(''):'';
  const summary='以下是我对你方案的逐条反馈，请据此修改出下一版：'+sorted.map((a,i)=>`\n\n${i+1}. 原文：\n> ${a.quote.replaceAll('\n','\n> ')}\n意见：${a.comment}`).join('')+tasks+(generalFeedback.trim()?`\n\n总体意见：${generalFeedback.trim()}`:'');
  return {protocolVersion:1,submissionId,agentName,document,annotations:sorted.map(a=>({...a})),checks:changed.map(c=>({text:c.text.trim(),checked:c.checked})),generalFeedback,submittedAt:new Date().toISOString(),summary};
}
