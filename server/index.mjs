import http from 'node:http';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, readdir, open, link, rename, unlink, realpath, stat } from 'node:fs/promises';
import { resolve, join, sep, extname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { validatePayload } from '../protocol/validate.mjs';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const MAX_BODY = 1024 * 1024;
const SESSION_MS = 30 * 60 * 1000;
const MIME = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8', '.json':'application/json', '.svg':'image/svg+xml', '.png':'image/png', '.ico':'image/x-icon', '.woff2':'font/woff2' };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const string = (value, max) => typeof value === 'string' && value.length <= max;
const fail = (status, message) => Object.assign(new Error(message), { status });
const digest = value => createHash('sha256').update(value).digest();

async function readJSON(file) {
  try { return JSON.parse(await readFile(file, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
// Sync both contents and directory entries before acknowledging acceptance.
async function atomicJSON(file, value, exclusive = false) {
  const directory = resolve(file, '..');
  const temporary = join(directory, `.${randomUUID()}.tmp`);
  const handle = await open(temporary, 'wx', 0o600);
  try {
    await handle.writeFile(JSON.stringify(value) + '\n');
    await handle.sync();
  } finally { await handle.close(); }
  try {
    if (exclusive) await link(temporary, file);
    else await rename(temporary, file);
    const dir = await open(directory, 'r');
    try { await dir.sync(); } finally { await dir.close(); }
  } finally { await unlink(temporary).catch(() => {}); }
}
async function bodyJSON(req) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) throw fail(415, 'application/json required');
  if (Number(req.headers['content-length']) > MAX_BODY) throw fail(413, 'Maximum body is 1 MiB');
  let size = 0;
  const chunks = [];
  // Keep the socket usable long enough to return 413 for chunked requests too.
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > MAX_BODY) throw fail(413, 'Maximum body is 1 MiB');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw fail(400, 'Invalid JSON'); }
}
function validateFeedback(p) {
  const error = validatePayload(p);
  if (error) return error;
  const fields = ['protocolVersion','submissionId','agentName','document','annotations','generalFeedback','submittedAt','summary','checks','reviewId','revision'];
  if (Object.keys(p).some(k => !fields.includes(k)) || !UUID.test(p.submissionId) || !UUID.test(p.reviewId)) return 'Invalid feedback fields or IDs';
  if (!string(p.document, 30000) || !string(p.agentName, 100) || !string(p.generalFeedback, 5000) || !string(p.summary, 200000) || p.annotations.length > 100) return 'Feedback limit exceeded';
  if (Array.isArray(p.checks) && p.checks.length > 200) return 'Feedback limit exceeded';
  if (!p.annotations.length && !p.generalFeedback.trim() && !(Array.isArray(p.checks) && p.checks.length)) return 'Feedback is empty';
  for (const a of p.annotations) {
    if (Object.keys(a).some(k => !['id','quote','comment','start','end'].includes(k)) || !string(a.id, 100) || !string(a.quote, 30000) || !string(a.comment, 5000) || a.end > 200000) return 'Invalid annotation fields or limits';
  }
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(p.submittedAt)) return 'UTC timestamp required';
  return null;
}
async function webhookConfig(file) {
  const config = await readJSON(file) ?? {};
  if (!object(config)) throw new Error('Invalid webhook configuration');
  for (const target of Object.values(config)) {
    if (!object(target) || typeof target.url !== 'string' || typeof target.bearer !== 'string' || /[\r\n]/.test(target.bearer)) throw new Error('Invalid webhook configuration');
    if (!target.url) continue;
    const url = new URL(target.url);
    const local = ['localhost','127.0.0.1','[::1]'].includes(url.hostname);
    if (url.username || url.password || url.hash || !(url.protocol === 'https:' || (url.protocol === 'http:' && local))) throw new Error('Invalid webhook URL');
  }
  return config;
}

export async function createLoopServer({
  agentToken = process.env.LOOP_AGENT_TOKEN,
  dataDir = process.env.LOOP_DATA_DIR || './data',
  webDist = process.env.LOOP_WEB_DIST || '../web/dist',
  host = process.env.HOST || '127.0.0.1',
  port = Number(process.env.PORT || 3020),
  publicUrl = process.env.LOOP_PUBLIC_URL || `http://${host.includes(':') ? `[${host}]` : host}:${port}`,
  webhooksFile = process.env.LOOP_WEBHOOKS_FILE,
  deliveryIntervalMs = 5000,
  webhookTimeoutMs = 10000,
} = {}) {
  if (typeof agentToken !== 'string' || !agentToken.trim() || /[\r\n]/.test(agentToken)) throw new Error('LOOP_AGENT_TOKEN is required and must be a single line');
  const publicOrigin = new URL(publicUrl);
  if (!['http:','https:'].includes(publicOrigin.protocol) || publicOrigin.username || publicOrigin.password || publicOrigin.search || publicOrigin.hash || publicOrigin.pathname !== '/') throw new Error('LOOP_PUBLIC_URL must be an HTTP(S) origin');
  const expectedToken = digest(`Bearer ${agentToken}`);
  dataDir = resolve(dataDir); webDist = resolve(webDist);
  webhooksFile = resolve(webhooksFile || join(dataDir, '..', 'webhooks.json'));
  await webhookConfig(webhooksFile);
  const reviews = join(dataDir, 'reviews'), feedback = join(dataDir, 'feedback');
  await mkdir(reviews, { recursive:true, mode:0o700 });
  await mkdir(feedback, { recursive:true, mode:0o700 });
  const sessions = new Map(), rates = new Map();
  const reviewFile = id => join(reviews, `${id}.json`);
  const feedbackFile = id => join(feedback, `${id}.json`);
  const authorized = req => timingSafeEqual(digest(req.headers.authorization || ''), expectedToken);
  function sameOrigin(req) {
    if (req.headers.origin && req.headers.origin !== publicOrigin.origin) throw fail(403, 'Same-origin requests only');
    if (req.headers['sec-fetch-site'] === 'cross-site') throw fail(403, 'Same-origin requests only');
  }
  function rateLimit(req) {
    const now = Date.now();
    for (const [key, value] of rates) if (value.until <= now) rates.delete(key);
    const key = req.socket.remoteAddress;
    const bucket = rates.get(key) || { until:now + 60000, used:0 };
    if (bucket.used >= 120 || (!rates.has(key) && rates.size >= 10000)) throw fail(429, 'Too many requests');
    bucket.used++; rates.set(key, bucket);
  }
  function sessionFor(req) {
    const session = sessions.get(req.headers['x-loop-session']);
    if (!session || session.expires <= Date.now() || session.used >= 30) throw fail(403, 'Session expired or exhausted');
    session.used++;
  }

  let draining = null, stopped = false;
  async function deliver() {
    for (const name of await readdir(feedback)) {
      if (stopped) break;
      if (!UUID.test(name.slice(0, -5)) || !name.endsWith('.json')) continue;
      const file = join(feedback, name), record = await readJSON(file);
      if (!record || record.delivery.status !== 'pending' || record.delivery.nextAttemptAt > Date.now()) continue;
      let target;
      const delivery = { status:'pending', attempts:record.delivery.attempts + 1, updatedAt:new Date().toISOString() };
      try {
        const config = await webhookConfig(webhooksFile);
        target = Object.hasOwn(config, record.payload.agentName) ? config[record.payload.agentName] : Object.hasOwn(config, '*') ? config['*'] : null;
        if (!target?.url) { delivery.status = 'skipped'; delivery.attempts--; }
        else {
          const response = await fetch(target.url, {
            method:'POST', redirect:'error', signal:AbortSignal.timeout(webhookTimeoutMs),
            headers:{ 'Content-Type':'application/json', ...(target.bearer ? { Authorization:`Bearer ${target.bearer}` } : {}) },
            body:JSON.stringify(record.payload),
          });
          delivery.httpStatus = response.status;
          await response.body?.cancel();
          if (!response.ok) throw new Error('Webhook rejected');
          delivery.status = 'delivered';
        }
      } catch {
        // Do not store URLs, credentials, response bodies, or transport error messages.
        delivery.status = delivery.attempts >= 5 ? 'failed' : 'pending';
        delivery.nextAttemptAt = Date.now() + 1000 * 2 ** delivery.attempts;
      }
      await atomicJSON(file, { ...record, delivery });
    }
  }
  function drain() {
    if (!stopped && !draining) draining = deliver().catch(() => {
      console.error('Loop delivery scan failed; stored feedback retained.');
    }).finally(() => { draining = null; });
    return draining;
  }
  async function serveStatic(pathname, req, res) {
    let relative;
    try { relative = decodeURIComponent(pathname); } catch { throw fail(400, 'Invalid path'); }
    if (relative.includes('\0') || relative.split(/[\\/]/).some(p => p === '..' || p.startsWith('.'))) throw fail(404, 'Not found');
    const root = await realpath(webDist).catch(() => { throw fail(503, 'Web build unavailable'); });
    let file = resolve(root, `.${relative}`);
    if (file !== root && !file.startsWith(root + sep)) throw fail(404, 'Not found');
    try { if (!(await stat(file)).isFile()) file = join(root, 'index.html'); }
    catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error; file = join(root, 'index.html'); }
    file = await realpath(file).catch(() => { throw fail(503, 'Web build unavailable'); });
    if (!file.startsWith(root + sep)) throw fail(404, 'Not found');
    let body = await readFile(file);
    const html = extname(file) === '.html';
    if (html) body = Buffer.from(body.toString('utf8').replace(/<head\b[^>]*>/i, '$&<script>window.LOOP_HOSTED=true</script>'));
    res.setHeader('Content-Type', MIME[extname(file)] || 'application/octet-stream');
    res.setHeader('Content-Length', body.length);
    res.writeHead(200); res.end(req.method === 'HEAD' ? undefined : body);
  }
  const server = http.createServer({ requestTimeout:30000, headersTimeout:15000, maxHeaderSize:16384 }, async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    const reply = (status, value) => { res.setHeader('Content-Type','application/json; charset=utf-8'); res.writeHead(status); res.end(JSON.stringify(value)); };
    try {
      const pathname = new URL(req.url, 'http://loop.local').pathname;
      if (!pathname.startsWith('/api/')) {
        if (!['GET','HEAD'].includes(req.method)) throw fail(405, 'Method not allowed');
        return await serveStatic(pathname, req, res);
      }
      if (pathname === '/api/health' && req.method === 'GET') return reply(200, { ok:true });
      const match = /^\/api\/reviews\/([^/]+)(\/feedback)?$/.exec(pathname);
      if (match) {
        if (match[2] && !authorized(req)) throw fail(401, 'Unauthorized');
        if (!UUID.test(match[1])) throw fail(400, 'Invalid review ID');
        if (req.method !== 'GET') throw fail(405, 'Method not allowed');
        const review = await readJSON(reviewFile(match[1]));
        if (!review) throw fail(404, 'Review not found');
        if (!match[2]) return reply(200, review);
        const list = [];
        for (const name of await readdir(feedback)) {
          if (!name.endsWith('.json') || !UUID.test(name.slice(0, -5))) continue;
          const record = await readJSON(join(feedback, name));
          if (record?.payload.reviewId === match[1]) list.push(record);
        }
        list.sort((a,b) => a.receivedAt.localeCompare(b.receivedAt) || a.payload.submissionId.localeCompare(b.payload.submissionId));
        return reply(200, { reviewId:match[1], feedback:list });
      }
      if (!['/api/session','/api/feedback','/api/reviews'].includes(pathname)) throw fail(404, 'Not found');
      if (pathname === '/api/reviews' && !authorized(req)) throw fail(401, 'Unauthorized');
      if (req.method !== 'POST') throw fail(405, 'Method not allowed');
      sameOrigin(req);
      if (pathname !== '/api/reviews') rateLimit(req);
      if (pathname === '/api/session') {
        const now = Date.now();
        for (const [key, value] of sessions) if (value.expires <= now) sessions.delete(key);
        if (sessions.size >= 10000) throw fail(429, 'Session limit reached');
        const session = randomBytes(32).toString('base64url');
        sessions.set(session, { expires:now + SESSION_MS, used:0 });
        req.resume(); return reply(200, { session, expiresIn:SESSION_MS / 1000 });
      }
      if (pathname === '/api/feedback') sessionFor(req);
      const p = await bodyJSON(req);
      if (pathname === '/api/reviews') {
        if (!object(p) || Object.keys(p).some(k => !['title','agentName','document','parentReviewId'].includes(k)) || !string(p.title,120) || !p.title.trim() || !string(p.agentName,100) || !p.agentName.trim() || !string(p.document,30000) || !p.document.trim() || (Object.hasOwn(p,'parentReviewId') && !UUID.test(p.parentReviewId))) throw fail(400, 'Invalid review fields or limits');
        const parent = p.parentReviewId ? await readJSON(reviewFile(p.parentReviewId)) : null;
        if (p.parentReviewId && !parent) throw fail(404, 'Parent review not found');
        const revision = parent ? parent.revision + 1 : 1;
        if (revision > 1000) throw fail(400, 'Revision limit reached');
        const review = { reviewId:randomUUID(), title:p.title.trim(), agentName:p.agentName.trim(), document:p.document, createdAt:new Date().toISOString(), parentReviewId:parent?.reviewId ?? null, revision };
        await atomicJSON(reviewFile(review.reviewId), review, true);
        return reply(201, { ...review, reviewUrl:new URL(`/?review=${review.reviewId}`, publicOrigin).href });
      }
      const invalid = validateFeedback(p);
      if (invalid) throw fail(400, invalid);
      const review = await readJSON(reviewFile(p.reviewId));
      if (!review || review.revision !== p.revision || review.document !== p.document || review.agentName !== p.agentName) throw fail(409, 'Feedback does not match immutable review');
      const record = { payload:p, receivedAt:new Date().toISOString(), delivery:{ status:'pending', attempts:0, nextAttemptAt:0 } };
      let duplicate = false;
      try { await atomicJSON(feedbackFile(p.submissionId), record, true); }
      catch (error) {
        if (error.code !== 'EEXIST') throw error;
        const previous = await readJSON(feedbackFile(p.submissionId));
        if (!isDeepStrictEqual(previous.payload, p)) throw fail(409, 'Submission ID reused with different payload');
        duplicate = true;
      }
      reply(202, { accepted:true, submissionId:p.submissionId, duplicate, persisted:true });
      void drain();
    } catch (error) {
      req.resume();
      if (!res.headersSent) reply(error.status || 500, { error:error.status ? error.message : 'Server error' });
      else res.destroy();
    }
  });
  let timer;
  server.on('listening', () => { void drain(); timer = setInterval(drain, deliveryIntervalMs); timer.unref(); });
  server.on('close', () => { stopped = true; clearInterval(timer); });
  // Allows graceful shutdown and tests to await the final atomic delivery status write.
  server.stop = async () => {
    stopped = true; clearInterval(timer);
    if (server.listening) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await draining;
  };
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const server = await createLoopServer();
    const port = Number(process.env.PORT || 3020), host = process.env.HOST || '127.0.0.1';
    server.on('error', () => { console.error('Loop could not listen on the configured address.'); process.exitCode = 1; });
    server.listen(port, host, () => console.log(`Loop listening on port ${server.address().port}`));
    for (const signal of ['SIGINT','SIGTERM']) process.once(signal, () => { void server.stop().catch(() => { process.exitCode = 1; }); });
  } catch { console.error('Loop startup failed; check token, paths, public URL, and webhook configuration.'); process.exitCode = 1; }
}
