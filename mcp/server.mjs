#!/usr/bin/env node
/**
 * Loop MCP server (stdio JSON-RPC).
 * Tools wrap the existing Mac CLI and hosted web-review script — no new backend.
 *
 * Claude Desktop / Cursor example:
 *   {"command":"node","args":["/path/to/loop/mcp/server.mjs"],"env":{"LOOP_AGENT_TOKEN":"…"}}
 */
import {spawn} from 'node:child_process';
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createInterface} from 'node:readline';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const webReview = join(root, 'skills/loop-review/scripts/web-review.mjs');
const loopBin = process.env.LOOP_BIN || 'loop';

const tools = [
  {
    name: 'loop_web_create',
    description: '在手机网页端创建一轮 Loop 审阅，返回 reviewUrl。用户不在 Mac 前时用。',
    inputSchema: {
      type: 'object',
      properties: {
        document: {type: 'string', description: 'Markdown 方案正文'},
        path: {type: 'string', description: '方案文件路径；与 document 二选一'},
        agentName: {type: 'string', description: 'Agent 名字，默认 Loop MCP'},
        title: {type: 'string'},
        parentReviewId: {type: 'string', description: '上一版 reviewId，可选'},
      },
      additionalProperties: false,
    },
  },
  {
    name: 'loop_web_wait',
    description: '轮询托管服务，直到用户提交网页审阅反馈或超时。',
    inputSchema: {
      type: 'object',
      properties: {
        reviewId: {type: 'string'},
        timeoutSeconds: {type: 'number', description: '默认 540'},
      },
      required: ['reviewId'],
      additionalProperties: false,
    },
  },
  {
    name: 'loop_mac_detach',
    description: '在本机打开 Loop 审阅窗口并立即返回会话 id（适配有命令超时的 agent）。需要已安装 loop CLI。',
    inputSchema: {
      type: 'object',
      properties: {
        document: {type: 'string'},
        path: {type: 'string'},
      },
      additionalProperties: false,
    },
  },
  {
    name: 'loop_mac_wait',
    description: '等待本机 detach 审阅提交；超时可再次调用续等。',
    inputSchema: {
      type: 'object',
      properties: {
        id: {type: 'string'},
        timeoutSeconds: {type: 'number', description: '默认 540'},
      },
      required: ['id'],
      additionalProperties: false,
    },
  },
];

function send(msg) {
  const body = JSON.stringify(msg);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
}

function run(cmd, args, {input, env} = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, {
      env: {...process.env, ...env},
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '', stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    if (input != null) {
      child.stdin.write(input);
      child.stdin.end();
    } else child.stdin.end();
    child.on('close', (code) => resolve({code: code ?? 1, stdout, stderr}));
  });
}

function writeTempMarkdown(document) {
  const dir = mkdtempSync(join(tmpdir(), 'loop-mcp-'));
  const path = join(dir, '方案.md');
  writeFileSync(path, document, 'utf8');
  return {dir, path};
}

async function callTool(name, args = {}) {
  switch (name) {
    case 'loop_web_create': {
      let cleanup;
      let path = args.path;
      if (!path) {
        if (typeof args.document !== 'string' || !args.document.trim()) {
          return {isError: true, text: '需要 document 或 path'};
        }
        cleanup = writeTempMarkdown(args.document);
        path = cleanup.path;
      }
      try {
        const argv = [webReview, 'create', path, '--agent', args.agentName || process.env.LOOP_AGENT_NAME || 'Loop MCP'];
        if (args.title) argv.push('--title', args.title);
        if (args.parentReviewId) argv.push('--parent', args.parentReviewId);
        const r = await run(process.execPath, argv);
        if (r.code !== 0) return {isError: true, text: (r.stderr || r.stdout || `exit ${r.code}`).trim()};
        return {text: r.stdout.trim()};
      } finally {
        if (cleanup) rmSync(cleanup.dir, {recursive: true, force: true});
      }
    }
    case 'loop_web_wait': {
      const timeout = String(args.timeoutSeconds ?? 540);
      const r = await run(process.execPath, [webReview, 'wait', args.reviewId, '--timeout', timeout]);
      if (r.code === 2) return {isError: true, text: `timeout\n${(r.stderr || '').trim()}`};
      if (r.code !== 0) return {isError: true, text: (r.stderr || r.stdout || `exit ${r.code}`).trim()};
      return {text: r.stdout.trim()};
    }
    case 'loop_mac_detach': {
      let cleanup;
      let path = args.path;
      if (!path) {
        if (typeof args.document !== 'string' || !args.document.trim()) {
          return {isError: true, text: '需要 document 或 path'};
        }
        cleanup = writeTempMarkdown(args.document);
        path = cleanup.path;
      }
      try {
        const r = await run(loopBin, ['review', '--detach', path]);
        if (r.code !== 0) return {isError: true, text: (r.stderr || r.stdout || `exit ${r.code}`).trim()};
        return {text: r.stdout.trim()};
      } finally {
        // Detach copies the plan into its session dir; temp can go.
        if (cleanup) rmSync(cleanup.dir, {recursive: true, force: true});
      }
    }
    case 'loop_mac_wait': {
      const timeout = String(args.timeoutSeconds ?? 540);
      const r = await run(loopBin, ['wait', args.id, '--timeout', timeout]);
      if (r.code === 2) return {isError: true, text: `timeout\n${(r.stderr || '').trim()}`};
      if (r.code !== 0) return {isError: true, text: (r.stderr || r.stdout || `exit ${r.code}`).trim()};
      return {text: r.stdout.trim()};
    }
    default:
      return {isError: true, text: `未知工具：${name}`};
  }
}

async function handle(msg) {
  const {id, method, params} = msg;
  if (method === 'initialize') {
    return {
      jsonrpc: '2.0', id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: {tools: {}},
        serverInfo: {name: 'loop', version: '1.0.0'},
      },
    };
  }
  if (method === 'notifications/initialized' || method === 'initialized') return null;
  if (method === 'tools/list') {
    return {jsonrpc: '2.0', id, result: {tools}};
  }
  if (method === 'tools/call') {
    const name = params?.name;
    const args = params?.arguments || {};
    const result = await callTool(name, args);
    return {
      jsonrpc: '2.0', id,
      result: {
        content: [{type: 'text', text: result.text}],
        isError: !!result.isError,
      },
    };
  }
  if (method === 'ping') return {jsonrpc: '2.0', id, result: {}};
  return {
    jsonrpc: '2.0', id,
    error: {code: -32601, message: `Method not found: ${method}`},
  };
}

// Framing: prefer Content-Length; also accept newline-delimited JSON for tests.
let buffer = Buffer.alloc(0);
process.stdin.on('data', (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  void drain();
});

async function drain() {
  while (true) {
    if (buffer.length === 0) return;
    let message;
    if (buffer.toString('utf8', 0, Math.min(buffer.length, 20)).startsWith('Content-Length:')) {
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) return;
      const header = buffer.toString('utf8', 0, headerEnd);
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      if (!match) {
        buffer = buffer.subarray(headerEnd + 4);
        continue;
      }
      const len = Number(match[1]);
      const start = headerEnd + 4;
      if (buffer.length < start + len) return;
      message = buffer.subarray(start, start + len).toString('utf8');
      buffer = buffer.subarray(start + len);
    } else {
      const nl = buffer.indexOf('\n');
      if (nl < 0) return;
      message = buffer.subarray(0, nl).toString('utf8').trim();
      buffer = buffer.subarray(nl + 1);
      if (!message) continue;
    }
    let msg;
    try { msg = JSON.parse(message); }
    catch { continue; }
    const reply = await handle(msg);
    if (reply) send(reply);
  }
}

process.stdin.on('end', () => process.exit(0));
