import { marked } from 'marked';
import DOMPurify from 'dompurify';
export interface Annotation { id: string; quote: string; comment: string; start: number; end: number }
export interface Agent { id: string; name: string; webhook: string }
export function renderMarkdown(raw: string): string {
  // Raw HTML is shown as text. Images are omitted to avoid unsolicited remote requests.
  const renderer = new marked.Renderer();
  renderer.html = ({text}) => text.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
  renderer.image = ({text}) => `[图片：${text.replaceAll('<','&lt;').replaceAll('>','&gt;')}]`;
  return DOMPurify.sanitize(marked.parse(raw, {renderer, async:false, gfm:true}) as string, {FORBID_TAGS:['img','iframe','style','input'], FORBID_ATTR:['style']});
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
export function makePayload(document:string, annotations:Annotation[], generalFeedback:string, agentName:string, submissionId:string=crypto.randomUUID()) {
  const sorted=[...annotations].sort((a,b)=>a.start-b.start);
  const summary='以下是我对你方案的逐条反馈，请据此修改出下一版：'+sorted.map((a,i)=>`\n\n${i+1}. 原文：\n> ${a.quote.replaceAll('\n','\n> ')}\n意见：${a.comment}`).join('')+(generalFeedback.trim()?`\n\n总体意见：${generalFeedback.trim()}`:'');
  return {protocolVersion:1,submissionId,agentName,document,annotations:sorted.map(a=>({...a})),generalFeedback,submittedAt:new Date().toISOString(),summary};
}
