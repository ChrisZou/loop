/** Explicit, bounded, local inbox reader. Never evaluates feedback or wakes agents. */
import {readdir,readFile,mkdir,writeFile,stat} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setTimeout as sleep} from 'node:timers/promises';
import {validatePayload} from './receiver.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const filePattern=/^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.json$/i;
export async function readPending(inboxDir) {
 const inbox=resolve(inboxDir);let files;
 try {files=await readdir(inbox);}catch(e){if(e.code==='ENOENT')return [];throw e;}
 const result=[];
 for(const file of files.sort()){
  const match=filePattern.exec(file);if(!match)continue;
  try {await stat(join(inbox,'.processed',`${match[1].toLowerCase()}.ack`));continue;}catch(e){if(e.code!=='ENOENT')throw e;}
  const payload=JSON.parse(await readFile(join(inbox,file),'utf8'));
  const error=validatePayload(payload);if(error||payload.submissionId.toLowerCase()!==match[1].toLowerCase())throw new Error(`Invalid inbox record: ${file}`);
  result.push(payload);
 }
 return result;
}
export async function acknowledge(inboxDir,id){
 if(!uuid.test(id))throw new Error('Acknowledgment requires a UUID submission ID');
 const inbox=resolve(inboxDir), normalized=id.toLowerCase();
 const payload=JSON.parse(await readFile(join(inbox,`${normalized}.json`),'utf8'));
 if(validatePayload(payload)||payload.submissionId.toLowerCase()!==normalized)throw new Error('Cannot acknowledge invalid submission');
 const directory=join(inbox,'.processed');await mkdir(directory,{recursive:true,mode:0o700});
 try {await writeFile(join(directory,`${normalized}.ack`),JSON.stringify({submissionId:payload.submissionId,acknowledgedAt:new Date().toISOString()})+'\n',{mode:0o600,flag:'wx'});}catch(e){if(e.code!=='EEXIST')throw e;}
}
export async function watchInbox(inboxDir,{once=false,timeoutSeconds=60,pollMilliseconds=200,onPayload=()=>{}}={}){
 if(!Number.isFinite(timeoutSeconds)||timeoutSeconds<=0||timeoutSeconds>3600)throw new Error('timeout-seconds must be greater than 0 and at most 3600');
 const emitted=new Set(),deadline=Date.now()+timeoutSeconds*1000;
 do {
  for(const p of await readPending(inboxDir)){const id=p.submissionId.toLowerCase();if(!emitted.has(id)){await onPayload(p);emitted.add(id);}}
  if(once||Date.now()>=deadline)break;
  await sleep(Math.min(pollMilliseconds,Math.max(0,deadline-Date.now())));
 }while(Date.now()<=deadline);
 return emitted.size;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try {
  let inbox=null,once=false,timeoutSeconds=60,ack=null;const args=process.argv.slice(2);
  for(let i=0;i<args.length;i++){
   const arg=args[i];if(arg==='--inbox-dir'){inbox=args[++i];if(!inbox||inbox.startsWith('--'))throw new Error('Missing inbox directory');}
   else if(arg==='--once')once=true;
   else if(arg==='--timeout-seconds')timeoutSeconds=Number(args[++i]);
   else if(arg==='--ack')ack=args[++i];
   else throw new Error(`Unknown option: ${arg}`);
  }
  if(!inbox)throw new Error('Specify --inbox-dir <private-directory>');
  if(args.includes('--ack')&&!ack)throw new Error('Missing acknowledgment UUID');
  if(ack){if(once||args.includes('--timeout-seconds'))throw new Error('--ack cannot be combined with watch options');await acknowledge(inbox,ack);console.error(`Acknowledged ${ack}`);}
  else await watchInbox(inbox,{once,timeoutSeconds,onPayload:p=>process.stdout.write(JSON.stringify(p)+'\n')});
 }catch(e){console.error(e.message);process.exitCode=1;}
}
