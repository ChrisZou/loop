/** Local demonstration only. Never starts an agent or forwards user documents. */
import http from 'node:http';
import { timingSafeEqual, randomUUID } from 'node:crypto';
import { mkdir, readFile, open, link, unlink } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
export const allowedOrigins = new Set(['http://localhost:5173','http://127.0.0.1:5173','http://localhost:4173','http://127.0.0.1:4173']);
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
  const summary='以下是我对你方案的逐条反馈，请据此修改出下一版：'+p.annotations.map((a,i)=>`\n\n${i+1}. 原文：\n> ${a.quote.replaceAll('\n','\n> ')}\n意见：${a.comment}`).join('')+(p.generalFeedback.trim()?`\n\n总体意见：${p.generalFeedback.trim()}`:'');
  if(p.summary!==summary) return 'Summary does not match annotations';
  return null;
}
export function createReceiver({token='', inboxDir=null, onAccept=()=>{}}={}) {
  const inbox=inboxDir ? resolve(inboxDir) : null;
  async function persist(p, body) {
    if(!inbox)return false;
    await mkdir(inbox,{recursive:true,mode:0o700});
    const target=join(inbox,`${p.submissionId.toLowerCase()}.json`);
    const temporary=join(inbox,`.${randomUUID()}.tmp`);
    const handle=await open(temporary,'wx',0o600);
    try {await handle.writeFile(body+'\n');await handle.sync();} finally {await handle.close();}
    try {
      // Hard-link atomically publishes a complete file without replacing an existing ID.
      await link(temporary,target);return false;
    } catch(error) {
      if(error.code!=='EEXIST')throw error;
      const previous=JSON.parse(await readFile(target,'utf8'));
      if(JSON.stringify(previous)!==body){const conflict=new Error('ID conflict');conflict.code='CONFLICT';throw conflict;}
      return true;
    } finally {await unlink(temporary).catch(()=>{});}
  }
  const accepted=new Map();
  return http.createServer(async(req,res)=>{
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    const reply=(status,value)=>{res.writeHead(status);res.end(JSON.stringify(value));};
    if(req.headers.host && !/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(req.headers.host)) return reply(403,{error:'Local host required'});
    const origin=req.headers.origin;
    if(origin && !allowedOrigins.has(origin)) return reply(403,{error:'Origin not allowed'});
    if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
    if(req.url!=='/webhook') return reply(404,{error:'Not found'});
    if(req.method==='OPTIONS') {
      res.setHeader('Access-Control-Allow-Methods','POST, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');
      res.writeHead(204);return res.end();
    }
    if(req.method!=='POST') return reply(405,{error:'POST required'});
    if(token){const got=Buffer.from(req.headers.authorization||'');const want=Buffer.from(`Bearer ${token}`);if(got.length!==want.length||!timingSafeEqual(got,want))return reply(401,{error:'Unauthorized'});}
    if(!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type']||''))return reply(415,{error:'application/json required'});
    let size=0;const chunks=[];
    try {
      for await(const chunk of req){size+=chunk.length;if(size>1024*1024){reply(413,{error:'Maximum payload is 1 MiB'});req.resume();return;}chunks.push(chunk);}
      const p=JSON.parse(Buffer.concat(chunks).toString('utf8'));const error=validatePayload(p);if(error)return reply(400,{error});
      const body=JSON.stringify(p), prior=accepted.get(p.submissionId);
      if(prior && prior!==body)return reply(409,{error:'Submission ID reused with different payload'});
      const duplicate=!!prior || await persist(p,body);
      if(!duplicate){await onAccept(p);}accepted.set(p.submissionId,body);if(accepted.size>1000)accepted.delete(accepted.keys().next().value);
      reply(202,{accepted:true,submissionId:p.submissionId,duplicate,persisted:!!inbox,agentStarted:false,demo:true});
    }catch(error){reply(error.code==='CONFLICT'?409:error instanceof SyntaxError?400:500,{error:error.code==='CONFLICT'?'Submission ID reused with different payload':error instanceof SyntaxError?'Invalid JSON':'Receiver error'});}
  });
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
  const args=process.argv.slice(2);
  if(args.length && (args.length!==2 || args[0]!=='--inbox-dir' || !args[1])){console.error('Usage: node examples/receiver.mjs [--inbox-dir <private-directory>]');process.exit(2);}
  const server=createReceiver({token:process.env.LOOP_DEMO_TOKEN||'',inboxDir:args[1]||null,onAccept:p=>console.log(`Accepted ${p.submissionId}; annotations=${p.annotations.length}; demo only, no agent started.`)});
  server.listen(8787,'127.0.0.1',()=>console.log('Loop demo receiver: http://127.0.0.1:8787/webhook (loopback only)'));
}
