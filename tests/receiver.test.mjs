import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createReceiver,validatePayload} from '../examples/receiver.mjs';
const payload={protocolVersion:1,submissionId:'00000000-0000-4000-8000-000000000001',agentName:'本地测试',document:'你好🧭',annotations:[{id:'a',quote:'你好🧭',comment:'请说明方向',start:0,end:4}],generalFeedback:'',submittedAt:'2026-10-18T00:00:00Z',summary:'以下是我对你方案的逐条反馈，请据此修改出下一版：\n\n1. 原文：\n> 你好🧭\n意见：请说明方向'};
test('business validation: UTF-16, malformed payload, overlaps, summary',()=>{
 assert.equal(validatePayload(payload),null);
 for(const bad of [null,[],{...payload,protocolVersion:2},{...payload,annotations:[{...payload.annotations[0],end:3}]},{...payload,summary:'bad'},{...payload,annotations:[...payload.annotations,...payload.annotations]}])assert.ok(validatePayload(bad));
});
test('local receiver preflight, auth, invalid JSON, acceptance and deduplication',async()=>{
 let count=0;const server=createReceiver({token:'test-only-token',onAccept:()=>count++});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}/webhook`;
 try {
  let r=await fetch(url,{method:'OPTIONS',headers:{Origin:'http://localhost:5173','Access-Control-Request-Headers':'authorization,content-type'}});assert.equal(r.status,204);assert.equal(r.headers.get('access-control-allow-origin'),'http://localhost:5173');
  r=await fetch(url,{method:'OPTIONS',headers:{Origin:'https://untrusted.invalid'}});assert.equal(r.status,403);
  const post=(body,auth=true)=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer test-only-token'}:{})},body});
  assert.equal((await post(JSON.stringify(payload),false)).status,401);
  assert.equal((await post('{')).status,400);
  r=await post(JSON.stringify(payload));assert.equal(r.status,202);assert.equal((await r.json()).agentStarted,false);
  r=await post(JSON.stringify(payload));assert.equal((await r.json()).duplicate,true);assert.equal(count,1);
  assert.equal((await post(JSON.stringify({...payload,agentName:'another'}))).status,409);
 } finally {server.closeAllConnections();await new Promise(r=>server.close(r));}
});
test('deterministic Chinese duplicate-text fixture remains valid',async()=>{
 const {readFile}=await import('node:fs/promises');const fixture=JSON.parse(await readFile(new URL('../protocol/fixture.json',import.meta.url),'utf8'));
 assert.equal(validatePayload(fixture.payload),null);
 for(const a of fixture.payload.annotations){assert.equal(fixture.canonicalText.slice(a.start,a.end),a.quote);assert.notEqual(fixture.canonicalText.indexOf(a.quote),a.start);}
});
test('optional private inbox persists atomically, deduplicates after restart and rejects conflicts',async()=>{
 const fs=await import('node:fs/promises'),os=await import('node:os'),path=await import('node:path');
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'loop-inbox-test-'));const inbox=path.join(dir,'inbox');
 let server;
 const open=async()=>{server=createReceiver({inboxDir:inbox});await new Promise(r=>server.listen(0,'127.0.0.1',r));return `http://127.0.0.1:${server.address().port}/webhook`;};
 const close=async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));};
 const post=(url,p)=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)});
 try{
  let url=await open();let r=await post(url,payload);assert.equal(r.status,202);assert.equal((await r.json()).persisted,true);
  const file=path.join(inbox,`${payload.submissionId}.json`);assert.deepEqual(JSON.parse(await fs.readFile(file,'utf8')),payload);
  assert.deepEqual(await fs.readdir(inbox),[`${payload.submissionId}.json`]);
  if(process.platform!=='win32'){assert.equal((await fs.stat(file)).mode&0o777,0o600);assert.equal((await fs.stat(inbox)).mode&0o777,0o700);}
  await close();url=await open();r=await post(url,payload);assert.equal((await r.json()).duplicate,true);
  assert.equal((await post(url,{...payload,agentName:'changed'})).status,409);
  assert.equal((await post(url,{...payload,submissionId:'../unsafe'})).status,400);
 }finally{await close();await fs.rm(dir,{recursive:true,force:true});}
});
test('optional immutable review metadata requires a lowercase UUID and paired revision 1..1000',()=>{
 const reviewId='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
 assert.equal(validatePayload(payload),null);
 for(const revision of [1,2,1000])assert.equal(validatePayload({...payload,reviewId,revision}),null);
 for(const context of [{reviewId},{revision:1},{reviewId:null,revision:1},{reviewId,revision:null},{reviewId:'../review',revision:1},{reviewId:reviewId.toUpperCase(),revision:1},{reviewId,revision:0},{reviewId,revision:-1},{reviewId,revision:1001},{reviewId,revision:1.5},{reviewId,revision:'1'},{reviewId,revision:Number.MAX_SAFE_INTEGER},{reviewId:undefined,revision:undefined}])assert.ok(validatePayload({...payload,...context}),JSON.stringify(context));
});
test('HTTP receiver and inbox retain valid review context, reject malformed pairs',async()=>{
 const fs=await import('node:fs/promises'),os=await import('node:os'),path=await import('node:path');
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'loop-context-test-'));
 const server=createReceiver({inboxDir:dir});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const url=`http://127.0.0.1:${server.address().port}/webhook`;
 const post=p=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)});
 try{
  const enriched={...payload,reviewId:'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',revision:2};
  assert.equal((await post({...payload,revision:2})).status,400);
  assert.equal((await post(enriched)).status,202);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(dir,`${payload.submissionId}.json`),'utf8')),enriched);
  assert.equal((await post({...enriched,revision:3})).status,409);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));await fs.rm(dir,{recursive:true,force:true});}
});
