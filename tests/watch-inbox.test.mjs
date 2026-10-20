import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as sleep} from 'node:timers/promises';
import {createReceiver} from '../examples/receiver.mjs';
import {watchInbox,readPending,acknowledge} from '../examples/watch-inbox.mjs';
test('bounded watcher awaits delayed POST; reads never consume; explicit ack survives restart',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'loop-watch-test-'));const inbox=join(dir,'inbox');
 const payload=JSON.parse(await readFile(new URL('../protocol/fixture.json',import.meta.url),'utf8')).payload;
 const server=createReceiver({inboxDir:inbox});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{
  const emitted=[];
  const watching=watchInbox(inbox,{timeoutSeconds:0.25,pollMilliseconds:15,onPayload:p=>emitted.push(p)});
  await sleep(40);assert.equal(emitted.length,0);
  const response=await fetch(`http://127.0.0.1:${server.address().port}/webhook`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  assert.equal(response.status,202);assert.equal(await watching,1);assert.deepEqual(emitted,[payload]);
  assert.deepEqual(await readdir(inbox),[`${payload.submissionId}.json`]);
  const restarted=[];await watchInbox(inbox,{once:true,onPayload:p=>restarted.push(p)});assert.deepEqual(restarted,[payload]);
  await acknowledge(inbox,payload.submissionId);assert.deepEqual(await readPending(inbox),[]);
  assert.equal(await watchInbox(inbox,{once:true}),0);await acknowledge(inbox,payload.submissionId);
  await assert.rejects(acknowledge(inbox,'../unsafe'));
  assert.deepEqual(JSON.parse(await readFile(join(inbox,`${payload.submissionId}.json`),'utf8')),payload);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));await rm(dir,{recursive:true,force:true});}
});
