import {clampPosition} from './viewport';
import './style.css';
import {renderMarkdown,canonicalText,rangeOffsets,paintAnnotations,overlaps,validateWebhook,makePayload, type Annotation,type Agent} from './core';
const sample=`# 让每一轮反馈，都更进一步

这是你的审阅空间。**选中任何一段文字**，把具体想法留在原文旁边。完成后，将反馈送回你的 Agent。

## 一个更轻盈的工作流

1. 粘贴 Agent 给出的 Markdown 方案
2. 选中文字，点击「批注」或按 Alt + Enter
3. 写下修改建议，提交给下一轮

> 好的反馈从具体的原文开始。无需来回切换，也无需重新解释上下文。

## 这次，我们关注什么？

| 方向 | 期待的变化 |
| --- | --- |
| 清晰度 | 让每个步骤都能直接行动 |
| 体验 | 保留必要信息，减少干扰 |
| 交付 | 让反馈变成下一版的起点 |

### 技术约定

\`\`\`json
{ "status": "ready", "next": "your feedback" }
\`\`\`

准备好了？选中一句话，开始第一条批注。
`;
const hosted=(window as Window & {LOOP_HOSTED?:boolean}).LOOP_HOSTED===true;
const demo=!hosted && (window as Window & {LOOP_DEMO?:boolean}).LOOP_DEMO===true;
const sameOriginMode=hosted || demo;
// Keep hosted traffic on this origin, including redirects; never forward session capabilities cross-origin.
const sessionTransport:RequestInit={mode:'same-origin',credentials:'same-origin',redirect:'follow',referrerPolicy:'same-origin'};
const sessionAgent:Agent={id:hosted?'loop-hosted':'loop-demo',name:hosted?'当前会话':'当前对话收件箱（演示）',webhook:new URL('/api/feedback',location.origin).href};
interface ReviewContext { reviewId:string; title:string; agentName:string; revision:number; createdAt:string; parentReviewId:string|null }
interface State { review?:ReviewContext; document:string; annotations:Annotation[]; generalFeedback:string; agents:Agent[]; selected:string }
const initial:State={document:hosted?'':sample,annotations:[],generalFeedback:'',agents:[],selected:''};
let state:State=initial;
try {const saved=JSON.parse(localStorage.getItem('loop.v1')||'null'); if(saved && typeof saved.document==='string' && Array.isArray(saved.annotations)&&Array.isArray(saved.agents)) state={...initial,...saved};}catch{}
// Validate browser storage as untrusted input, including stale anchor positions.
state.agents=state.agents.filter((a:any)=>a && typeof a.id==='string' && typeof a.name==='string' && typeof a.webhook==='string');
if(typeof state.generalFeedback!=='string')state.generalFeedback='';
if(typeof state.selected!=='string')state.selected='';
const restored=document.createElement('div');restored.innerHTML=renderMarkdown(state.document);const restoredText=canonicalText(restored);
const valid:Annotation[]=[];
for(const a of state.annotations){if(a && typeof a.id==='string' && typeof a.quote==='string' && typeof a.comment==='string' && Number.isInteger(a.start) && Number.isInteger(a.end) && a.start>=0 && a.end>a.start && a.end<=restoredText.length && restoredText.slice(a.start,a.end)===a.quote && !valid.some(b=>b.id===a.id||overlaps(a,b)))valid.push(a);}
state.annotations=valid;
if(hosted && state.document===sample && !state.annotations.length && !state.generalFeedback.trim())state.document='';
if(state.review && (typeof state.review.reviewId!=='string'||typeof state.review.title!=='string'||typeof state.review.agentName!=='string'||!Number.isInteger(state.review.revision)||state.review.revision<1||state.review.revision>1000||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(state.review.reviewId)))delete state.review;
const linkedMode=hosted || demo && (new URL(location.href).searchParams.has('review') || !!state.review);
if(sameOriginMode)state.selected=sessionAgent.id;
const availableAgents=()=>sameOriginMode?[sessionAgent,...state.agents.filter(a=>a.id!==sessionAgent.id)]:state.agents;
const keys=new Map<string,string>(); // Keys deliberately live only in this page's memory.
let pending:ReturnType<typeof rangeOffsets>=null, editingId:string|null=null, submitting=false;
interface Drafts { markdown:string|null; comment:null }
let drafts:Drafts={markdown:null,comment:null};
try {const d=JSON.parse(localStorage.getItem('loop.drafts.v1')||'null');if(d){if(typeof d.markdown==='string')drafts.markdown=d.markdown;if(d.comment!==undefined&&d.comment!==null)localStorage.setItem('loop.drafts.v1',JSON.stringify(drafts));}}catch{}
let saveFailed=false;
type SubmissionPayload=ReturnType<typeof makePayload>&{reviewId?:string;revision?:number};
let retrySubmission:{fingerprint:string;payload:SubmissionPayload}|null=null;
try{const r=JSON.parse(localStorage.getItem('loop.pending.v1')||'null');if(r&&typeof r.fingerprint==='string'&&r.payload&&typeof r.payload.submissionId==='string'&&typeof r.payload.submittedAt==='string')retrySubmission=r;}catch{}
function submissionSnapshot(agent:Agent):SubmissionPayload{
 const candidate={...makePayload(state.document,state.annotations,state.generalFeedback,state.review?.agentName??agent.name),...(state.review?{reviewId:state.review.reviewId,revision:state.review.revision}:{})};
 const {submissionId:_,submittedAt:__,...content}=candidate;
 const fingerprint=JSON.stringify({endpoint:agent.webhook,content});
 const priorContent=retrySubmission?(({submissionId,submittedAt,...rest})=>rest)(retrySubmission.payload):null;
 if(retrySubmission?.fingerprint!==fingerprint||JSON.stringify(priorContent)!==JSON.stringify(content))retrySubmission={fingerprint,payload:candidate};
 // Reuse the entire snapshot, including its timestamp, so backend deduplication is exact.
 try{localStorage.setItem('loop.pending.v1',JSON.stringify(retrySubmission));}catch{}
 return retrySubmission.payload;
}
function saveDrafts(){try{localStorage.setItem('loop.drafts.v1',JSON.stringify(drafts));}catch{announce('草稿无法保存到此设备，请勿关闭页面。',true);}showDrafts();}
function showDrafts(){const notice=document.querySelector<HTMLElement>('#draft-notice');if(!notice)return;notice.hidden=drafts.markdown===null;document.querySelector<HTMLElement>('#restore-markdown')!.hidden=drafts.markdown===null;}


function save(){try{localStorage.setItem('loop.v1',JSON.stringify(state));saveFailed=false;}catch{saveFailed=true;} document.querySelector('#save-state')!.textContent=saveFailed?'存储不可用 · 请勿关闭页面':'';if(saveFailed)announce('存储不可用，请勿关闭页面。',true);}
const app=document.querySelector<HTMLDivElement>('#app')!;
app.innerHTML=`<header><a class="brand" href="#" aria-label="Loop 首页"><span class="logo">↻</span> Loop<span class="brand-note">反馈，让想法向前</span></a><div class="header-actions"><button id="new" class="quiet">新建</button><button id="settings" class="quiet">设置</button><div class="submit-group"><select id="agent-select" aria-label="目标 Agent"></select><button id="submit" class="primary">提交 <span>↗</span></button></div></div></header>
<main><div class="intro"><div><div class="eyebrow">HUMAN IN THE LOOP</div><h1>想法的下一版，从你开始。</h1><p>在原文里留下反馈，让 Agent 接着往前走。</p></div><span class="private-badge">◈ 仅保存在此设备</span></div><div id="review-context" class="review-context" hidden></div><div id="review-load" class="draft-notice" hidden role="status"><span id="review-load-text"></span><button id="retry-review" hidden>重新打开收到的方案</button></div><div id="draft-notice" class="draft-notice" hidden><span>有尚未应用的草稿，已自动保存</span><button id="restore-markdown">继续编辑原文</button><button id="discard-drafts" class="quiet">放弃草稿</button></div><section class="workspace"><div class="document-toolbar"><div class="tabs"><button id="read-tab" class="active">审阅</button><button id="edit-tab">Markdown</button></div><div class="document-meta"><span id="count">0 条批注</span><span class="separator">·</span><span id="save-state">已自动保存到此设备</span></div></div><div class="reading-hint"><span>⌁</span> 选中文字即可批注 <kbd>Alt ↵</kbd><span class="hint-end">你的思考，留在原处</span></div><article id="document" class="markdown" aria-label="待审阅文档"></article><section id="editor-panel" hidden><label for="markdown-input">粘贴或编辑 Markdown</label><p>修改原文会清除现有批注，以免位置错配。取消编辑可保留原文与批注。</p><textarea id="markdown-input" spellcheck="false"></textarea><div class="editor-actions"><button id="cancel-edit">放弃修改</button><button id="apply-edit" class="primary">应用修改</button></div></section><section class="general"><label for="general-feedback">总体意见</label><textarea id="general-feedback" placeholder="" rows="3"></textarea></section></section><footer><span>Loop · 让反馈回到创作中</span><span>选中 · 批注 · 下一版</span></footer><div id="status" role="status" aria-live="polite"></div></main>
<button id="selection-action" class="floating primary" hidden>＋ 批注</button>
<div id="comment-popover" class="popover" hidden role="dialog" aria-label="原文批注"><div class="popover-top"><strong id="comment-title">添加批注</strong><button id="close-comment" aria-label="关闭批注">×</button></div><blockquote id="quote"></blockquote><label for="comment-input" class="sr-only">批注内容</label><textarea id="comment-input" rows="4" placeholder="你希望如何修改？"></textarea><div class="popover-actions"><button id="delete-comment" class="danger" hidden>删除</button><button id="save-comment" class="primary">保存批注</button></div></div>
<dialog id="settings-dialog"><form id="settings-form"><div class="dialog-head"><div><div class="eyebrow">YOUR AGENTS</div><h2>连接你的 Agent</h2></div><button type="button" id="close-settings" aria-label="关闭设置">×</button></div><p>提交时，将原文与反馈发送到你选择的 Webhook。</p><div id="agent-rows"></div><button type="button" id="add-agent">＋ 添加 Agent</button><div class="security-note">密钥仅保留在当前页面内存中，刷新或关闭后需重新填写。Webhook 地址和名称保存在此设备，请勿将密钥写入 URL。</div><details><summary>连接与 CORS 说明</summary><p>接收端需允许此网页来源的 POST / OPTIONS 请求及 Content-Type、Authorization 请求头。HTTPS 网页访问 localhost HTTP 可能被浏览器拦截。建议使用可信 HTTPS 接口或同源代理。</p><p>只有点击「提交」才会发起请求。HTTP 2xx 表示接口已接收，不代表 Agent 已完成处理。超时后请确认接收端状态，避免重复提交。</p></details><p id="settings-error" role="alert"></p><div class="dialog-actions"><button type="submit" class="primary">保存设置</button></div></form></dialog>`;
const $=<T extends HTMLElement=HTMLElement>(s:string)=>document.querySelector<T>(s)!;
if(linkedMode){for(const selector of ['#new','#settings','#agent-select','#edit-tab','#read-tab']){const el=$(selector) as HTMLButtonElement;el.hidden=true;el.disabled=true;}$('.document-toolbar').hidden=true;app.classList.add('linked-review');}
const doc=$('#document'), action=$<HTMLButtonElement>('#selection-action'), pop=$('#comment-popover');
function announce(text:string,error=false){$('#status').textContent=text;$('#status').classList.toggle('error',error);}
function draw(){drawReviewContext();doc.innerHTML=renderMarkdown(state.document);paintAnnotations(doc,state.annotations);doc.querySelectorAll('a').forEach(a=>{a.target='_blank';a.rel='noopener noreferrer';});$('#count').textContent=`${state.annotations.length} 条批注`;}
function drawAgents(){if(linkedMode)state.selected=sessionAgent.id;const agents=availableAgents();const select=$<HTMLSelectElement>('#agent-select');select.replaceChildren();if(!agents.length) select.add(new Option('选择 Agent',''));agents.forEach(a=>select.add(new Option(a.id===sessionAgent.id?'当前会话':a.name,a.id))); if(!agents.some(a=>a.id===state.selected))state.selected=agents[0]?.id||'';select.value=state.selected;}
function hidePendingSelection(){action.hidden=true;if(pop.hidden){pending=null;pendingRect=null;keptPendingAfterCalloutClear=false;}}
function discardCommentDraft(){drafts.comment=null;saveDrafts();closePopover();}
function closePopover(){$<HTMLTextAreaElement>('#comment-input').value='';pop.hidden=true;editingId=null;pending=null;pendingRect=null;keptPendingAfterCalloutClear=false;action.hidden=true;}
let popAnchor={left:12,bottom:102}, pendingRect:{left:number;top:number;bottom:number}|null=null;
let selectingByTouch=false, dismissCalloutAfterCapture=false, keptPendingAfterCalloutClear=false;
function place(el:HTMLElement,rect:{left:number;bottom:number;top?:number}){const vv=window.visualViewport, box={width:vv?.width??innerWidth,height:vv?.height??innerHeight,left:vv?.offsetLeft??0,top:vv?.offsetTop??0};if(el===pop){popAnchor=rect;el.style.maxWidth=`${Math.max(0,box.width-24)}px`;el.style.maxHeight=`${Math.max(0,box.height-24)}px`;el.style.overflow='auto';}const size={width:el.offsetWidth||(el===pop?340:100),height:el.offsetHeight||(el===pop?320:48)};const pos=clampPosition(rect,size,box,el===action?{preferAbove:true}:undefined);el.style.left=`${pos.left}px`;el.style.top=`${pos.top}px`;}
function repositionPopover(){if(!pop.hidden)place(pop,popAnchor);}
function focusComment(){$<HTMLTextAreaElement>('#comment-input').focus();requestAnimationFrame(()=>{if(pop.hidden)return;pop.scrollIntoView?.({block:'nearest',inline:'nearest'});repositionPopover();});}
function captureSelection(){
 // touchstart→touchend: never clear the live range; handles must stay adjustable.
 if(!pop.hidden||selectingByTouch)return;const selection=window.getSelection();
 if(!selection?.rangeCount || selection.isCollapsed){
  // After we cleared the native range to dismiss iOS callout, keep ＋批注 from pending offsets/quote.
  // A real user collapse (no keptPending flag) still dismisses the floating button.
  if(keptPendingAfterCalloutClear && pending){
   if(pendingRect)place(action,pendingRect);
   action.hidden=false;return;
  }
  hidePendingSelection();return;
 }
 const r=selection.getRangeAt(0),anchor=rangeOffsets(doc,r);if(!anchor){hidePendingSelection();return;}
 const rect=r.getBoundingClientRect();
 keptPendingAfterCalloutClear=false;
 pending=anchor;pendingRect={left:rect.left,top:rect.top,bottom:rect.bottom};
 place(action,pendingRect);action.hidden=false;
 if(dismissCalloutAfterCapture){
  const forAnchor=anchor;
  // After touch settles: clear native selection only (no DOM text wrap) to dismiss iOS Copy/Look Up callout.
  // Do not use mark.temp-selection — wrapping text nodes previously broke Safari selection handles.
  requestAnimationFrame(()=>{requestAnimationFrame(()=>{
   if(selectingByTouch||pending!==forAnchor)return;
   keptPendingAfterCalloutClear=true;
   window.getSelection()?.removeAllRanges();
   if(pending===forAnchor && pendingRect){place(action,pendingRect);action.hidden=false;}
  });});
 }
}
document.addEventListener('selectionchange',captureSelection);
doc.addEventListener('contextmenu',e=>e.preventDefault());
doc.addEventListener('touchstart',()=>{selectingByTouch=true;dismissCalloutAfterCapture=true;},{passive:true});
doc.addEventListener('touchend',()=>{selectingByTouch=false;/* let Safari finalize selection before capture + delayed clear */setTimeout(captureSelection,50);});
doc.addEventListener('touchcancel',()=>{selectingByTouch=false;dismissCalloutAfterCapture=false;hidePendingSelection();});
document.addEventListener('pointerdown',e=>{if((e as PointerEvent).pointerType!=='touch')dismissCalloutAfterCapture=false;},true);
function dismissOnBlank(e:Event){
 const target=e.target as Element;
 if(!doc.contains(target) || target.closest('[data-annotation],#selection-action,#comment-popover,a,button,input,textarea,select,label,summary,[contenteditable],[role="button"]'))return;
 if(!pop.hidden){discardCommentDraft();}else hidePendingSelection();
}
doc.addEventListener('pointerdown',dismissOnBlank);
doc.addEventListener('click',dismissOnBlank);
action.addEventListener('pointerdown',e=>e.preventDefault());
function openNew(){if(!pending)return;if(state.annotations.some(a=>overlaps(a,pending!))){announce('这段文字已包含批注。请点击已有编号编辑，或选择不重叠的文字。',true);return;}editingId=null;$('#comment-title').textContent='添加批注';$('#quote').textContent=pending.quote;$<HTMLTextAreaElement>('#comment-input').value='';$('#delete-comment').hidden=true;pop.hidden=false;place(pop,action.getBoundingClientRect());action.hidden=true;focusComment();}
action.onclick=openNew;
document.addEventListener('keydown',e=>{if(e.altKey&&e.key==='Enter'){e.preventDefault();if(pop.hidden){captureSelection();openNew();}else saveComment();}if(e.key==='Escape'){discardCommentDraft();}});
function openExisting(id:string,target:HTMLElement,focus=false){const a=state.annotations.find(a=>a.id===id);if(!a)return;editingId=id;pending=null;$('#comment-title').textContent='编辑批注';$('#quote').textContent=a.quote;$<HTMLTextAreaElement>('#comment-input').value=a.comment;$('#delete-comment').hidden=false;pop.hidden=false;action.hidden=true;place(pop,target.getBoundingClientRect());if(focus)focusComment();}
doc.addEventListener('click',e=>{const t=(e.target as HTMLElement).closest<HTMLElement>('[data-annotation]');if(t)openExisting(t.dataset.annotation!,t,true);});
doc.addEventListener('pointerover',e=>{if(e.pointerType==='touch'||!pop.hidden)return;const t=(e.target as HTMLElement).closest<HTMLElement>('[data-marker]');if(t)openExisting(t.dataset.annotation!,t);});
$('#close-comment').onclick=()=>{discardCommentDraft();};
function saveComment(){const comment=$<HTMLTextAreaElement>('#comment-input').value.trim();if(!comment){announce('请先写下批注内容。',true);return;}if(editingId){state.annotations=state.annotations.map(a=>a.id===editingId?{...a,comment}:a);}else if(pending){state.annotations.push({...pending,id:crypto.randomUUID(),comment});}else return;drafts.comment=null;saveDrafts();closePopover();window.getSelection()?.removeAllRanges();draw();save();announce('');}
$('#save-comment').onclick=saveComment;
$('#delete-comment').onclick=()=>{drafts.comment=null;saveDrafts();state.annotations=state.annotations.filter(a=>a.id!==editingId);closePopover();draw();save();announce('');};
$<HTMLTextAreaElement>('#general-feedback').value=state.generalFeedback;
$('#general-feedback').addEventListener('input',e=>{state.generalFeedback=(e.target as HTMLTextAreaElement).value;save();});
$('#agent-select').addEventListener('change',e=>{state.selected=linkedMode?sessionAgent.id:(e.target as HTMLSelectElement).value;save();});
function editor(open:boolean){discardCommentDraft();doc.hidden=open;$('#editor-panel').hidden=!open;$('.reading-hint').hidden=open;$('#read-tab').classList.toggle('active',!open);$('#edit-tab').classList.toggle('active',open);if(open)$<HTMLTextAreaElement>('#markdown-input').value=drafts.markdown??state.document;}
$('#edit-tab').onclick=()=>{if(!linkedMode)editor(true);};$('#read-tab').onclick=()=>editor(false);$('#cancel-edit').onclick=()=>{drafts.markdown=null;saveDrafts();editor(false);};
$('#markdown-input').addEventListener('input',()=>{drafts.markdown=$<HTMLTextAreaElement>('#markdown-input').value;saveDrafts();});
$('#apply-edit').onclick=()=>{if(hosted){announce('方案原文不可修改，请放弃原文草稿。',true);return;}const next=$<HTMLTextAreaElement>('#markdown-input').value;if(next!==state.document){if(state.annotations.length&&!confirm('应用修改将清除所有原文批注（保留总体意见）。继续吗？'))return;state.document=next;delete state.review;const manualUrl=new URL(location.href);manualUrl.searchParams.delete('review');history.replaceState(null,'',manualUrl);state.annotations=[];drafts.comment=null;save();draw();}drafts.markdown=null;saveDrafts();editor(false);};
$('#new').onclick=()=>{if(linkedMode)return;if(submitting){announce('正在提交，请等待结果后再新建。',true);return;}if(!confirm('新建会清空当前原文、批注和总体意见。Agent 设置保留。继续吗？'))return;drafts={markdown:null,comment:null};saveDrafts();closePopover();delete state.review;const cleanUrl=new URL(location.href);cleanUrl.searchParams.delete('review');history.replaceState(null,'',cleanUrl);state.document='';state.annotations=[];state.generalFeedback='';$<HTMLTextAreaElement>('#general-feedback').value='';draw();save();editor(true);};
let draftAgents:Agent[]=[];
function drawSettings(){const rows=$('#agent-rows');rows.replaceChildren();draftAgents.forEach((a,i)=>{const row=document.createElement('div');row.className='agent-row';row.innerHTML=`<div class="row-heading"><strong>Agent ${i+1}</strong><button type="button" class="remove danger">移除</button></div><label>名称<input class="agent-name" required maxlength="80" placeholder="如：方案助手"></label><label>Webhook URL<input class="agent-url" type="url" required placeholder="https://example.com/feedback"></label><label>密钥 <span>可选 · 仅本次页面</span><input class="agent-key" type="password" autocomplete="off" placeholder="以 Bearer Token 发送"></label>`;row.querySelector<HTMLInputElement>('.agent-name')!.value=a.name;row.querySelector<HTMLInputElement>('.agent-url')!.value=a.webhook;row.querySelector<HTMLInputElement>('.agent-key')!.value=draftKeys.get(a.id)||'';row.querySelector('.remove')!.addEventListener('click',()=>{readSettings();draftAgents.splice(i,1);drawSettings();});rows.append(row);});}
let draftKeys=new Map<string,string>();
function readSettings(){[...$('#agent-rows').children].forEach((row,i)=>{draftAgents[i].name=row.querySelector<HTMLInputElement>('.agent-name')!.value.trim();draftAgents[i].webhook=row.querySelector<HTMLInputElement>('.agent-url')!.value.trim();draftKeys.set(draftAgents[i].id,row.querySelector<HTMLInputElement>('.agent-key')!.value);});}
$('#settings').onclick=()=>{if(linkedMode)return;draftAgents=state.agents.map(a=>({...a}));draftKeys=new Map(keys);$('#settings-error').textContent='';drawSettings();$<HTMLDialogElement>('#settings-dialog').showModal();};
$('#close-settings').onclick=()=>$<HTMLDialogElement>('#settings-dialog').close();
$('#add-agent').onclick=()=>{readSettings();draftAgents.push({id:crypto.randomUUID(),name:'',webhook:''});drawSettings();};
$('#settings-form').onsubmit=e=>{e.preventDefault();readSettings();for(const a of draftAgents){const error=validateWebhook(a.webhook);if(!a.name||error){$('#settings-error').textContent=error||'请输入 Agent 名称';return;}}state.agents=draftAgents.map(a=>({...a}));keys.clear();draftKeys.forEach((v,k)=>{if(state.agents.some(a=>a.id===k))keys.set(k,v);});drawAgents();save();$<HTMLDialogElement>('#settings-dialog').close();announce('Agent 设置已保存。'+(state.agents.some(a=>a.webhook.startsWith('http:'))?' 本机 HTTP 无加密，请仅用于本地调试。':''));};
$('#submit').onclick=async()=>{if(submitting)return;if(hosted&&(!state.review||(incomingReview&&state.review.reviewId!==incomingReview))){announce('请先打开需要审阅的方案。',true);return;}if(!pop.hidden){announce('请先保存或关闭正在编辑的批注，再提交。',true);return;}if(!$('#editor-panel').hidden){announce('请先应用或取消 Markdown 修改。',true);return;}if(drafts.markdown!==null&&drafts.markdown!==state.document){announce('还有未应用的原文草稿，请继续编辑并应用或放弃修改后再提交。',true);return;}const agent=linkedMode?sessionAgent:availableAgents().find(a=>a.id===state.selected);if(!agent){$('#settings').click();return;}const invalid=validateWebhook(agent.webhook);if(invalid){announce(invalid,true);return;}if(!state.document.trim()){announce('请先添加需要审阅的 Markdown 原文。',true);return;}if(!state.annotations.length&&!state.generalFeedback.trim()){announce('请至少添加一条批注或总体意见。',true);return;}
  const payload=submissionSnapshot(agent);const key=keys.get(agent.id);submitting=true;const button=$<HTMLButtonElement>('#submit');button.disabled=true;button.textContent='提交中…';announce('');const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),15000);
  let stage='建立提交会话';
  try {const isSession=sameOriginMode && agent.id===sessionAgent.id && new URL(agent.webhook).origin===location.origin;const sessionHeaders:Record<string,string>={};if(isSession){const sessionResponse=await fetch('/api/session',{...sessionTransport,method:'POST',signal:controller.signal});if(!sessionResponse.ok)throw new Error(`提交会话不可用（HTTP ${sessionResponse.status}），可能已过期或达到限额`);const sessionData=await sessionResponse.json();if(typeof sessionData.session!=='string'||!sessionData.session)throw new Error('提交会话响应无效');sessionHeaders['X-Loop-Session']=sessionData.session;}stage='发送反馈';const response=await fetch(isSession?'/api/feedback':agent.webhook,{method:'POST',headers:{'Content-Type':'application/json',...sessionHeaders,...(!isSession&&key?{Authorization:`Bearer ${key}`}:{})},body:JSON.stringify(payload),signal:controller.signal,...(isSession?sessionTransport:{redirect:'error' as const,credentials:'omit' as const,referrerPolicy:'no-referrer' as const})});if(!response.ok)throw new Error(`接收端返回 HTTP ${response.status}`);if(isSession){stage='核对提交回执';const receipt=await response.json();if(receipt.accepted!==true||receipt.submissionId!==payload.submissionId)throw new Error('提交回执无效，状态未确认');finishSubmission(payload.reviewId??null,receipt.submissionId);}else finishSubmission(payload.reviewId??null,payload.submissionId);}catch(error){const timedOut=controller.signal.aborted;announce(timedOut?'提交超时，接收状态未知。内容已保留，请确认后重试。':`提交未确认（${stage}）：${error instanceof Error?error.message:'网络错误'}。${saveFailed?'内容仍在当前页面，请勿关闭或刷新。':'内容已保留在此设备，可重试。'}`,true);}finally{clearTimeout(timer);submitting=false;button.disabled=false;button.innerHTML='提交 <span>↗</span>';}
};
window.addEventListener('resize',()=>{hidePendingSelection();repositionPopover();});window.addEventListener('scroll',hidePendingSelection,true);
window.visualViewport?.addEventListener('resize',repositionPopover);window.visualViewport?.addEventListener('scroll',repositionPopover);
$('#restore-markdown').onclick=()=>editor(true);

$('#discard-drafts').onclick=()=>{if(!confirm('放弃尚未应用的原文草稿？已保存的原文与批注会保留。'))return;drafts={markdown:null,comment:null};saveDrafts();closePopover();editor(false);};
if(demo){const warning=document.createElement('p');warning.className='demo-warning';warning.textContent='公开临时演示 · 无需登录，请仅使用虚构测试内容，勿填写隐私或密钥。收到的方案链接可被任何持有链接的人打开；反馈保存在后台，不提供公开读取。原文草稿与已保存批注保存在此浏览器；点击提交后，原文和反馈将提交到当前会话的临时存储，不会自动启动 Agent。演示有效至 2026-10-20 08:30 UTC。';document.querySelector('#settings-dialog details')!.append(warning);document.querySelector('.private-badge')!.textContent='草稿本地 · 提交云端';}
function drawReviewContext(){const el=$('#review-context');el.hidden=!state.review;if(state.review)el.textContent=`${state.review.title} · 来自 ${state.review.agentName} · 第 ${state.review.revision} 版`;}
const incomingReview=sameOriginMode?new URL(location.href).searchParams.get('review'):null;
let loadingReview=false;
async function loadIncomingReview(){
 if(!incomingReview||loadingReview)return;
 const notice=$('#review-load'),label=$('#review-load-text'),retry=$('#retry-review');notice.hidden=false;retry.hidden=true;
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(incomingReview)){label.textContent='收到的方案链接无效。当前内容未改动。';return;}
 if(state.review?.reviewId===incomingReview){notice.hidden=true;return;}
 loadingReview=true;label.textContent='加载中…';const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),15000);
 try{const response=await fetch(`/api/reviews/${encodeURIComponent(incomingReview)}`,{...sessionTransport,signal:controller.signal});if(!response.ok)throw new Error(`HTTP ${response.status}`);const review=await response.json();if(review.reviewId!==incomingReview||typeof review.document!=='string'||review.document.length>30000||typeof review.title!=='string'||typeof review.agentName!=='string'||!Number.isInteger(review.revision)||review.revision<1||review.revision>1000)throw new Error('方案数据无效');
 if(new URL(location.href).searchParams.get('review')!==incomingReview){notice.hidden=true;return;}
 const dirty=(state.document!==sample && state.document.trim()!=='')||state.annotations.length>0||state.generalFeedback.trim()!==''||drafts.markdown!==null||!pop.hidden||!$('#editor-panel').hidden;
 if(dirty&&!confirm(`打开「${review.title}」第 ${review.revision} 版将替换当前原文、批注、总体意见和草稿。当前内容不会自动发送。是否切换？`)){label.textContent='未切换方案';retry.hidden=false;return;}
 closePopover();drafts={markdown:null,comment:null};saveDrafts();state.document=review.document;state.annotations=[];state.generalFeedback='';state.review={reviewId:review.reviewId,title:review.title,agentName:review.agentName,revision:review.revision,createdAt:typeof review.createdAt==='string'?review.createdAt:'',parentReviewId:typeof review.parentReviewId==='string'?review.parentReviewId:null};$<HTMLTextAreaElement>('#general-feedback').value='';draw();save();editor(false);notice.hidden=true;
 }catch(error){label.textContent=`无法加载收到的方案：${controller.signal.aborted?'请求超时':error instanceof Error?error.message:'网络错误'}。当前内容已保留。`;retry.hidden=false;}finally{clearTimeout(timer);loadingReview=false;}
}
$('#retry-review').onclick=()=>void loadIncomingReview();
function finishSubmission(reviewId:string|null,submissionId:string){try{sessionStorage.setItem('loop.completed.v1',JSON.stringify({reviewId,submissionId}));}catch{}showCompletion();try{window.close();}catch{}}
function showCompletion(){app.innerHTML='<main class="completion" role="status"><span>已提交</span></main>';}
let alreadyCompleted=false;try{const c=JSON.parse(sessionStorage.getItem('loop.completed.v1')||'null');alreadyCompleted=!!c && c.reviewId===(incomingReview||state.review?.reviewId||null);}catch{}
if(alreadyCompleted)showCompletion();else{draw();drawAgents();save();showDrafts();void loadIncomingReview();}
