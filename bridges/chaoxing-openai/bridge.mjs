import http from 'node:http';
import { timingSafeEqual, randomUUID } from 'node:crypto';

const MODEL = 'chaoxing-course-ai';
const MAX_BODY = 32 * 1024;
function reply(res, status, object) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(JSON.stringify(object));
}
function error(res, status, code, message) { reply(res, status, { error: { code, message, type: 'upstream_error' } }); }
function equalSecret(given, expected) {
  const a = Buffer.from(given), b = Buffer.from(`Bearer ${expected}`);
  return a.length === b.length && timingSafeEqual(a, b);
}
async function readBody(req) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) throw { status: 415, code: 'JSON_REQUIRED', message: '需要 application/json。' };
  let size = 0, parts = [];
  for await (const part of req) {
    size += part.length;
    if (size > MAX_BODY) throw { status: 413, code: 'BODY_TOO_LARGE', message: '请求体过大。' };
    parts.push(part);
  }
  try { return JSON.parse(Buffer.concat(parts).toString('utf8')); }
  catch { throw { status: 400, code: 'INVALID_JSON', message: 'JSON 格式错误。' }; }
}
function question(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || body.model !== MODEL || !Array.isArray(body.messages) || !body.messages.length || body.messages.length > 40 || (body.stream !== undefined && typeof body.stream !== 'boolean')) {
    throw { status: 400, code: 'INVALID_REQUEST', message: '模型、消息或 stream 参数无效。' };
  }
  if (body.messages.some(m => !m || !['system','user','assistant'].includes(m.role) || typeof m.content !== 'string' || !m.content.trim())) {
    throw { status: 400, code: 'UNSUPPORTED_CONTENT', message: '仅支持文本 system/user/assistant 消息。' };
  }
  if (body.messages.at(-1).role !== 'user') throw { status: 400, code: 'INVALID_MESSAGES', message: '最后一条必须是用户消息。' };
  // Upstream is session-based; replay the complete client transcript in one new
  // session rather than risk cross-client context reuse. No historical messages
  // are silently omitted. This is buffered text, not native browser context.
  const content = body.messages.length === 1 ? body.messages[0].content.trim() : body.messages.map(m => `${m.role}: ${m.content.trim()}`).join('\n\n');
  if (content.length > 4000) throw { status: 400, code: 'MESSAGE_TOO_LONG', message: '合并后的消息不能超过 4000 字符。' };
  return content;
}
function completion(content) {
  return { id: `chatcmpl-${randomUUID()}`, object: 'chat.completion', created: Math.floor(Date.now() / 1000), model: MODEL, choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: 'stop' }] };
}
function streaming(res, text) {
  const id = `chatcmpl-${randomUUID()}`;
  res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
  for (const delta of [{ role: 'assistant', content: text }, {}]) {
    res.write(`data: ${JSON.stringify({ id, object: 'chat.completion.chunk', created: Math.floor(Date.now()/1000), model: MODEL, choices: [{ index: 0, delta, finish_reason: delta.content ? null : 'stop' }] })}\n\n`);
  }
  res.end('data: [DONE]\n\n');
}

export function createServer({ upstreamUrl, upstreamKey, key }) {
  const target = new URL(upstreamUrl);
  if (target.protocol !== 'http:' || !['localhost','127.0.0.1','::1','[::1]'].includes(target.hostname) || !upstreamKey || !key) throw new Error('Both keys and a loopback upstream are required');
  async function upstream(method, path, data, timeout = 110000) {
    const response = await fetch(new URL(path, target), {
      method, headers: { Authorization: `Bearer ${upstreamKey}`, ...(data ? { 'Content-Type': 'application/json' } : {}) },
      ...(data ? { body: JSON.stringify(data) } : {}), signal: AbortSignal.timeout(timeout),
    });
    if (response.status === 204) return null;
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      const code = typeof body?.error?.code === 'string' ? body.error.code.slice(0, 64) : 'UPSTREAM_ERROR';
      const message = typeof body?.error?.message === 'string' ? body.error.message.slice(0, 250) : '上游暂时不可用。';
      throw { status: response.status >= 400 && response.status < 600 ? response.status : 502, code, message };
    }
    return body;
  }
  let draining = false, activeRequests = 0;
  return http.createServer(async (req, res) => {
    let counted = false;
    try {
      if (!equalSecret(req.headers.authorization || '', key)) return error(res, 401, 'UNAUTHORIZED', '访问密钥无效。');
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'POST' && url.pathname === '/admin/drain') {
        draining = true;
        return reply(res, 200, { draining: true, active_requests: activeRequests });
      }
      if (req.method === 'GET' && (url.pathname === '/health' || url.pathname === '/v1/models')) {
        const state = await upstream('GET', '/api/status', null, 10000);
        if (state?.upstream?.ready !== true) return error(res, 503, state?.upstream?.code || 'UPSTREAM_UNAVAILABLE', state?.upstream?.message || '课程 AI 暂不可用。');
        return reply(res, 200, url.pathname === '/health' ? { status: 'ready' } : { object: 'list', data: [{ id: MODEL, object: 'model', owned_by: 'chaoxing' }] });
      }
      if (req.method !== 'POST' || url.pathname !== '/v1/chat/completions') return error(res, 404, 'NOT_FOUND', '接口不存在。');
      if (draining) return error(res, 503, 'BRIDGE_DRAINING', '服务正在停止，暂不接受新请求。');
      activeRequests++; counted = true;
      const body = await readBody(req);
      const message = question(body);
      let sessionId, answerText;
      try {
        const created = await upstream('POST', '/api/sessions', {}, 65000);
        sessionId = created?.session_id;
        if (typeof sessionId !== 'string' || !sessionId) throw { status: 502, code: 'INVALID_SESSION', message: '上游未返回有效会话。' };
        const answer = await upstream('POST', '/api/chat', { session_id: sessionId, message });
        if (typeof answer?.answer !== 'string' || !answer.answer.trim() || answer.session_id !== sessionId) throw { status: 502, code: 'INVALID_ANSWER', message: '上游答复与当前会话不匹配。' };
        answerText = answer.answer;
      } finally {
        if (sessionId) {
          let cleanupFailure;
          for (let attempt = 0; attempt < 2; attempt++) {
            try {
              await upstream('DELETE', `/api/sessions/${encodeURIComponent(sessionId)}`, null, 15000);
              cleanupFailure = undefined; break;
            } catch (e) {
              if (e?.status === 404 && e?.code === 'SESSION_NOT_FOUND') { cleanupFailure = undefined; break; }
              cleanupFailure = e;
            }
          }
          if (cleanupFailure) {
            console.warn('Chaoxing session cleanup failed after two attempts (no key or prompt logged)');
            throw { status: 502, code: 'SESSION_CLEANUP_FAILED', message: '会话清理失败；问题可能已经发送，请勿自动重试。' };
          }
        }
      }
      if (body.stream) streaming(res, answerText);
      else reply(res, 200, completion(answerText));
    } catch (e) {
      if (!res.headersSent) error(res, e?.status || 502, e?.code || 'UPSTREAM_UNAVAILABLE', e?.message && e?.status ? e.message : '上游请求失败。');
    } finally {
      if (counted) activeRequests--;
    }
  });
}
