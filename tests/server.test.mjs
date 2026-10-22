import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, stat, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { createLoopServer } from '../server/index.mjs';

const token = 'test-agent-token';
const agentHeaders = { Authorization:`Bearer ${token}` };
const proposal = { title:'生产方案', agentName:'ElonBot', document:'# 方案\n\n原始 Markdown 🧭' };
const prefix = '以下是我对你方案的逐条反馈，请据此修改出下一版：';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
function payload(review, changes={}) {
  return { protocolVersion:1, submissionId:randomUUID(), agentName:review.agentName, document:review.document, annotations:[], generalFeedback:'补充验证', submittedAt:new Date().toISOString(), summary:prefix+'\n\n总体意见：补充验证', reviewId:review.reviewId, revision:review.revision, ...changes };
}
async function fixture(t, options={}) {
  const dir = await mkdtemp(join(tmpdir(),'loop-server-'));
  const webDist = join(dir,'web'), dataDir = join(dir,'data'), webhooksFile = join(dir,'webhooks.json');
  await mkdir(webDist);await writeFile(join(webDist,'index.html'),'<html><head><title>Loop</title></head><body><script type="module" src="/app.js"></script></body></html>');
  await writeFile(join(webDist,'app.js'),'window.test=true;');
  const config = { agentToken:token, dataDir, webDist, webhooksFile, publicUrl:'https://loop.example', deliveryIntervalMs:20, ...options };
  let server, url;
  async function start() { server=await createLoopServer(config);await new Promise(r=>server.listen(0,'127.0.0.1',r));url=`http://127.0.0.1:${server.address().port}`; }
  async function stop() { if(server?.listening)await server.stop(); }
  t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
  await start();
  const get=(path,headers={})=>fetch(url+path,{headers});
  const post=(path,body,headers={})=>fetch(url+path,{method:'POST',headers:{'Content-Type':'application/json',...headers},body:body===undefined?undefined:JSON.stringify(body)});
  const create=async(body=proposal)=>{const r=await post('/api/reviews',body,agentHeaders);assert.equal(r.status,201);return r.json();};
  const session=async()=>{const r=await post('/api/session');assert.equal(r.status,200);return {'X-Loop-Session':(await r.json()).session};};
  const poll=async id=>(await get(`/api/reviews/${id}/feedback`,agentHeaders)).json();
  return {dir,webDist,dataDir,webhooksFile,get,post,create,session,poll,start,stop,config,get url(){return url;}};
}
async function until(fn) { for(let n=0;n<300;n++){const result=await fn();if(result)return result;await sleep(20);}throw new Error('Condition did not settle'); }
async function mock(t, handler) {
  const server=http.createServer(handler);await new Promise(r=>server.listen(0,'127.0.0.1',r));
  t.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));});
  return `http://127.0.0.1:${server.address().port}/hook`;
}

test('required configuration, agent auth, public health/static with hosted injection and safe paths',async t=>{
  await assert.rejects(createLoopServer({agentToken:''}),/LOOP_AGENT_TOKEN/);
  const f=await fixture(t);
  assert.deepEqual(await (await f.get('/api/health')).json(),{ok:true});
  for(const authorization of [undefined,'Bearer wrong','Bearer test-agent-tokeN','Basic test-agent-token']) {
    assert.equal((await f.post('/api/reviews',proposal,authorization?{Authorization:authorization}:{})).status,401);
  }
  const session=await f.session();assert.equal((await f.post('/api/reviews',proposal,session)).status,401);
  for(const path of ['/','/?review='+randomUUID(),'/deep/link']) {
    const res=await f.get(path);assert.equal(res.status,200);const html=await res.text();
    assert.ok(html.indexOf('window.LOOP_HOSTED=true')<html.indexOf('type="module"'));assert.ok(!html.includes(token));
    assert.equal(res.headers.get('cache-control'),'no-store');
  }
  assert.equal(await (await f.get('/app.js')).text(),'window.test=true;');
  assert.equal((await fetch(f.url+'/',{method:'HEAD'})).status,200);
  await writeFile(join(f.dir,'private.txt'),'private');await symlink(join(f.dir,'private.txt'),join(f.webDist,'escape.txt'));
  for(const path of ['/escape.txt','/%2e%2e%2fprivate.txt','/.env','/api/missing'])assert.equal((await f.get(path)).status,404);
  assert.equal((await f.post('/api/session',undefined,{Origin:'https://attacker.example'})).status,403);
  assert.equal((await f.post('/api/session',undefined,{'Sec-Fetch-Site':'cross-site'})).status,403);
});

test('immutable public review create/get, revision lineage, field limits and valid IDs',async t=>{
  const f=await fixture(t), first=await f.create();
  assert.match(first.reviewId,uuid);assert.equal(first.revision,1);assert.equal(first.parentReviewId,null);
  assert.equal(first.reviewUrl,`https://loop.example/?review=${first.reviewId}`);
  const {reviewUrl,...stored}=first;assert.deepEqual(await (await f.get('/api/reviews/'+first.reviewId)).json(),stored);
  const next=await f.create({...proposal,parentReviewId:first.reviewId,document:'下一版'});
  assert.equal(next.revision,2);assert.equal(next.parentReviewId,first.reviewId);assert.notEqual(next.reviewId,first.reviewId);
  assert.equal((await f.get('/api/reviews')).status,401);
  assert.equal((await f.get('/api/reviews/not-a-uuid')).status,400);
  assert.equal((await f.get('/api/reviews/'+first.reviewId.toUpperCase())).status,400);
  assert.equal((await f.get('/api/reviews/'+randomUUID())).status,404);
  assert.equal((await f.post('/api/reviews/'+first.reviewId,proposal,agentHeaders)).status,405);
  for(const change of [{title:''},{title:'a'.repeat(121)},{agentName:' '},{agentName:'a'.repeat(101)},{document:'a'.repeat(30001)},{parentReviewId:null},{parentReviewId:'../escape'},{extra:true}])assert.equal((await f.post('/api/reviews',{...proposal,...change},agentHeaders)).status,400);
  assert.equal((await f.post('/api/reviews',{...proposal,parentReviewId:randomUUID()},agentHeaders)).status,404);
  await writeFile(join(f.dataDir,'reviews',first.reviewId+'.json'),JSON.stringify({...stored,revision:1000}));
  assert.equal((await f.post('/api/reviews',{...proposal,parentReviewId:first.reviewId},agentHeaders)).status,400);
});

test('feedback validates session, schema, exact review document/revision/agent; bounds JSON and chunked bodies',async t=>{
  const f=await fixture(t),review=await f.create(),p=payload(review),session=await f.session();
  assert.equal((await f.post('/api/feedback',p)).status,403);
  assert.equal((await f.post('/api/feedback',p,agentHeaders)).status,403);
  for(const change of [{reviewId:undefined},{revision:undefined},{submissionId:'../escape'},{reviewId:'../escape'},{summary:'incorrect'},{extra:'field'},{annotations:[{id:'a',quote:'wrong',comment:'why',start:0,end:2}]}])assert.equal((await f.post('/api/feedback',{...p,...change},session)).status,400);
  for(const change of [{document:'changed'},{revision:2},{reviewId:randomUUID()},{agentName:'Another agent'}])assert.equal((await f.post('/api/feedback',{...p,...change},session)).status,409);
  assert.equal((await fetch(f.url+'/api/feedback',{method:'POST',headers:{...session,'Content-Type':'application/json'},body:'{'})).status,400);
  assert.equal((await fetch(f.url+'/api/feedback',{method:'POST',headers:session,body:'{}'})).status,415);
  assert.equal((await f.post('/api/feedback',{...p,document:'x'.repeat(1024*1024)},session)).status,413);
  const status=await new Promise((resolve,reject)=>{
    const req=http.request(f.url+'/api/feedback',{method:'POST',headers:{...session,'Content-Type':'application/json','Transfer-Encoding':'chunked'}},res=>{res.resume();resolve(res.statusCode);});req.on('error',reject);req.write('x'.repeat(1024*1024));req.end('overflow');
  });assert.equal(status,413);
  assert.equal((await f.poll(review.reviewId)).feedback.length,0);
});

test('atomic persistence and authenticated polling survive restart, concurrent duplicates and conflicts',async t=>{
  const f=await fixture(t),review=await f.create(),p=payload(review),session=await f.session();
  const responses=await Promise.all(Array.from({length:8},()=>f.post('/api/feedback',p,session)));
  for(const response of responses)assert.equal(response.status,202);
  const receipts=await Promise.all(responses.map(r=>r.json()));assert.equal(receipts.filter(r=>!r.duplicate).length,1);
  assert.equal((await f.get(`/api/reviews/${review.reviewId}/feedback`)).status,401);
  assert.equal((await f.get(`/api/reviews/${review.reviewId}/feedback`,{Authorization:'Bearer incorrect'})).status,401);
  await until(async()=>{const list=(await f.poll(review.reviewId)).feedback;return list.length===1&&list[0].delivery.status==='skipped';});
  const record=(await f.poll(review.reviewId)).feedback[0];assert.deepEqual(record.payload,p);
  const file=join(f.dataDir,'feedback',p.submissionId+'.json');assert.deepEqual(JSON.parse(await readFile(file,'utf8')),record);
  assert.equal((await stat(file)).mode&0o777,0o600);assert.equal((await stat(join(f.dataDir,'feedback'))).mode&0o777,0o700);
  assert.deepEqual(await readdir(join(f.dataDir,'feedback')),[p.submissionId+'.json']);
  await f.stop();await f.start();
  assert.equal((await f.post('/api/feedback',p,session)).status,403);
  const newSession=await f.session();assert.equal((await (await f.post('/api/feedback',p,newSession)).json()).duplicate,true);
  const changed=payload(review,{submissionId:p.submissionId,generalFeedback:'新意见',summary:prefix+'\n\n总体意见：新意见'});
  assert.equal((await f.post('/api/feedback',changed,newSession)).status,409);
  assert.deepEqual((await f.poll(review.reviewId)).feedback[0].payload,p);
  const other=await f.create();assert.deepEqual((await f.poll(other.reviewId)).feedback,[]);
});

test('webhook receives exact webhook-v1 JSON and configured bearer; receipt precedes delivery',async t=>{
  let received,headers,release;
  const url=await mock(t,async(req,res)=>{headers=req.headers;const chunks=[];for await(const c of req)chunks.push(c);received=JSON.parse(Buffer.concat(chunks));await new Promise(r=>release=r);res.writeHead(202);res.end('{}');});
  const f=await fixture(t);await writeFile(f.webhooksFile,JSON.stringify({ElonBot:{url,bearer:'test-webhook-bearer'}}));
  const review=await f.create(),p=payload(review);
  const response=await f.post('/api/feedback',p,await f.session());assert.equal(response.status,202);
  await until(()=>received);assert.deepEqual(received,p);assert.equal(headers.authorization,'Bearer test-webhook-bearer');
  assert.equal((await f.poll(review.reviewId)).feedback[0].delivery.status,'pending');release();
  await until(async()=>(await f.poll(review.reviewId)).feedback[0].delivery.status==='delivered');
  const record=(await f.poll(review.reviewId)).feedback[0];assert.equal(record.delivery.httpStatus,202);assert.equal(record.delivery.attempts,1);
  assert.ok(!JSON.stringify(record).includes('test-webhook-bearer'));
});

test('failed webhook persists, restart retries pending delivery, redirects never forward bearer',async t=>{
  let calls=0,success=false;
  const url=await mock(t,(req,res)=>{calls++;req.resume();res.writeHead(success?200:503);res.end('sensitive error text');});
  const f=await fixture(t);await writeFile(f.webhooksFile,JSON.stringify({ElonBot:{url,bearer:''}}));
  const review=await f.create(),p=payload(review);assert.equal((await f.post('/api/feedback',p,await f.session())).status,202);
  await until(async()=>(await f.poll(review.reviewId)).feedback[0]?.delivery.attempts===1);
  await f.stop();success=true;await f.start();
  await until(async()=>(await f.poll(review.reviewId)).feedback[0].delivery.status==='delivered');assert.equal(calls,2);
  assert.deepEqual((await f.poll(review.reviewId)).feedback[0].payload,p);
  let leaked=false;
  const destination=await mock(t,(req,res)=>{leaked=true;res.end();});
  const redirect=await mock(t,(req,res)=>{req.resume();res.writeHead(302,{Location:destination});res.end();});
  await writeFile(f.webhooksFile,JSON.stringify({ElonBot:{url:redirect,bearer:'must-not-follow'}}));
  const another=payload(review);await f.post('/api/feedback',another,await f.session());
  await until(async()=>(await f.poll(review.reviewId)).feedback.find(r=>r.payload.submissionId===another.submissionId)?.delivery.attempts===1);
  assert.equal(leaked,false);
});

test('webhook timeout and exhausted retries keep feedback available for polling',async t=>{
  const url=await mock(t,req=>req.resume());
  const f=await fixture(t,{webhookTimeoutMs:30});await writeFile(f.webhooksFile,JSON.stringify({ElonBot:{url,bearer:''}}));
  const review=await f.create(),p=payload(review);await f.post('/api/feedback',p,await f.session());
  await until(async()=>(await f.poll(review.reviewId)).feedback[0]?.delivery.attempts===1);
  await f.stop();
  const file=join(f.dataDir,'feedback',p.submissionId+'.json'),record=JSON.parse(await readFile(file,'utf8'));
  record.delivery.attempts=4;record.delivery.nextAttemptAt=0;await writeFile(file,JSON.stringify(record));await f.start();
  await until(async()=>(await f.poll(review.reviewId)).feedback[0]?.delivery.status==='failed');
  assert.deepEqual((await f.poll(review.reviewId)).feedback[0].payload,p);
});
