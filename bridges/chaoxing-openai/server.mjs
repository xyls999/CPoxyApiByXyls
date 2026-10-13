import { createServer } from './bridge.mjs';

const key = process.env.CHAOXING_BRIDGE_KEY;
const upstreamKey = process.env.CHAOXING_SERVICE_KEY;
const upstreamUrl = process.env.CHAOXING_SERVICE_URL || 'http://127.0.0.1:8787';
const port = Number(process.env.CHAOXING_BRIDGE_PORT || '8788');
if (!key || key.length < 24 || !upstreamKey || upstreamKey.length < 24 || !Number.isInteger(port) || port < 1 || port > 65535) {
  console.error('Configure CHAOXING_BRIDGE_KEY, CHAOXING_SERVICE_KEY (24+ chars) and a valid bridge port.');
  process.exit(1);
}
const server = createServer({ key, upstreamKey, upstreamUrl });
server.listen(port, '127.0.0.1', () => console.log(`Chaoxing OpenAI bridge listening on 127.0.0.1:${port}`));
