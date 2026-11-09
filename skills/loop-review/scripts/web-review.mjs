#!/usr/bin/env node
// Web review through the hosted Loop server, for a user on the phone.
//
//   node web-review.mjs create <方案.md> [--agent 名字] [--title 标题] [--parent 上一版reviewId]
//       → prints {"reviewId","revision","reviewUrl"} as JSON
//   node web-review.mjs wait <reviewId> [--timeout 秒]
//       → exit 0 with the feedback on stdout; exit 2 if nothing was submitted before the timeout
//
// Token: $LOOP_AGENT_TOKEN, else ~/.config/loop/agent-token. Server: $LOOP_URL, else ~/.config/loop/url.
import {readFileSync} from 'node:fs';
import {homedir} from 'node:os';
import {basename, join} from 'node:path';
import {setTimeout as sleep} from 'node:timers/promises';

const [command, target, ...rest] = process.argv.slice(2);
const options = {};
for (let i = 0; i < rest.length; i += 2) {
  if (!rest[i].startsWith('--') || rest[i + 1] === undefined) fail(`参数有误：${rest[i]}`, 64);
  options[rest[i].slice(2)] = rest[i + 1];
}

function fail(message, code = 1) {
  process.stderr.write(`loop-web: ${message}\n`);
  process.exit(code);
}

function token() {
  if (process.env.LOOP_AGENT_TOKEN) return process.env.LOOP_AGENT_TOKEN.trim();
  try { return readFileSync(join(homedir(), '.config/loop/agent-token'), 'utf8').trim(); }
  catch { fail('找不到 Agent Token：设置 LOOP_AGENT_TOKEN，或写入 ~/.config/loop/agent-token', 69); }
}

function serverUrl() {
  let url = process.env.LOOP_URL?.trim();
  if (!url) try { url = readFileSync(join(homedir(), '.config/loop/url'), 'utf8').trim(); } catch {}
  if (!url) fail('找不到 Loop 服务地址：设置 LOOP_URL，或写入 ~/.config/loop/url', 69);
  return url.replace(/\/$/, '');
}

async function api(method, path, body) {
  const server = serverUrl();
  let response;
  try {
    response = await fetch(server + path, {
      method,
      headers: {Authorization: `Bearer ${token()}`, ...(body ? {'Content-Type': 'application/json'} : {})},
      body: body && JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
  } catch (error) { return {error: `连不上 ${server}：${error.message}`}; }
  const data = await response.json().catch(() => ({}));
  return response.ok ? {data} : {error: `${response.status} ${data.error || response.statusText}`, status: response.status};
}

if (command === 'create' && target) {
  let document;
  try { document = readFileSync(target, 'utf8'); } catch (error) { fail(`读不到 ${target}：${error.message}`, 66); }
  if (!document.trim()) fail(`${target} 是空的`, 66);
  if (document.length > 30000) fail(`方案有 ${document.length} 字，网页版上限 30000，请精简或拆开`, 66);
  const title = options.title || document.match(/^#[ \t]+(.+)$/m)?.[1].replace(/[*`]/g, '').trim() || basename(target).replace(/\.md$/i, '');
  const body = {title: title.slice(0, 120), agentName: (options.agent || process.env.LOOP_AGENT_NAME || 'Agent').slice(0, 100), document};
  if (options.parent) body.parentReviewId = options.parent;
  const {data, error} = await api('POST', '/api/reviews', body);
  if (error) fail(`创建审阅失败：${error}`);
  console.log(JSON.stringify({reviewId: data.reviewId, revision: data.revision, reviewUrl: data.reviewUrl}));
} else if (command === 'wait' && target) {
  const timeout = Number(options.timeout ?? 540);
  if (!(timeout >= 0)) fail('--timeout 要是秒数', 64);
  const deadline = Date.now() + timeout * 1000;
  for (;;) {
    const {data, error, status} = await api('GET', `/api/reviews/${encodeURIComponent(target)}/feedback`);
    if (error && status && status < 500) fail(`读取反馈失败：${error}`);
    const latest = data?.feedback?.at(-1)?.payload;
    if (latest) {
      if (data.feedback.length > 1) process.stderr.write(`loop-web: 这份方案提交过 ${data.feedback.length} 次，以下是最后一次\n`);
      console.log(latest.summary);
      process.exit(0);
    }
    if (Date.now() >= deadline) fail('还没有提交，稍后再等', 2);
    await sleep(Math.min(5000, Math.max(0, deadline - Date.now())));
  }
} else {
  fail('用法：web-review.mjs create <方案.md> [--agent 名字] [--parent reviewId] | wait <reviewId> [--timeout 秒]', 64);
}
