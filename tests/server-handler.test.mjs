// Direct HTTP-handler tests also run in sandboxes that prohibit listening sockets.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { createLoopServer } from '../server/index.mjs';

async function setup(t) {
  const root=await mkdtemp(join(tmpdir(),'loop-handler-')),webDist=join(root,'web'),dataDir=join(root,'data'),webhooksFile=join(root,'webhooks.json');
  await mkdir(webDist);await writeFile(join(webDist,'index.html'),'<head></head><body></body>');
  const server=await createLoopServer({agentToken:'handler-test-token',dataDir,webDist,webhooksFile,publicUrl:'https://loop.test'});
  t.after(async()=>{await server.stop();await rm(root,{recursive:true,force:true});});
  async function request(method,url,value,headers={}) {
    const req=Readable.from(value===undefined?[]:[Buffer.from(typeof value==='string'?value:JSON.stringify(value))]);
    Object.assign(req,{method,url,headers:{'content-type':'application/json',...headers},socket:{remoteAddress:'127.0.0.1'}});
    const responseHeaders={};let status,body;
    const res={headersSent:false,setHeader:(key,value)=>{responseHeaders[key.toLowerCase()]=value;},writeHead:code=>{status=code;res.headersSent=true;},end:value=>{body=value;},destroy:()=>{throw new Error('Unexpected socket destruction');}};
    await server.listeners('request')[0](req,res);
    return {status,headers:responseHeaders,text:body?.toString(),json:()=>JSON.parse(body)};
  }
  const auth={authorization:'Bearer handler-test-token'};
  const review=(await request('POST','/api/reviews',{title:'正式方案',agentName:'ElonBot',document:'# Plan'},auth)).json();
  const session={'x-loop-session':(await request('POST','/api/session')).json().session};
  const payload={protocolVersion:1,submissionId:randomUUID(),agentName:review.agentName,document:review.document,reviewId:review.reviewId,revision:review.revision,annotations:[],generalFeedback:'请补充',submittedAt:new Date().toISOString(),summary:'以下是我对你方案的逐条反馈，请据此修改出下一版：\n\n总体意见：请补充'};
  return {server,request,review,session,payload,auth,dataDir,webhooksFile};
}

test('handler: static injection, immutable review and constant-length/hash auth paths',async t=>{
  const f=await setup(t);
  assert.equal((await f.request('GET','/api/health')).status,200);
  assert.match((await f.request('GET','/nested/path')).text,/<head><script>window.LOOP_HOSTED=true<\/script>/);
  assert.equal((await f.request('POST','/api/reviews',{},f.session)).status,401);
  assert.equal((await f.request('GET',`/api/reviews/${f.review.reviewId}/feedback`)).status,401);
  assert.equal((await f.request('GET',`/api/reviews/${f.review.reviewId}/feedback`,undefined,{authorization:'Bearer handler-test-tokeN'})).status,401);
  assert.equal((await f.request('GET',`/api/reviews/${f.review.reviewId}`)).json().document,'# Plan');
  assert.equal(f.review.reviewUrl,`https://loop.test/?review=${f.review.reviewId}`);
  const revision=(await f.request('POST','/api/reviews',{title:'下一版',agentName:'ElonBot',document:'New',parentReviewId:f.review.reviewId},f.auth)).json();
  assert.equal(revision.revision,2);assert.equal(revision.parentReviewId,f.review.reviewId);
  for(const change of [{title:'x'.repeat(121)},{parentReviewId:null},{parentReviewId:'../bad'}])assert.equal((await f.request('POST','/api/reviews',{title:'A',agentName:'ElonBot',document:'D',...change},f.auth)).status,400);
  assert.equal((await f.request('POST','/api/session',undefined,{origin:'https://bad.example'})).status,403);
});

test('handler: validation, atomic persistence, concurrent deduplication and scoped poll',async t=>{
  const f=await setup(t);
  assert.equal((await f.request('POST','/api/feedback',f.payload)).status,403);
  for(const [change,status] of [[{summary:'bad'},400],[{submissionId:'../bad'},400],[{reviewId:null},400],[{document:'changed'},409],[{agentName:'Wrong'},409],[{revision:2},409]])assert.equal((await f.request('POST','/api/feedback',{...f.payload,...change},f.session)).status,status);
  assert.equal((await f.request('POST','/api/feedback','{',f.session)).status,400);
  assert.equal((await f.request('POST','/api/feedback','x'.repeat(1024*1024+1),f.session)).status,413);
  const results=await Promise.all(Array.from({length:4},()=>f.request('POST','/api/feedback',f.payload,f.session)));
  assert.ok(results.every(r=>r.status===202));assert.equal(results.filter(r=>!r.json().duplicate).length,1);
  assert.equal((await f.request('POST','/api/feedback',{...f.payload,submittedAt:'2026-01-01T00:00:00Z'},f.session)).status,409);
  const list=(await f.request('GET',`/api/reviews/${f.review.reviewId}/feedback`,undefined,f.auth)).json().feedback;
  assert.equal(list.length,1);assert.deepEqual(list[0].payload,f.payload);
  assert.deepEqual(JSON.parse(await readFile(join(f.dataDir,'feedback',f.payload.submissionId+'.json'),'utf8')).payload,f.payload);
});

test('handler: full webhook payload sent only after disk persistence; delivery status is recorded',async t=>{
  const f=await setup(t);await writeFile(f.webhooksFile,JSON.stringify({ElonBot:{url:'https://agent.example/hook',bearer:'handler-test-bearer'}}));
  let delivered=false;
  t.mock.method(globalThis,'fetch',async(url,options)=>{
    assert.equal(url,'https://agent.example/hook');assert.equal(options.headers.Authorization,'Bearer handler-test-bearer');assert.equal(options.redirect,'error');
    assert.deepEqual(JSON.parse(options.body),f.payload);
    assert.deepEqual(JSON.parse(await readFile(join(f.dataDir,'feedback',f.payload.submissionId+'.json'),'utf8')).payload,f.payload);
    delivered=true;return new Response('{}',{status:202});
  });
  assert.equal((await f.request('POST','/api/feedback',f.payload,f.session)).status,202);
  for(let n=0;n<100;n++){const r=(await f.request('GET',`/api/reviews/${f.review.reviewId}/feedback`,undefined,f.auth)).json().feedback[0];if(r.delivery.status==='delivered'){assert.equal(delivered,true);assert.equal(r.delivery.httpStatus,202);return;}await sleep(10);}
  assert.fail('Delivery did not finish');
});

test('handler: failed webhook retains feedback with retry status and no transport secrets',async t=>{
  const f=await setup(t);await writeFile(f.webhooksFile,JSON.stringify({ElonBot:{url:'https://agent.example/hook',bearer:'handler-test-bearer'}}));
  t.mock.method(globalThis,'fetch',async()=>{throw new Error('Sensitive transport details');});
  assert.equal((await f.request('POST','/api/feedback',f.payload,f.session)).status,202);
  for(let n=0;n<100;n++){const r=(await f.request('GET',`/api/reviews/${f.review.reviewId}/feedback`,undefined,f.auth)).json().feedback[0];if(r.delivery.attempts===1){assert.equal(r.delivery.status,'pending');assert.ok(r.delivery.nextAttemptAt>Date.now());assert.deepEqual(r.payload,f.payload);assert.ok(!JSON.stringify(r).includes('Sensitive'));return;}await sleep(10);}
  assert.fail('Failure was not recorded');
});
