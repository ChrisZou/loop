import {spawn} from 'node:child_process';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const serverPath = join(dirname(fileURLToPath(import.meta.url)), 'server.mjs');

function rpc(child, msg) {
  const body = JSON.stringify(msg);
  child.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
}

function readOne(child) {
  return new Promise((resolve, reject) => {
    let buf = Buffer.alloc(0);
    const onData = (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const headerEnd = buf.indexOf('\r\n\r\n');
      if (headerEnd < 0) return;
      const header = buf.toString('utf8', 0, headerEnd);
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      if (!match) return;
      const len = Number(match[1]);
      const start = headerEnd + 4;
      if (buf.length < start + len) return;
      child.stdout.off('data', onData);
      resolve(JSON.parse(buf.subarray(start, start + len).toString('utf8')));
    };
    child.stdout.on('data', onData);
    setTimeout(() => reject(new Error('timeout waiting for MCP response')), 5000);
  });
}

test('initialize + tools/list', async () => {
  const child = spawn(process.execPath, [serverPath], {stdio: ['pipe', 'pipe', 'pipe']});
  try {
    rpc(child, {jsonrpc: '2.0', id: 1, method: 'initialize', params: {protocolVersion: '2024-11-05', capabilities: {}, clientInfo: {name: 'test', version: '0'}}});
    const init = await readOne(child);
    assert.equal(init.result.serverInfo.name, 'loop');
    rpc(child, {jsonrpc: '2.0', method: 'notifications/initialized'});
    rpc(child, {jsonrpc: '2.0', id: 2, method: 'tools/list'});
    const list = await readOne(child);
    const names = list.result.tools.map((t) => t.name).sort();
    assert.deepEqual(names, ['loop_mac_detach', 'loop_mac_wait', 'loop_web_create', 'loop_web_wait']);
  } finally {
    child.kill();
  }
});
