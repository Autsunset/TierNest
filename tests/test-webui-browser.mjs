import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, mkdir, writeFile } from 'node:fs/promises';
import os from 'node:os';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const chromePath = process.env.CHROME_BIN || '/usr/bin/google-chrome';
const profileDir = await mkdtemp(path.join(os.tmpdir(), 'tiernest-chrome-'));
const port = await new Promise(resolve => {
  const probe = net.createServer();
  probe.listen(0, '127.0.0.1', () => {
    const freePort = probe.address().port;
    probe.close(() => resolve(freePort));
  });
});
const pageUrl = pathToFileURL(path.join(root, 'module/webroot/index.html')).href;
const privateConfig = await readFile(path.join(root, 'tests/fixtures/webui-config.toml'), 'utf8');
const configB64 = Buffer.from(privateConfig, 'utf8').toString('base64');
const chrome = spawn(chromePath, [
  '--headless', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
  '--remote-allow-origins=*', `--remote-debugging-port=${port}`,
  `--user-data-dir=${profileDir}`, '--window-size=412,915', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitForJson(pathname) {
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}${pathname}`);
      if (res.ok) return await res.json();
    } catch {}
    await sleep(100);
  }
  throw new Error('Chrome DevTools endpoint did not start');
}

let socket;
let nextId = 1;
const pending = new Map();
function send(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}
async function evaluate(expression) {
  const response = await send('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (response.exceptionDetails) throw new Error(response.exceptionDetails.text);
  return response.result?.value;
}

try {
  const targets = await waitForJson('/json');
  const page = targets.find((target) => target.type === 'page');
  assert(page?.webSocketDebuggerUrl);
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const waiter = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) waiter.reject(new Error(message.error.message));
      else waiter.resolve(message.result || {});
    }
  });

  await send('Runtime.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 412, height: 915, deviceScaleFactor: 1, mobile: true });
  const mockSource = `
    var __tiernestCommands = [];
    var __tiernestConfigB64 = ${JSON.stringify(configB64)};
    var __topologyEmpty = false;
    var __hotspotAccessEnabled = false;
    var __routeStrategy = 'legacy';
    var ksu = {
      enableEdgeToEdge: function() {},
      toast: function(message) { globalThis.__tiernestLastToast = String(message); },
      moduleInfo: function() { return JSON.stringify({ id: 'tiernest', name: 'TierNest Core Example Private', version: '1.0.0-et2.6.4-Example.private', versionCode: 100000, author: 'TierNest Contributors', description: 'A deliberately very long module description that must never expand the blue version badge on first paint', updateJson: 'https://example.invalid/very/long/update/path' }); },
      exec: function(command, options, callbackName) {
        __tiernestCommands.push(String(command));
        if (globalThis.__rootTestHook) {
          var override = globalThis.__rootTestHook(String(command));
          if (override) {
            setTimeout(function() { globalThis[callbackName](override.errno || 0, override.stdout || '', override.stderr || ''); }, override.delay || 0);
            return;
          }
        }
        var stdout = '', stderr = '', errno = 0;
        if (command.indexOf('topology-json') >= 0) stdout = JSON.stringify(__topologyEmpty ? [] : [
          { ipv4: '10.42.0.10/24', hostname: 'Example-Phone-A', proxy_cidrs: '', next_hop_ipv4: '-', next_hop_hostname: 'Local', path_len: 0, path_latency: 0, version: '2.6.4' },
          { ipv4: '10.42.0.1/24', hostname: 'Example-Gateway', proxy_cidrs: '192.168.50.0/24', next_hop_ipv4: 'DIRECT', next_hop_hostname: 'DIRECT', path_len: 1, path_latency: 42, version: '2.6.4' },
          { ipv4: '10.42.0.52/24', hostname: 'Example-Phone-B', proxy_cidrs: '', next_hop_ipv4: '10.42.0.1/24', next_hop_hostname: 'PublicServer_Shenzhen', path_len: 2, path_latency: 76, version: '2.6.4' },
          { ipv4: '10.42.0.51/24', hostname: 'Example-Tablet', proxy_cidrs: '', next_hop_ipv4: '10.42.0.1/24', next_hop_hostname: 'Example-Gateway', path_len: 2, path_latency: 68, version: '2.6.4' },
          { ipv4: '10.42.0.77/24', hostname: 'Node-Empty-Coords', proxy_cidrs: '', next_hop_ipv4: 'DIRECT', next_hop_hostname: 'DIRECT', path_len: 1, path_latency: 55, version: '2.6.4' },
          { ipv4: '10.42.0.88/24', hostname: 'Node-UnknownHop', proxy_cidrs: '', next_hop_ipv4: '10.42.0.250', next_hop_hostname: 'Unknown-Router', path_len: 3, path_latency: 110, version: '2.6.4' },
          { ipv4: '10.42.0.99/24', hostname: 'Node-Unconfigured', proxy_cidrs: '', next_hop_ipv4: 'DIRECT', next_hop_hostname: 'DIRECT', path_len: 1, path_latency: 95, version: '2.6.4' },
          { ipv4: '', hostname: 'PublicServer_Shenzhen', proxy_cidrs: '', next_hop_ipv4: 'DIRECT', next_hop_hostname: 'DIRECT', path_len: 1, path_latency: 120, version: '2.6.4' }
        ]) + '\\n';
        else if (command.indexOf('route-strategy-official') >= 0) {
          __routeStrategy = 'official';
          stdout = 'strategy=official\\nroute_mode=upstream\\nandroid_table_mirroring=0\\nrestarted=1\\n';
        }
        else if (command.indexOf('route-strategy-legacy') >= 0) {
          __routeStrategy = 'legacy';
          stdout = 'strategy=legacy\\nroute_mode=dedicated\\nandroid_table_mirroring=1\\nrestarted=1\\n';
        }
        else if (command.indexOf('route-strategy-status') >= 0) {
          stdout = __routeStrategy === 'legacy'
            ? 'strategy=legacy\\nstrategy_default=legacy\\nroute_mode=dedicated\\nandroid_table_mirroring=1\\n'
            : 'strategy=official\\nstrategy_default=legacy\\nroute_mode=upstream\\nandroid_table_mirroring=0\\n';
        }
        else if (command.indexOf('hotspot-access-enable') >= 0) {
          __hotspotAccessEnabled = true;
          stdout = 'enabled=1\\nactive=1\\nstatus=active\\ninterface=ap0\\ncidr=192.168.43.0/24\\ntun=tiernest0\\ntarget_count=2\\nclient_count=1\\nerror_detail=\\n';
        }
        else if (command.indexOf('hotspot-access-disable') >= 0) {
          __hotspotAccessEnabled = false;
          stdout = 'enabled=0\\nactive=0\\nstatus=disabled\\ninterface=ap0\\ncidr=192.168.43.0/24\\ntun=tiernest0\\ntarget_count=0\\nclient_count=1\\nerror_detail=\\n';
        }
        else if (command.indexOf('hotspot-access-reapply') >= 0 || command.indexOf('hotspot-access-status') >= 0) {
          stdout = __hotspotAccessEnabled
            ? 'enabled=1\\nactive=1\\nstatus=active\\ninterface=ap0\\ncidr=192.168.43.0/24\\ntun=tiernest0\\ntarget_count=2\\nclient_count=1\\nerror_detail=\\n'
            : 'enabled=0\\nactive=0\\nstatus=disabled\\ninterface=ap0\\ncidr=192.168.43.0/24\\ntun=tiernest0\\ntarget_count=0\\nclient_count=1\\nerror_detail=\\n';
        }
        else if (command.indexOf('control.sh overview') >= 0) stdout = 'schema=1\\n' + 'state=running\\npid=24219\\ntun=tiernest0\\nframework=KernelSU\\nroute_guard=1\\nroute_table=20110\\nrule_priority=9980\\nexternal_vpn=tun0=172.19.0.1/30,\\nauto_restart_on_vpn_change=1\\nnetwork_name=Example-Network\\nvirtual_ipv4=10.42.0.10/24\\nconfig_mode=toml\\nmodule_version=1.0.0\\n'.split('\\n').filter(Boolean).map(line => 'status.' + line).join('\\n') + '\\n' + 'cpu_percent=1.4\\nrss_kb=38240\\nvm_kb=186400\\nthreads=14\\nfd_count=36\\nruntime_seconds=8642\\ntun_rx_bytes=38742414\\ntun_tx_bytes=19278103\\nmodule_log_bytes=4223\\ncore_log_bytes=82911\\nnetwork_log_bytes=148332\\nhotspot_log_bytes=2048\\ntransport_log_bytes=1024\\nlog_total_bytes=238538\\nmodule_size_bytes=8732672\\nvpn_restart_count=2\\nhealth_restart_count=1\\nroute_sync_count=9\\nroute_count=2\\nlocal_route_override_count=1\\ntransport_endpoint_count=2\\nlast_recovery_reason=external-vpn-change\\nlast_recovery_status=success\\nlast_recovery_duration=6\\n'.split('\\n').filter(Boolean).map(line => 'metrics.' + line).join('\\n') + '\\n';
        else if (command.indexOf('config-read-b64') >= 0) stdout = __tiernestConfigB64 + '\\n';
        else if (command.indexOf('config-validate-b64') >= 0) stdout = 'valid=1\\n';
        else if (command.indexOf('config-save-b64') >= 0) stdout = 'saved=/data/adb/modules/tiernest/config/config.toml\\nbackup=/sdcard/Download/TierNest/backups/config-test.toml\\n';
        else if (command.indexOf('config-backup') >= 0) stdout = '/sdcard/Download/TierNest/backups/config-test.toml\\n';
        else if (command.indexOf('export-log') >= 0) stdout = '/sdcard/Download/TierNest-diagnostics-test.txt\\n';
        else if (command.indexOf('tail -n') >= 0) stdout = '2026-08-29 10:00:00 EasyTier started pid=24219 mode=配置模式\\n2026-08-29 10:00:03 Reconciled 2 route(s) in table=20110 dev=tiernest0\\n';
        else stdout = 'ok\\n';
        var callbackDelay = command.indexOf('control.sh overview') >= 0 ? 350 : 0;
        setTimeout(function() { globalThis[callbackName](errno, stdout, stderr); }, callbackDelay);
      }
    };
    globalThis.ksu = ksu;
  `;
  await send('Page.addScriptToEvaluateOnNewDocument', { source: mockSource });
  await send('Page.navigate', { url: pageUrl });
  for (let i = 0; i < 60; i++) {
    if (await evaluate(`Boolean(document.getElementById('module-version-badge')) && globalThis.__tiernestCommands?.length > 0`)) break;
    await sleep(50);
  }
  assert((await evaluate(`globalThis.__tiernestCommands?.length || 0`)) > 0, 'WebUI should initialize');
  assert.equal(await evaluate(`document.getElementById('module-version-badge').textContent.trim()`), 'v1.0.0');
  assert.equal(await evaluate(`document.getElementById('module-version-badge').scrollWidth <= 95`), true);
  await sleep(1000);

  const errors = await evaluate(`Array.from(document.querySelectorAll('.toast-item.error')).map(e => e.textContent)`);
  assert.deepEqual(errors, []);
  assert.equal(await evaluate(`document.querySelector('#global-state-pill .state-text').textContent.trim()`), '运行中');
  assert.equal(await evaluate(`document.getElementById('metric-cpu').textContent.trim()`), '1.4%');
  assert.match(await evaluate(`document.getElementById('metric-rss').textContent.trim()`), /MB/);
  assert.equal(await evaluate(`document.getElementById('stat-network').textContent.trim()`), 'Example-Network');
  assert.match(await evaluate(`document.getElementById('stat-route').textContent.trim()`), /本地直连 1/);
  assert.equal(await evaluate(`document.getElementById('metric-vpn-restarts').textContent.trim()`), '3 次重启');

  // Real routing tree: no maps, coordinates, or geography calls remain.
  assert.equal(await evaluate(`document.querySelectorAll('[data-topology-view], #topology-edit-locations-btn, #topology-location-modal, .topology-map-country').length`), 0);
  assert.equal(await evaluate(`globalThis.__tiernestCommands.some(c => c.includes('topology-locations'))`), false);
  assert.match(await evaluate(`document.querySelector('.topology-route-note').textContent`), /不代表全网所有物理链路/);
  assert.match(await evaluate(`document.getElementById('topology-summary-title').textContent`), /Example-Phone-A 的路由拓扑/);
  assert.equal(await evaluate(`document.getElementById('topology-node-count').textContent`), '8 个节点');
  assert.equal(await evaluate(`document.querySelectorAll('#topology-svg .topology-node').length`), 10); // 8 records + unknown next-hop placeholder + subnet
  const rendered = await evaluate(`Array.from(document.querySelectorAll('#topology-svg .topology-node')).map(n => ({id: n.dataset.nodeId, name: n.querySelector('title').textContent.split('\\n')[0], x: +n.dataset.topologyX, y: +n.dataset.topologyY, depth: +n.dataset.topologyDepth, reported: n.dataset.reported}))`);
  assert(rendered.every((n,i) => n.x >= 16 && (!i || n.y >= rendered[i-1].y + 80)));
  const idFor = (name) => rendered.find(n => n.name === name)?.id;
  const connectionEdges = await evaluate(`Array.from(document.querySelectorAll('#topology-svg .topology-edge')).map(e => ({from: e.dataset.edgeFrom, to: e.dataset.edgeTo, uncertain: e.dataset.uncertain, folded: e.classList.contains('is-folded')}))`);
  for (const [from,to] of [['Example-Phone-A','Example-Gateway'],['Example-Phone-A','PublicServer_Shenzhen'],['PublicServer_Shenzhen','Example-Phone-B'],['Example-Gateway','Example-Tablet']]) {
    const e = connectionEdges.find(e => e.from === idFor(from) && e.to === idFor(to));
    assert(e, `${from} → ${to}`); assert.equal(e.uncertain, 'false');
  }
  assert.equal(rendered.find(n => n.name === 'Unknown-Router').reported, 'false');
  assert.equal(connectionEdges.find(e => e.to === idFor('Node-UnknownHop')).uncertain, 'true');
  assert.equal(await evaluate(`document.querySelectorAll('#topology-virtual-nodes-list .topology-node-card').length`), 7);
  const virtualNodesText = await evaluate(`document.getElementById('topology-virtual-nodes-list').textContent`);
  assert.match(virtualNodesText, /Example-Phone-A → PublicServer_Shenzhen → Example-Phone-B/);
  assert.match(virtualNodesText, /Example-Phone-A → Example-Gateway → Example-Tablet/);
  assert.match(virtualNodesText, /Unknown-Router → … → Node-UnknownHop/);
  assert.doesNotMatch(virtualNodesText, /地图坐标|位置标注|经纬度/);
  assert.equal(await evaluate(`document.getElementById('topology-section').scrollWidth <= document.getElementById('topology-section').clientWidth + 1`), true);
  assert.equal(await evaluate(`document.getElementById('topology-viewport').scrollWidth <= document.getElementById('topology-viewport').clientWidth + 1`), true);
  assert.equal(await evaluate(`document.getElementById('topology-viewport').scrollHeight > document.getElementById('topology-viewport').clientHeight`), true);

  await evaluate(`Array.from(document.querySelectorAll('.topology-node-card')).find(c => c.querySelector('.topology-node-card-name')?.textContent === 'Example-Gateway').click()`);
  assert.match(await evaluate(`document.getElementById('topology-detail').textContent`), /192\.168\.50\.0\/24/);
  assert.equal(await evaluate(`document.querySelector('.topology-node.is-selected')?.getAttribute('aria-pressed')`), 'true');
  assert((await evaluate(`document.querySelectorAll('.topology-edge.is-path').length`)) > 0);
  // Keyboard selection must work on a node, without a mouse-only tooltip dependency.
  await evaluate(`Array.from(document.querySelectorAll('#topology-svg .topology-node')).find(n => n.getAttribute('aria-label').includes('Example-Phone-B')).dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))`);
  assert.match(await evaluate(`document.getElementById('topology-detail').textContent`), /经公网服务器 PublicServer_Shenzhen/);

  await evaluate(`document.querySelector('[data-topology-filter="virtual_only"]').click()`);
  assert.equal(await evaluate(`localStorage.getItem('tiernest_topology_filter')`), 'virtual_only');
  assert.equal(await evaluate(`document.querySelectorAll('#topology-svg .topology-node.public').length`), 0);
  assert.equal(await evaluate(`document.querySelectorAll('#topology-virtual-nodes-list .topology-node-card').length`), 7);
  const foldedEdges = await evaluate(`Array.from(document.querySelectorAll('#topology-svg .topology-edge')).map(e => ({from:e.dataset.edgeFrom,to:e.dataset.edgeTo,folded:e.classList.contains('is-folded'),uncertain:e.dataset.uncertain}))`);
  assert.equal(foldedEdges.find(e => e.to === idFor('Example-Phone-B')).folded, true);
  assert.equal(foldedEdges.find(e => e.to === idFor('Example-Gateway')).uncertain, 'false');
  assert.equal(foldedEdges.find(e => e.to === idFor('Example-Gateway')).folded, false);
  await evaluate(`document.querySelector('[data-topology-filter="all"]').click()`);
  // Refresh must not reset the user's scroll position or selected route.
  await evaluate(`document.getElementById('topology-viewport').scrollTop = 140; document.getElementById('topology-refresh-btn').click()`);
  await sleep(220);
  assert.equal(await evaluate(`document.getElementById('topology-viewport').scrollTop`), 140);
  assert.match(await evaluate(`document.querySelector('.topology-node.is-selected').getAttribute('aria-label')`), /Example-Phone-B/);
  await evaluate(`__topologyEmpty = true; document.getElementById('topology-refresh-btn').click()`);
  await sleep(220);
  assert.equal(await evaluate(`document.querySelectorAll('#topology-svg .topology-node').length`), 0);
  assert.equal(await evaluate(`document.getElementById('topology-detail').textContent`), '');
  await evaluate(`__topologyEmpty = false; document.getElementById('topology-refresh-btn').click()`);
  await sleep(220);

  for (const width of [360, 768, 412]) {
    await send('Emulation.setDeviceMetricsOverride', { width, height: 915, deviceScaleFactor: 1, mobile: true });
    await sleep(60);
    assert.equal(await evaluate(`document.documentElement.scrollWidth <= window.innerWidth + 1`), true, `page should fit ${width}px`);
    assert.equal(await evaluate(`document.getElementById('topology-viewport').scrollWidth <= document.getElementById('topology-viewport').clientWidth + 1`), true, `tree should fit ${width}px`);
  }

  if (process.env.SCREENSHOT_DIR) {
    await mkdir(process.env.SCREENSHOT_DIR, { recursive: true });
    await evaluate(`document.getElementById('topology-section').scrollIntoView(); document.getElementById('topology-viewport').scrollTop = 0`);
    await sleep(200);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    await writeFile(path.join(process.env.SCREENSHOT_DIR, 'topology-routing-tree.png'), Buffer.from(shot.data, 'base64'));
    await evaluate(`window.scrollTo(0, 0)`);
  }

  assert.match(await evaluate(`document.getElementById('metric-health-detail').textContent.trim()`), /端点 2/);
  assert.match(await evaluate(`document.getElementById('metric-health-detail').title`), /external-vpn-change \/ success \/ 6s/);
  assert.equal(await evaluate(`document.documentElement.dataset.tiernestPolling`), 'active');
  const commandsBeforeVisibilityResume = await evaluate(`globalThis.__tiernestCommands.length`);
  await evaluate(`Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' }); document.dispatchEvent(new Event('visibilitychange'));`);
  assert.equal(await evaluate(`document.documentElement.dataset.tiernestPolling`), 'paused');
  await evaluate(`Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' }); document.dispatchEvent(new Event('visibilitychange'));`);
  await sleep(500);
  assert.equal(await evaluate(`document.documentElement.dataset.tiernestPolling`), 'active');
  assert((await evaluate(`globalThis.__tiernestCommands.length`)) > commandsBeforeVisibilityResume);
  let sectionIconSizes = await evaluate(`Array.from(document.querySelectorAll('#tab-overview .section-title > svg')).map(svg => ({w: svg.getBoundingClientRect().width, h: svg.getBoundingClientRect().height}))`);
  assert(sectionIconSizes.length >= 2);
  assert(sectionIconSizes.every(({w, h}) => w <= 20 && h <= 20));
  let oversized = await evaluate(`Array.from(document.querySelectorAll('#tab-overview svg:not(.topology-svg)')).map(svg => ({w: svg.getBoundingClientRect().width, h: svg.getBoundingClientRect().height, visible: !!svg.offsetParent})).filter(x => x.visible && (x.w > 64 || x.h > 64))`);
  assert.deepEqual(oversized, []);

  await evaluate(`document.getElementById('nav-tab-settings').click()`);
  await sleep(200);
  assert.equal(await evaluate(`document.getElementById('tab-settings').classList.contains('is-active')`), true);
  assert.equal(await evaluate(`document.getElementById('cfg-instance-name').value`), 'default');
  assert.match(await evaluate(`document.querySelector('label[for="cfg-dev-name"] ~ .form-hint').textContent`), /自动分配 tunX/);

  // Persistent route strategy switch performs a one-click restart.
  assert.equal(await evaluate(`document.getElementById('route-strategy-legacy-btn').classList.contains('is-active')`), true);
  assert.match(await evaluate(`document.getElementById('route-strategy-summary').textContent`), /Android 网络表镜像已启用/);
  await evaluate(`document.getElementById('route-strategy-official-btn').click()`);
  await sleep(250);
  assert.equal(await evaluate(`document.getElementById('route-strategy-official-btn').classList.contains('is-active')`), true);
  let routeCommands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(routeCommands.some((command) => command.includes('route-strategy-official')));
  await evaluate(`document.getElementById('route-strategy-legacy-btn').click()`);
  await sleep(250);
  assert.equal(await evaluate(`document.getElementById('route-strategy-legacy-btn').classList.contains('is-active')`), true);

  // Outbound-only hotspot access is opt-in and explicitly one-way.
  assert.equal(await evaluate(`document.getElementById('hotspot-access-toggle').checked`), false);
  assert.match(await evaluate(`document.querySelector('.hotspot-access-safety-note').textContent`), /ESTABLISHED,RELATED/);
  await evaluate(`document.getElementById('hotspot-access-toggle').click()`);
  await sleep(220);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-toggle').checked`), true);
  assert.match(await evaluate(`document.getElementById('hotspot-access-badge-text').textContent`), /运行中/);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-targets').textContent`), '2 个');
  let hotspotCommands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(hotspotCommands.some((command) => command.includes('hotspot-access-enable')));

  // Verify KCP / smoltcp switches and dynamic combo hint
  assert.equal(await evaluate(`document.getElementById('cfg-flag-kcp-proxy').checked`), true);
  assert.equal(await evaluate(`document.getElementById('cfg-flag-smoltcp').checked`), false);
  assert.equal(await evaluate(`document.getElementById('kcp-smoltcp-combo-hint').classList.contains('is-warning')`), true);
  assert.match(await evaluate(`document.getElementById('kcp-smoltcp-combo-title').textContent`), /高风险警告/);

  // Switch KCP off -> safe state
  await evaluate(`document.getElementById('cfg-flag-kcp-proxy').click()`);
  assert.equal(await evaluate(`document.getElementById('kcp-smoltcp-combo-hint').classList.contains('is-safe')`), true);
  assert.match(await evaluate(`document.getElementById('kcp-smoltcp-combo-title').textContent`), /推荐配置/);

  // Switch KCP on + smoltcp on -> compat mode
  await evaluate(`document.getElementById('cfg-flag-kcp-proxy').click()`);
  await evaluate(`document.getElementById('cfg-flag-smoltcp').click()`);
  assert.equal(await evaluate(`document.getElementById('kcp-smoltcp-combo-hint').classList.contains('is-compat')`), true);
  assert.match(await evaluate(`document.getElementById('kcp-smoltcp-combo-title').textContent`), /兼容模式/);

  await evaluate(`document.getElementById('cfg-hostname').value = 'WebUI-Test-Phone'`);
  await evaluate(`document.getElementById('cfg-dev-name').value = ''`);
  await evaluate(`document.getElementById('cfg-action-validate').click()`);
  await sleep(250);
  let commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  const validateCommand = commands.findLast((command) => command.includes('config-validate-b64'));
  assert(validateCommand);
  let payload = validateCommand.trim().split(/\s+/).at(-1);
  let decoded = Buffer.from(payload, 'base64').toString('utf8');
  assert.match(decoded, /hostname = "WebUI-Test-Phone"/);
  assert.match(decoded, /dev_name = ""/);
  assert.match(decoded, /enable_kcp_proxy = true/);
  assert.match(decoded, /use_smoltcp = true/);
  assert.match(decoded, /custom_unknown_root = "preserve-me"/);
  assert.match(decoded, /unknown_flag = "preserve-this-too"/);

  await evaluate(`document.getElementById('cfg-action-save').click()`);
  await sleep(250);
  commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  const saveCommand = commands.findLast((command) => command.includes('config-save-b64'));
  assert(saveCommand);
  let savePayload = saveCommand.trim().split(/\s+/).at(-1);
  let saveDecoded = Buffer.from(savePayload, 'base64').toString('utf8');
  assert.match(saveDecoded, /dev_name = ""/);
  assert.match(saveDecoded, /enable_kcp_proxy = true/);
  assert.match(saveDecoded, /use_smoltcp = true/);
  await evaluate(`document.getElementById('cfg-action-backup').click()`);
  await sleep(200);
  commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(commands.some((command) => command.includes('config-backup')));
  assert.match(await evaluate(`document.getElementById('toast-container').textContent`), /Download\/TierNest\/backups\/config-test\.toml/);

  await evaluate(`document.getElementById('cfg-action-save-restart').click()`);
  await sleep(100);
  await evaluate(`document.getElementById('modal-confirm-btn').click()`);
  await sleep(350);
  commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(commands.some((command) => /control\.sh restart$/.test(command)));

  await evaluate(`document.getElementById('nav-tab-logs').click()`);
  await sleep(200);
  assert.equal(await evaluate(`document.getElementById('tab-logs').classList.contains('is-active')`), true);
  assert.match(await evaluate(`document.getElementById('log-output-container').textContent`), /EasyTier started/);
  await evaluate(`document.querySelector('[data-log-target="transport"]').click()`);
  await sleep(180);
  commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(commands.some((command) => command.includes('/logs/transport.log')));
  await evaluate(`document.querySelector('[data-log-target="hotspot"]').click()`);
  await sleep(180);
  commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(commands.some((command) => command.includes('/logs/hotspot.log')));

  await evaluate(`document.getElementById('nav-tab-overview').click()`);
  await evaluate(`document.querySelector('[data-control-cmd="export-log"]').click()`);
  await sleep(200);
  assert.match(await evaluate(`document.getElementById('export-path-text').textContent`), /TierNest-diagnostics-test\.txt/);
  commands = await evaluate(`globalThis.__tiernestCommands.slice()`);
  assert(commands.some((command) => command.includes('export-log')));

  // v1.0 failure/concurrency regressions against the real bundled UI.
  await sleep(700);
  const beforeOverviewBurst = await evaluate(`__tiernestCommands.filter(c => c.includes('control.sh overview')).length`);
  await evaluate(`globalThis.__rootTestHook = c => c.includes('control.sh overview') ? {delay: 120, stdout: 'schema=1\\nstatus.state=running\\nstatus.network_name=SHARED\\nmetrics.cpu_percent=1.0\\n'} : null; for (let i=0;i<8;i++) document.getElementById('global-refresh-btn').click()`);
  await sleep(200);
  assert.equal(await evaluate(`__tiernestCommands.filter(c => c.includes('control.sh overview')).length`), beforeOverviewBurst + 1);
  assert.equal(await evaluate(`__tiernestCommands.some(c => /control\.sh (status|metrics)$/.test(c))`), false, 'overview should be one bridge call');

  // A read from before backgrounding cannot overwrite the newer resume snapshot.
  await evaluate(`globalThis.__overviewReadNo = 0; globalThis.__rootTestHook = c => {
    if (!c.includes('control.sh overview')) return null;
    const old = ++globalThis.__overviewReadNo === 1;
    return {delay: old ? 260 : 10, stdout: 'schema=1\\nstatus.state=running\\nstatus.network_name='+(old ? 'OLD' : 'NEW')+'\\nmetrics.cpu_percent=1.0\\n'};
  }; document.getElementById('global-refresh-btn').click()`);
  await sleep(30);
  await evaluate(`Object.defineProperty(document, 'visibilityState', {configurable:true,value:'hidden'}); document.dispatchEvent(new Event('visibilitychange')); Object.defineProperty(document, 'visibilityState', {configurable:true,value:'visible'}); document.dispatchEvent(new Event('visibilitychange'))`);
  await sleep(340);
  assert.equal(await evaluate(`document.getElementById('stat-network').textContent`), 'NEW');
  await evaluate(`globalThis.__rootTestHook = c => c.includes('control.sh overview') ? {errno:1,stderr:'RPC read failed'} : null; document.getElementById('global-refresh-btn').click()`);
  await sleep(60);
  assert.equal(await evaluate(`document.querySelector('#global-state-pill .state-text').textContent`), '读取失败');
  await evaluate(`globalThis.__rootTestHook = c => c.includes('control.sh overview') ? {stdout:'schema=1\\nstatus.state=stopped\\n'} : null; document.getElementById('global-refresh-btn').click()`);
  await sleep(60);
  assert.equal(await evaluate(`document.querySelectorAll('#topology-svg .topology-node').length`), 0);
  await evaluate(`globalThis.__rootTestHook = null; document.getElementById('global-refresh-btn').click()`);
  await sleep(420);

  await evaluate(`document.getElementById('nav-tab-settings').click()`);
  await sleep(100);
  // Start from disabled; failed enable must perform a real status read after releasing busy.
  if (await evaluate(`document.getElementById('hotspot-access-toggle').checked`)) {
    await evaluate(`document.getElementById('hotspot-access-toggle').click()`); await sleep(80);
  }
  const beforeHotspotFailure = await evaluate(`__tiernestCommands.filter(c=>c.includes('hotspot-access-status')).length`);
  await evaluate(`globalThis.__rootTestHook = c => c.includes('hotspot-access-enable') ? {errno:1,stderr:'mock enable failed',delay:20} : null; document.getElementById('hotspot-access-toggle').click()`);
  await sleep(140);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-toggle').checked`), false);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-toggle').disabled`), false);
  assert((await evaluate(`__tiernestCommands.filter(c=>c.includes('hotspot-access-status')).length`)) > beforeHotspotFailure);
  // Old status reply cannot undo a successful enable.
  await evaluate(`globalThis.__rootTestHook = c => c.includes('hotspot-access-status') ? {delay:220,stdout:'enabled=0\\nactive=0\\nstatus=disabled\\n'} : null; document.getElementById('hotspot-access-refresh-btn').click()`);
  await sleep(20);
  await evaluate(`document.getElementById('hotspot-access-toggle').click()`);
  await sleep(280);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-toggle').checked`), true);
  // Failed enable AND status read: show uncertainty, never leave an optimistic switch on.
  await evaluate(`globalThis.__rootTestHook=null; document.getElementById('hotspot-access-toggle').click()`);
  await sleep(80);
  await evaluate(`globalThis.__rootTestHook = c => /hotspot-access-(enable|status)/.test(c) ? {errno:1,stderr:'mock unavailable'} : null; document.getElementById('hotspot-access-toggle').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-toggle').checked`), false);
  assert.equal(await evaluate(`document.getElementById('hotspot-access-badge-text').textContent`), '状态未确认');

  // Config actions are serialized in the UI as well as in the backend.
  const beforeSaveBurst = await evaluate(`__tiernestCommands.filter(c=>c.includes('config-save-b64')).length`);
  const beforeBackupBurst = await evaluate(`__tiernestCommands.filter(c=>c.includes('config-backup')).length`);
  await evaluate(`globalThis.__rootTestHook = c => c.includes('config-save-b64') ? {delay:180,stdout:'saved=config.toml\\nbackup=config-unique.toml\\n'} : null; document.getElementById('cfg-action-save').click(); document.getElementById('cfg-action-save').click(); document.getElementById('cfg-action-backup').click()`);
  await sleep(240);
  assert.equal(await evaluate(`__tiernestCommands.filter(c=>c.includes('config-save-b64')).length`), beforeSaveBurst+1);
  assert.equal(await evaluate(`__tiernestCommands.filter(c=>c.includes('config-backup')).length`), beforeBackupBurst);
  assert.equal(await evaluate(`document.getElementById('cfg-action-save').disabled`), false);

  // Raw editor actions must never silently replace edits with a stale visual form.
  await evaluate(`globalThis.__rootTestHook=null; document.getElementById('view-mode-toml-btn').click(); document.getElementById('toml-raw-editor').value='hostname="RAW_EDIT"\\ncustom_raw=42\\n'; document.getElementById('view-mode-toml-btn').click()`);
  assert.match(await evaluate(`document.getElementById('toml-raw-editor').value`), /RAW_EDIT/);
  await evaluate(`document.getElementById('editor-format-btn').click()`);
  assert.match(await evaluate(`document.getElementById('toml-raw-editor').value`), /custom_raw = 42/);
  assert.equal(await evaluate(`document.getElementById('config-error-alert-banner').style.display`), 'none');
  assert.doesNotMatch(await evaluate(`document.getElementById('toml-raw-editor').value`), /network_identity|flags/);
  await evaluate(`document.getElementById('toml-raw-editor').value='hostname = ['; document.getElementById('view-mode-visual-btn').click()`);
  assert.equal(await evaluate(`document.getElementById('view-mode-toml-btn').classList.contains('is-active')`), true);
  assert.equal(await evaluate(`document.getElementById('toml-raw-editor').value`), 'hostname = [');
  await evaluate(`document.getElementById('cfg-action-reload').click()`);
  await sleep(100);

  await evaluate(`globalThis.__rootTestHook=null; document.getElementById('nav-tab-logs').click()`);
  await sleep(80);
  await evaluate(`globalThis.__rootTestHook = c => c.includes('/logs/tiernest.log') ? {delay:220,stdout:'OLD_MODULE_LOG'} : c.includes('/logs/transport.log') ? {delay:10,stdout:'NEW_TRANSPORT_LOG'} : null; document.querySelector('[data-log-target="tiernest"]').click()`);
  await sleep(25);
  await evaluate(`document.querySelector('[data-log-target="transport"]').click()`);
  await sleep(300);
  assert.match(await evaluate(`document.getElementById('log-active-path').textContent`), /transport.log/);
  assert.equal(await evaluate(`document.getElementById('log-output-container').textContent`), 'NEW_TRANSPORT_LOG');
  const dangerousLog = 'INFO 10.0.0.1/24 <script>test</script> & [error] a+b';
  await evaluate(`globalThis.__rootTestHook = c => c.includes('tail -n') ? {stdout:${JSON.stringify(dangerousLog)}} : null; document.getElementById('log-refresh-btn').click()`);
  await sleep(70);
  await evaluate(`document.getElementById('log-search-input').value='INFO'; document.getElementById('log-search-input').dispatchEvent(new Event('input'))`);
  assert.equal(await evaluate(`document.getElementById('log-output-container').textContent`), dangerousLog);
  assert.equal(await evaluate(`document.querySelector('#log-output-container .log-token-info.log-token-highlight')?.textContent`), 'INFO');
  assert.equal(await evaluate(`document.querySelectorAll('#log-output-container script').length`), 0);
  await evaluate(`document.getElementById('log-search-input').value='a+b'; document.getElementById('log-search-input').dispatchEvent(new Event('input'))`);
  assert.equal(await evaluate(`document.getElementById('log-output-container').textContent`), dangerousLog);
  await evaluate(`globalThis.__rootTestHook=null; document.getElementById('log-clear-search-btn').click()`);

  // Selectable lifecycle modes, safe numeric home inputs and stopped-page quietness.
  await evaluate(`globalThis.__serviceMode='manual'; globalThis.__manualStop='1'; globalThis.__homeSaved=false; globalThis.__homeRows=[]; globalThis.__homeNetwork='home'; globalThis.__homeDeleteFails=false;
    globalThis.__detectionMode='poll'; globalThis.__detectionInterval='30'; globalThis.__detectionFails=false;
    globalThis.__rootTestHook = c => {
      if (c.includes('home-detection-save')) {
        if (__detectionFails) return {errno:1,stderr:'mock listener unsupported'};
        var args=c.split(' '); __detectionMode=args.at(-2); __detectionInterval=args.at(-1);
        return {stdout:'ok',delay:100};
      }
      if (c.includes('service-mode-auto')) { __serviceMode='auto'; return {stdout:'ok'}; }
      if (c.includes('service-mode-manual')) { __serviceMode='manual'; return {stdout:'ok'}; }
      if (c.includes('home-learn')) {
        var row=__homeNetwork==='home' ? 'wlan0|192.168.80.1|02:01:02:03:04:05|10.80.0.1|80' : 'wlan0|192.168.0.1|02:06:07:08:09:0a|10.80.0.1|80';
        if (!__homeRows.includes(row)) __homeRows.push(row);
        __homeSaved=true; return {stdout:'ok'};
      }
      if (c.includes('home-forget')) {
        if (__homeDeleteFails) return {errno:1,stderr:'mock delete failed'};
        var id=c.split(' ').at(-1);
        __homeRows=__homeRows.filter(r=>{var a=r.split('|');return a[0]+'-'+a[1]+'-'+a[2].replaceAll(':','')!==id;});
        __homeSaved=__homeRows.length>0;
        if (!__homeSaved) __serviceMode='manual';
        return {stdout:'ok'};
      }
      if (c.includes('control.sh overview')) return {stdout:'schema=1\\nstatus.state=stopped\\nstatus.service_mode='+__serviceMode+'\\nstatus.home_detection_mode='+__detectionMode+'\\nstatus.home_check_interval='+__detectionInterval+'\\nstatus.manual_stop='+__manualStop+'\\nstatus.home_paused='+(__manualStop==='1'||__serviceMode!=='auto'?'0':'1')+'\\nstatus.home_configured='+(__homeSaved?'1':'0')+'\\nstatus.home_networks_b64='+btoa(__homeRows.join('\\n'))+'\\nstatus.home_active_id=wlan0-192.168.0.1-02060708090a\\nstatus.home_target=10.80.0.1\\nstatus.home_port=80\\nstatus.home_gateway=192.168.80.1\\n'};
      return null;
    }; document.getElementById('nav-tab-overview').click();`);
  await sleep(100);
  assert.match(await evaluate(`document.getElementById('overview-state-headline').textContent`), /已手动停止/);
  assert.equal(await evaluate(`document.documentElement.dataset.tiernestPolling`), 'paused');
  const quietCount = await evaluate(`__tiernestCommands.length`);
  await sleep(10_200);
  assert.equal(await evaluate(`__tiernestCommands.length`), quietCount, 'Manual stop must pause recurring UI reads');
  assert.equal(await evaluate(`document.getElementById('home-check-interval').value`), '30');
  const beforeInvalidInterval = await evaluate(`__tiernestCommands.filter(c=>c.includes('home-detection-save')).length`);
  for (const invalid of ['0', '-1', '1.5', '2147483648']) {
    await evaluate(`document.getElementById('home-check-interval').value=${JSON.stringify(invalid)}; document.getElementById('home-check-interval').dispatchEvent(new Event('input')); document.getElementById('home-detection-save').click()`);
  }
  assert.equal(await evaluate(`__tiernestCommands.filter(c=>c.includes('home-detection-save')).length`), beforeInvalidInterval);
  await evaluate(`document.getElementById('home-check-interval').value='300'; document.getElementById('home-check-interval').dispatchEvent(new Event('input')); document.getElementById('global-refresh-btn').click()`);
  await sleep(70);
  assert.equal(await evaluate(`document.getElementById('home-check-interval').value`), '300', 'Status reads preserve an unsaved interval');
  await evaluate(`document.getElementById('home-detection-save').click(); document.getElementById('home-detection-save').click()`);
  assert.equal(await evaluate(`document.getElementById('home-detection-select').disabled`), true);
  await sleep(200);
  assert.equal(await evaluate(`__tiernestCommands.filter(c=>c.includes('home-detection-save')).length`), beforeInvalidInterval + 1);
  assert.equal(await evaluate(`__detectionInterval`), '300');
  assert.equal(await evaluate(`__manualStop`), '1');
  await evaluate(`document.getElementById('home-detection-select').value='event'; document.getElementById('home-detection-select').dispatchEvent(new Event('change')); __detectionFails=true; document.getElementById('home-detection-save').click()`);
  await sleep(100);
  assert.equal(await evaluate(`__detectionMode`), 'poll');
  assert.equal(await evaluate(`document.getElementById('home-detection-select').value`), 'event', 'Failed saves preserve the draft');
  assert.match(await evaluate(`document.getElementById('home-detection-status').textContent`), /每 300 秒/);
  assert.equal(await evaluate(`getComputedStyle(document.getElementById('home-interval-field')).display`), 'none');
  assert.match(await evaluate(`document.getElementById('home-detection-hint').textContent`), /故障不会自动/);
  await evaluate(`__detectionFails=false; document.getElementById('home-detection-save').click()`);
  await sleep(200);
  assert.equal(await evaluate(`__detectionMode`), 'event');
  assert.equal(await evaluate(`__detectionInterval`), '300');
  await evaluate(`document.getElementById('home-detection-select').value='poll'; document.getElementById('home-detection-select').dispatchEvent(new Event('change')); document.getElementById('home-detection-save').click()`);
  await sleep(200);
  assert.notEqual(await evaluate(`getComputedStyle(document.getElementById('home-interval-field')).display`), 'none');
  assert.equal(await evaluate(`document.getElementById('home-check-interval').value`), '300');
  const beforeInvalidHome = await evaluate(`__tiernestCommands.filter(c=>c.includes('home-learn')).length`);
  await evaluate(`document.getElementById('home-network-target').value='10.80.0.1;echo BAD'; document.getElementById('home-network-learn').click()`);
  assert.equal(await evaluate(`__tiernestCommands.filter(c=>c.includes('home-learn')).length`), beforeInvalidHome);
  await evaluate(`document.getElementById('home-network-target').value='10.80.0.1'; document.getElementById('home-network-learn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`__homeSaved`), true);
  assert.equal(await evaluate(`document.querySelectorAll('.home-network-row').length`), 1);
  await evaluate(`__homeNetwork='portable'; document.getElementById('home-network-learn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.querySelectorAll('.home-network-row').length`), 2);
  assert.match(await evaluate(`document.getElementById('home-network-list').textContent`), /192\.168\.80\.1/);
  assert.match(await evaluate(`document.getElementById('home-network-list').textContent`), /192\.168\.0\.1/);
  await evaluate(`document.getElementById('home-network-learn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.querySelectorAll('.home-network-row').length`), 2);

  await evaluate(`document.getElementById('service-mode-select').value='auto'; document.getElementById('service-mode-select').dispatchEvent(new Event('change')); document.getElementById('service-mode-save').click()`);
  await sleep(100);
  assert.equal(await evaluate(`__serviceMode`), 'auto');
  assert.match(await evaluate(`document.getElementById('service-mode-status').textContent`), /已手动停止/);
  await evaluate(`__homeDeleteFails=true; document.querySelector('[data-home-network-id="wlan0-192.168.80.1-020102030405"]').click(); document.getElementById('modal-confirm-btn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.querySelectorAll('.home-network-row').length`), 2);
  await evaluate(`__homeDeleteFails=false; document.querySelector('[data-home-network-id="wlan0-192.168.80.1-020102030405"]').click(); document.getElementById('modal-confirm-btn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.querySelectorAll('.home-network-row').length`), 1);
  await evaluate(`document.querySelector('[data-home-network-id="wlan0-192.168.0.1-02060708090a"]').click(); document.getElementById('modal-confirm-btn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.querySelectorAll('.home-network-row').length`), 0);
  assert.equal(await evaluate(`document.getElementById('service-mode-select').value`), 'manual');
  assert.match(await evaluate(`document.getElementById('service-mode-status').textContent`), /已手动停止/);
  await evaluate(`__homeNetwork='home'; document.getElementById('home-network-learn').click()`);
  await sleep(80);
  await evaluate(`__homeNetwork='portable'; document.getElementById('home-network-learn').click()`);
  await sleep(80);
  await evaluate(`document.getElementById('service-mode-select').value='auto'; document.getElementById('service-mode-save').click()`);
  await sleep(100);

  await evaluate(`__manualStop='0'; document.getElementById('global-refresh-btn').click()`);
  await sleep(100);
  assert.equal(await evaluate(`document.documentElement.dataset.tiernestPolling`), 'active');
  assert.match(await evaluate(`document.getElementById('overview-state-headline').textContent`), /自动待机/);
  await evaluate(`document.getElementById('home-network-setup').open=true; document.querySelector('.service-mode-card').scrollIntoView()`);
  assert.equal(await evaluate(`document.documentElement.scrollWidth <= window.innerWidth + 1`), true);
  if (process.env.SCREENSHOT_DIR) {
    await sleep(3500);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    await writeFile(path.join(process.env.SCREENSHOT_DIR, 'service-modes.png'), Buffer.from(shot.data, 'base64'));
  }
  console.log('WebUI browser integration test passed.');
} finally {
  try { socket?.close(); } catch {}
  chrome.kill('SIGTERM');
  await sleep(350);
  await rm(profileDir, { recursive: true, force: true }).catch(() => {});
}
