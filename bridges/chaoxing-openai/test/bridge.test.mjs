import { afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createServer } from '../bridge.mjs';

const servers = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map(server => new Promise(resolve => server.close(resolve))));
});
async function listen(server) {
  servers.push(server);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${server.address().port}`;
}

// Would fail if the bridge reused another request's session, dropped upstream auth,
// or failed to delete a session after receiving its answer.
test('each authorized completion uses and releases its own Chaoxing session', async () => {
  const actions = [];
  const upstream = http.createServer(async (req, res) => {
    assert.equal(req.headers.authorization, 'Bearer chaoxing-private-key');
    const body = await new Promise(resolve => {
      let text = '';
      req.on('data', part => { text += part; });
      req.on('end', () => resolve(text ? JSON.parse(text) : {}));
    });
    if (req.url === '/api/status') return void res.end(JSON.stringify({ upstream: { ready: true } }));
    if (req.url === '/api/sessions') {
      actions.push('create'); res.writeHead(201); return void res.end(JSON.stringify({ session_id: `session-${actions.length}` }));
    }
    if (req.url === '/api/chat') {
      actions.push(`chat:${body.session_id}:${body.message}`);
      return void res.end(JSON.stringify({ session_id: body.session_id, answer: '课程答复' }));
    }
    if (req.method === 'DELETE') { actions.push(`delete:${req.url}`); res.writeHead(204); return void res.end(); }
    res.writeHead(404); res.end();
  });
  const upstreamUrl = await listen(upstream);
  const bridgeUrl = await listen(createServer({ upstreamUrl, upstreamKey: 'chaoxing-private-key', key: 'bridge-private-key' }));
  const req = () => fetch(`${bridgeUrl}/v1/chat/completions`, {
    method: 'POST', headers: { Authorization: 'Bearer bridge-private-key', 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'chaoxing-course-ai', messages: [{ role: 'user', content: '你好' }] }),
  });
  const first = await req(); const second = await req();
  assert.equal(first.status, 200); assert.equal(second.status, 200);
  assert.equal((await first.json()).choices[0].message.content, '课程答复');
  assert.deepEqual(actions, [
    'create', 'chat:session-1:你好', 'delete:/api/sessions/session-1',
    'create', 'chat:session-4:你好', 'delete:/api/sessions/session-4',
  ]);
  const unauthorized = await fetch(`${bridgeUrl}/v1/chat/completions`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
  assert.equal(unauthorized.status, 401);
});

// Would fail if an unavailable course was advertised as ready or a failed send
// leaked a session into the bounded upstream pool.
test('upstream failure is reported and a created session is released', async () => {
  const actions = [];
  const upstreamUrl = await listen(http.createServer(async (req, res) => {
    if (req.url === '/api/status') return void res.end(JSON.stringify({ upstream: { ready: false, code: 'LOGIN_REQUIRED', message: '请登录' } }));
    if (req.url === '/api/sessions') { actions.push('create'); res.writeHead(201); return void res.end(JSON.stringify({ session_id: 's1' })); }
    if (req.url === '/api/chat') { actions.push('chat'); res.writeHead(503); return void res.end(JSON.stringify({ error: { code: 'LOGIN_REQUIRED', message: '请登录' } })); }
    if (req.method === 'DELETE') { actions.push('delete'); res.writeHead(204); return void res.end(); }
    res.writeHead(404); res.end();
  }));
  const bridgeUrl = await listen(createServer({ upstreamUrl, upstreamKey: 'upstream-key', key: 'bridge-key' }));
  const headers = { Authorization: 'Bearer bridge-key', 'Content-Type': 'application/json' };
  const status = await fetch(`${bridgeUrl}/health`, { headers });
  assert.equal(status.status, 503);
  const answer = await fetch(`${bridgeUrl}/v1/chat/completions`, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'chaoxing-course-ai', messages: [{ role: 'user', content: '你好' }] }),
  });
  assert.equal(answer.status, 503);
  assert.equal((await answer.json()).error.code, 'LOGIN_REQUIRED');
  assert.deepEqual(actions, ['create', 'chat', 'delete']);
});

// Would fail if the bridge reports an answer as successful while an upstream
// session is still leaked (or automatically resends an uncertain question).
test('failed session cleanup refuses success without resending the chat', async () => {
  let sends = 0, deletes = 0;
  const upstreamUrl = await listen(http.createServer((req, res) => {
    if (req.url === '/api/sessions') { res.writeHead(201); return void res.end(JSON.stringify({ session_id: 's1' })); }
    if (req.url === '/api/chat') { sends++; return void res.end(JSON.stringify({ session_id: 's1', answer: '一次发送的答复' })); }
    if (req.method === 'DELETE') { deletes++; res.writeHead(503); return void res.end(JSON.stringify({ error: { code: 'UPSTREAM_BUSY' } })); }
    res.writeHead(404); res.end();
  }));
  const bridgeUrl = await listen(createServer({ upstreamUrl, upstreamKey: 'up', key: 'bridge-key' }));
  const response = await fetch(`${bridgeUrl}/v1/chat/completions`, {
    method: 'POST', headers: { Authorization: 'Bearer bridge-key', 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'chaoxing-course-ai', messages: [{ role: 'user', content: '你好' }] }),
  });
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, 'SESSION_CLEANUP_FAILED');
  assert.equal(sends, 1);
  assert.equal(deletes, 2);
});

// Would fail if stop kills an active browser mutation or accepts new work after drain.
test('drain refuses new completions until an in-flight session is released', async () => {
  let release;
  const blocked = new Promise(resolve => { release = resolve; });
  let chatStarted;
  const started = new Promise(resolve => { chatStarted = resolve; });
  const upstreamUrl = await listen(http.createServer(async (req, res) => {
    if (req.url === '/api/sessions') { res.writeHead(201); return void res.end(JSON.stringify({ session_id: 's1' })); }
    if (req.url === '/api/chat') { chatStarted(); await blocked; return void res.end(JSON.stringify({ session_id: 's1', answer: '好' })); }
    res.writeHead(204); res.end();
  }));
  const bridgeUrl = await listen(createServer({ upstreamUrl, upstreamKey: 'up', key: 'bridge-key' }));
  const options = { method: 'POST', headers: { Authorization: 'Bearer bridge-key', 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'chaoxing-course-ai', messages: [{ role: 'user', content: '你好' }] }) };
  const active = fetch(`${bridgeUrl}/v1/chat/completions`, options);
  await started;
  try {
    const drain = await fetch(`${bridgeUrl}/admin/drain`, { method: 'POST', headers: { Authorization: 'Bearer bridge-key' } });
    assert.equal((await drain.json()).active_requests, 1);
    assert.equal((await fetch(`${bridgeUrl}/v1/chat/completions`, options)).status, 503);
  } finally { release(); }
  assert.equal((await active).status, 200);
  const finished = await fetch(`${bridgeUrl}/admin/drain`, { method: 'POST', headers: { Authorization: 'Bearer bridge-key' } });
  assert.equal((await finished.json()).active_requests, 0);
});

test('streaming completion ends with a standard SSE terminator after the final answer', async () => {
  const upstreamUrl = await listen(http.createServer((req, res) => {
    if (req.url === '/api/sessions') { res.writeHead(201); return void res.end(JSON.stringify({ session_id: 's1' })); }
    if (req.url === '/api/chat') return void res.end(JSON.stringify({ session_id: 's1', answer: '可以' }));
    res.writeHead(204); res.end();
  }));
  const bridgeUrl = await listen(createServer({ upstreamUrl, upstreamKey: 'up', key: 'bridge-key' }));
  const response = await fetch(`${bridgeUrl}/v1/chat/completions`, {
    method: 'POST', headers: { Authorization: 'Bearer bridge-key', 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'chaoxing-course-ai', stream: true, messages: [{ role: 'user', content: '你好' }] }),
  });
  assert.equal(response.status, 200);
  const text = await response.text();
  assert.match(text, /"content":"可以"/);
  assert.match(text, /data: \[DONE\]\n\n$/);
});
