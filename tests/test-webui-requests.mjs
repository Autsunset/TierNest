import assert from 'node:assert/strict';
import { LatestRequest } from '../webui/src/requests.js';
import { formatLogLine, filterLogLines } from '../webui/src/log-format.js';
const tick = () => Promise.resolve();
const gate = new LatestRequest();
let reads = 0;
let finish;
const one = gate.run('overview', async current => { reads++; await new Promise(r => { finish = r; }); return current(); });
const two = gate.run('overview', () => { throw new Error('must share'); });
assert.equal(one, two); await tick(); assert.equal(reads, 1);
finish(); assert.equal(await one, true); assert.equal(gate.current, null);

const pending = [], painted = [];
const job = name => async current => { await new Promise(resolve => pending.push(resolve)); if (current()) painted.push(name); };
const old = gate.run('overview', job('old')); await tick();
const recent = gate.run('overview', job('new'), { force: true }); await tick();
pending[1](); await recent; pending[0](); await old;
assert.deepEqual(painted, ['new']);
const hidden = gate.run('logs', job('hidden')); await tick(); gate.invalidate(); pending[2](); await hidden;
assert.deepEqual(painted, ['new']);
const notStarted = gate.run('logs', () => { throw new Error('invalidated queued read must not execute'); });
gate.invalidate(); await notStarted;
await assert.rejects(gate.run('overview', () => { throw new Error('read failed'); }), /read failed/);
assert.equal(gate.current, null);
assert.equal(await gate.run('overview', () => 42), 42);

const raw = '2026-09-06 16:00:00 INFO 10.0.0.1/24 <img src=x onerror="alert(1)"> & [foo] a+b 中文';
for (const keyword of ['INFO', 'info', 'class', '<', '&', '10.0.0.1', '[foo]', 'a+b', '中文', 'INFO 10.0.0.1', '(a+)+$', '']) {
  const html = formatLogLine(raw, keyword);
  assert(!html.includes('log-token-<'));
  assert(!html.includes('<img'));
  assert.equal((html.match(/<span /g) || []).length, (html.match(/<\/span>/g) || []).length);
  for (const tag of html.match(/<[^>]+>/g)) assert.match(tag, /^<(?:div class="log-line"|span class="[a-z -]+"|\/span|\/div)>$/);
  const plaintext = html.replace(/<[^>]+>/g, '').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&amp;/g, '&');
  assert.equal(plaintext, raw, `search must not change text: ${keyword}`);
}
assert.match(formatLogLine('INFO hi', 'INFO'), /class="log-token-info log-token-highlight">INFO<\/span>/);
assert.deepEqual(filterLogLines(['a.b', 'acb', 'A+B', '[foo]'], '.'), ['a.b']);
assert.deepEqual(filterLogLines(['a.b', 'acb', 'A+B', '[foo]'], 'a+b'), ['A+B']);
assert.deepEqual(filterLogLines(['foo', '[foo]'], '[foo]'), ['[foo]']);
console.log('WebUI request and plaintext log regressions passed.');

// The 10-second status timer must not duplicate the dedicated five-second log timer.
const { readFileSync } = await import('node:fs');
const vm = await import('node:vm');
const source = readFileSync(new URL('../webui/src/main.js', import.meta.url), 'utf8');
const timers = [];
let logReads = 0;
const context = vm.createContext({
  state: { activeTab: 'tab-logs', autoRefreshLog: true },
  STATUS_REFRESH_INTERVAL_MS: 10000, LOG_REFRESH_INTERVAL_MS: 5000,
  stopStatusPolling() {}, stopLogPolling() {}, pageIsVisible: () => true,
  setInterval: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
  async loadCurrentLogs() { logReads++; },
});
vm.runInContext(source.slice(source.indexOf('async function refreshVisibleTab'), source.indexOf('function syncPollingVisibility')), context);
context.startStatusPolling(); context.startLogPolling();
for (let t = 5000; t <= 30000; t += 5000) for (const timer of timers) if (t % timer.ms === 0) await timer.fn();
assert.equal(logReads, 6, 'one log poll per five seconds, not two independent pollers');
console.log('Single log polling source regression passed.');
