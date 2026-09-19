import { buildTopologyGraph } from './topology.js';
import { LatestRequest } from './requests.js';
import { formatLogLine, filterLogLines } from './log-format.js';
import { enableEdgeToEdge, exec, moduleInfo, toast as ksuToast } from 'kernelsu';
import { parse as parseTomlDocument, stringify as stringifyTomlDocument } from 'smol-toml';
import './styles.css';

// ==========================================
// Constants & Configuration
// ==========================================
const MODDIR = '/data/adb/modules/tiernest';
const CONTROL = `${MODDIR}/control.sh`;
const STATUS_REFRESH_INTERVAL_MS = 10_000;
const LOG_REFRESH_INTERVAL_MS = 5_000;

// Enable Android Edge-To-Edge
try {
  enableEdgeToEdge(true);
} catch (e) {
  console.warn('EdgeToEdge init:', e);
}

// ==========================================
// Safe Bridge & Version Utilities
// ==========================================

/**
 * Robust short version extractor and formatter
 * Handles objects, JSON strings, semver pre-releases, and long strings.
 * e.g., '1.0.0-et2.6.4' -> 'v1.0.0'
 */
function formatShortVersion(rawVersion) {
  if (!rawVersion) return '版本未知';
  let v = '';

  if (typeof rawVersion === 'object' && rawVersion !== null) {
    v = String(rawVersion.version || rawVersion.versionName || '').trim();
  } else if (typeof rawVersion === 'string') {
    v = rawVersion.trim();
    if (v.startsWith('{') && v.endsWith('}')) {
      try {
        const obj = JSON.parse(v);
        v = String(obj.version || obj.versionName || '').trim();
      } catch {
        // ignore parse error
      }
    }
  }

  // Strip wrapping quotes
  v = v.replace(/^["']|["']$/g, '').trim();
  if (!v) return '版本未知';

  // Parse semver pattern with pre-release
  const semverMatch = v.match(/^v?(\d+\.\d+(?:\.\d+)?)(?:-(beta|alpha|rc)\.?(\d+))?/i);
  if (semverMatch) {
    const core = semverMatch[1];
    const preType = semverMatch[2]?.toLowerCase();
    const preNum = semverMatch[3];
    if (preType === 'beta') return `v${core} β${preNum || '1'}`;
    if (preType === 'alpha') return `v${core} α${preNum || '1'}`;
    if (preType === 'rc') return `v${core} RC${preNum || '1'}`;
    return `v${core}`;
  }

  if (!v.startsWith('v') && !v.startsWith('V')) v = 'v' + v;
  if (v.length > 12) v = v.slice(0, 12);
  return v;
}

/**
 * UTF-8 safe Base64 Encoder (prevents shell injection)
 */
function utf8ToBase64(str) {
  const bytes = new TextEncoder().encode(str);
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * UTF-8 safe Base64 Decoder
 */
function base64ToUtf8(base64) {
  const clean = base64.trim().replace(/\s+/g, '');
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder('utf-8').decode(bytes);
}

/**
 * Safe exec wrapper
 */
async function safeExec(command) {
  try {
    if (typeof exec === 'function') {
      return await exec(command, { cwd: MODDIR });
    }
  } catch (error) {
    return { errno: -1, stdout: '', stderr: String(error) };
  }
  return { errno: -1, stdout: '', stderr: 'KernelSU bridge not available' };
}

/**
 * Run control.sh command
 */
async function runControl(cmd, ...args) {
  const fullCmd = args.length > 0 ? `${CONTROL} ${cmd} ${args.join(' ')}` : `${CONTROL} ${cmd}`;
  return safeExec(fullCmd);
}

// ==========================================
// UI Notifications & Modals
// ==========================================

function showToast(message, type = 'info') {
  try {
    if (typeof ksuToast === 'function') ksuToast(message);
  } catch (e) {
    // fallback
  }

  const container = document.getElementById('toast-container');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast-item ${type}`;
  const icon = type === 'success' ? '✓' : type === 'error' ? '✕' : 'ℹ';
  toast.innerHTML = `<span style="font-weight:700">${icon}</span><span>${escapeHtml(message)}</span>`;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(-10px)';
    toast.style.transition = 'all 0.25s ease';
    setTimeout(() => toast.remove(), 250);
  }, 2800);
}

function escapeHtml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

let modalResolver = null;
const confirmModalEl = document.getElementById('confirm-modal');
const modalTitleEl = document.getElementById('modal-title');
const modalMessageEl = document.getElementById('modal-message');
const modalConfirmBtn = document.getElementById('modal-confirm-btn');
const modalCancelBtn = document.getElementById('modal-cancel-btn');

function showConfirmModal(title, message, confirmText = '确定', isDanger = false) {
  return new Promise((resolve) => {
    modalResolver = resolve;
    modalTitleEl.textContent = title;
    modalMessageEl.textContent = message;
    modalConfirmBtn.textContent = confirmText;
    modalConfirmBtn.className = isDanger ? 'btn btn-danger' : 'btn btn-primary';
    confirmModalEl.classList.add('is-open');
    confirmModalEl.setAttribute('aria-hidden', 'false');
  });
}

function closeConfirmModal(result) {
  confirmModalEl.classList.remove('is-open');
  confirmModalEl.setAttribute('aria-hidden', 'true');
  if (modalResolver) {
    modalResolver(result);
    modalResolver = null;
  }
}

modalConfirmBtn?.addEventListener('click', () => closeConfirmModal(true));
modalCancelBtn?.addEventListener('click', () => closeConfirmModal(false));
confirmModalEl?.addEventListener('click', (e) => {
  if (e.target === confirmModalEl) closeConfirmModal(false);
});

// ==========================================
// Formatting Helpers
// ==========================================

function formatBytes(bytes) {
  const num = Number(bytes);
  if (isNaN(num) || num <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(num) / Math.log(1024));
  return `${(num / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i] || 'B'}`;
}

function formatUptime(seconds) {
  const sec = parseInt(seconds, 10);
  if (isNaN(sec) || sec <= 0) return '—';
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;

  if (d > 0) return `${d}天 ${h}小时 ${m}分`;
  if (h > 0) return `${h}小时 ${m}分 ${s}秒`;
  if (m > 0) return `${m}分 ${s}秒`;
  return `${s}秒`;
}

function formatEpoch(epoch) {
  const ep = parseInt(epoch, 10);
  if (isNaN(ep) || ep <= 0) return '—';
  const date = new Date(ep * 1000);
  const pad = (n) => String(n).padStart(2, '0');
  const Y = date.getFullYear();
  const M = pad(date.getMonth() + 1);
  const D = pad(date.getDate());
  const h = pad(date.getHours());
  const m = pad(date.getMinutes());
  const s = pad(date.getSeconds());
  return `${Y}-${M}-${D} ${h}:${m}:${s}`;
}

function parseKeyValue(text) {
  const map = {};
  if (!text) return map;
  const lines = text.split('\n');
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eqIdx = line.indexOf('=');
    if (eqIdx !== -1) {
      const k = line.slice(0, eqIdx).trim();
      const v = line.slice(eqIdx + 1).trim();
      map[k] = v;
    }
  }
  return map;
}

// ==========================================
// TOML Parser & Serializer for EasyTier
// ==========================================

const DEFAULT_CONFIG_TEMPLATE = {
  instance_name: 'default',
  hostname: '',
  ipv4: '10.144.144.2/24',
  dhcp: false,
  listeners: [
    'tcp://0.0.0.0:11010',
    'udp://0.0.0.0:11010',
    'wg://0.0.0.0:11011',
  ],
  mapped_listeners: [],
  exit_nodes: [],
  rpc_portal: '127.0.0.1:15888',
  network_identity: {
    network_name: 'default',
    network_secret: '',
  },
  peers: [],
  flags: {
    dev_name: 'tiernest0',
    enable_encryption: true,
    enable_ipv6: false,
    mtu: 1380,
    latency_first: false,
    enable_exit_node: false,
    no_tun: false,
    use_smoltcp: false,
    foreign_network_whitelist: '*',
    disable_p2p: false,
    relay_all_peer_rpc: false,
    disable_udp_hole_punching: false,
    disable_tcp_hole_punching: false,
    enable_kcp_proxy: false,
    bind_device: false,
    private_mode: false,
  },
};

function cloneConfig(cfg) {
  return JSON.parse(JSON.stringify(cfg));
}

function parseToml(text) {
  const document = parseTomlDocument(text);
  const result = {
    ...cloneConfig(DEFAULT_CONFIG_TEMPLATE),
    ...document,
    network_identity: {
      ...DEFAULT_CONFIG_TEMPLATE.network_identity,
      ...(document.network_identity || {}),
    },
    flags: {
      ...DEFAULT_CONFIG_TEMPLATE.flags,
      ...(document.flags || {}),
    },
    peers: Array.isArray(document.peer)
      ? document.peer.map((peer) => ({ ...peer }))
      : [],
  };
  delete result.peer;
  if (!Array.isArray(result.listeners)) result.listeners = [];
  if (!Array.isArray(result.mapped_listeners)) result.mapped_listeners = [];
  if (!Array.isArray(result.exit_nodes)) result.exit_nodes = [];
  return result;
}

function generateToml(config) {
  const document = {
    ...config,
    network_identity: { ...(config.network_identity || {}) },
    flags: { ...(config.flags || {}) },
    peer: Array.isArray(config.peers)
      ? config.peers
          .map((peer) => typeof peer === 'string' ? { uri: peer.trim() } : { ...peer, uri: (peer.uri || '').trim() })
          .filter((peer) => peer.uri)
      : [],
  };
  delete document.peers;
  return stringifyTomlDocument(document).trimEnd() + '\n';
}

// ==========================================
// Application State & DOM Bindings
// ==========================================

const state = {
  activeTab: 'tab-overview',
  settingsMode: 'visual', // 'visual' | 'toml'
  activeLogType: 'tiernest', // 'tiernest' | 'network' | 'transport' | 'hotspot'
  hotspotAccessBusy: false,
  hotspotEnabled: false,
  hotspotStatusSeq: 0,
  routeStatusSeq: 0,
  configBusy: false,
  routeStrategyBusy: false,
  routeStrategy: '',
  rawLogContent: '',
  logFilterKeyword: '',
  autoRefreshLog: false,
  logLinesLimit: 200,
  topologyNodes: [],
  topologyFilter: (() => { const saved = typeof localStorage !== 'undefined' ? localStorage.getItem('tiernest_topology_filter') : ''; return saved === 'virtual_only' ? 'virtual_only' : 'all'; })(),
  selectedTopologyNodeId: null,
  rawTopologyRoutes: [],
  lastTopologyAt: 0,
  config: cloneConfig(DEFAULT_CONFIG_TEMPLATE),
  settingsLoaded: false,
  lastStatus: {},
  lastMetrics: {},
  busy: false,
  statusTimer: null,
  logTimer: null,
};


const readRequests = {
  overview: new LatestRequest(), topology: new LatestRequest(), logs: new LatestRequest(),
  settings: new LatestRequest(),
};

function invalidateReadRequests() {
  Object.values(readRequests).forEach(request => request.invalidate());
  state.hotspotStatusSeq++;
  state.routeStatusSeq++;
  state.busy = false;
  document.body.classList.remove('is-busy');
  dom.topologyRefreshBtn?.classList.remove('is-spinning');
}

function pageIsVisible() {
  return document.visibilityState !== 'hidden';
}

function stopStatusPolling() {
  if (state.statusTimer) {
    clearInterval(state.statusTimer);
    state.statusTimer = null;
  }
}

function stopLogPolling() {
  if (state.logTimer) {
    clearInterval(state.logTimer);
    state.logTimer = null;
  }
}

async function refreshVisibleTab() {
  if (!pageIsVisible()) return;
  if (state.activeTab === 'tab-overview') {
    await refreshOverviewStatus({ quiet: true });
    if (Date.now() - state.lastTopologyAt >= 60_000) loadTopology({ quiet: true });
  } else if (state.activeTab === 'tab-settings') {
    if (!state.settingsLoaded) await loadSettingsConfig();
    await Promise.all([refreshRouteStrategyStatus({ quiet: true }), refreshHotspotAccessStatus({ quiet: true })]);
  }
}

function startStatusPolling() {
  stopStatusPolling();
  if (!pageIsVisible() || state.lastStatus?.manual_stop === '1') return;
  state.statusTimer = setInterval(() => {
    refreshVisibleTab();
  }, STATUS_REFRESH_INTERVAL_MS);
}

function startLogPolling() {
  stopLogPolling();
  if (!pageIsVisible() || state.lastStatus?.manual_stop === '1' || !state.autoRefreshLog) return;
  state.logTimer = setInterval(() => {
    if (state.activeTab === 'tab-logs' && state.autoRefreshLog && pageIsVisible()) {
      loadCurrentLogs();
    }
  }, LOG_REFRESH_INTERVAL_MS);
}

function syncPollingVisibility({ refreshNow = false } = {}) {
  const visible = pageIsVisible();
  document.documentElement.dataset.tiernestPolling = visible && state.lastStatus?.manual_stop !== '1' ? 'active' : 'paused';
  if (!visible) {
    stopStatusPolling();
    stopLogPolling();
    invalidateReadRequests();
    return;
  }
  startStatusPolling();
  startLogPolling();
  if (refreshNow) {
    refreshVisibleTab();
    if (state.activeTab === 'tab-logs' && state.autoRefreshLog) loadCurrentLogs();
  }
}

// Cache DOM Elements
const dom = {
  // Navigation
  navItems: document.querySelectorAll('.nav-item'),
  tabPanels: document.querySelectorAll('.tab-panel'),

  // Header
  versionBadge: document.getElementById('module-version-badge'),
  globalStatePill: document.getElementById('global-state-pill'),
  globalRefreshBtn: document.getElementById('global-refresh-btn'),

  // Overview Tab
  heroIconBox: document.getElementById('hero-icon-box'),
  overviewStateHeadline: document.getElementById('overview-state-headline'),
  overviewUpdatedTime: document.getElementById('overview-updated-time'),
  overviewFrameworkTag: document.getElementById('overview-framework-tag'),
  overviewModeBadge: document.getElementById('overview-mode-badge'),
  statPid: document.getElementById('stat-pid'),
  statTun: document.getElementById('stat-tun'),
  statIp: document.getElementById('stat-ip'),
  statNetwork: document.getElementById('stat-network'),
  statRoute: document.getElementById('stat-route'),
  statVpn: document.getElementById('stat-vpn'),

  // Metrics
  metricCpu: document.getElementById('metric-cpu'),
  metricCpuBar: document.getElementById('metric-cpu-bar'),
  metricRss: document.getElementById('metric-rss'),
  metricRssNote: document.getElementById('metric-rss-note'),
  metricUptime: document.getElementById('metric-uptime'),
  metricUptimeNote: document.getElementById('metric-uptime-note'),
  metricTunRx: document.getElementById('metric-tun-rx'),
  metricTunTx: document.getElementById('metric-tun-tx'),
  metricTunNote: document.getElementById('metric-tun-note'),
  metricLogSize: document.getElementById('metric-log-size'),
  metricLogDetail: document.getElementById('metric-log-detail'),
  metricVpnRestarts: document.getElementById('metric-vpn-restarts'),
  metricHealthDetail: document.getElementById('metric-health-detail'),
  metricsStatusBadge: document.getElementById('metrics-status-badge'),

  // Network Topology
  topologyRefreshBtn: document.getElementById('topology-refresh-btn'),
  topologyFilterBtns: document.querySelectorAll('[data-topology-filter]'),
  topologySummaryTitle: document.getElementById('topology-summary-title'),
  topologySummaryText: document.getElementById('topology-summary-text'),
  topologyNodeCount: document.getElementById('topology-node-count'),
  topologySvg: document.getElementById('topology-svg'),
  topologyPlaceholder: document.getElementById('topology-placeholder'),
  topologyDetail: document.getElementById('topology-detail'),
  topologyVirtualCountBadge: document.getElementById('topology-virtual-count-badge'),
  topologyVirtualNodesList: document.getElementById('topology-virtual-nodes-list'),

  // Service Controls
  controlBtns: document.querySelectorAll('[data-control-cmd]'),
  exportResultBox: document.getElementById('export-result-box'),
  exportPathText: document.getElementById('export-path-text'),

  // Settings Tab Banners
  commandArgsBanner: document.getElementById('command-args-warning-banner'),
  configErrorBanner: document.getElementById('config-error-alert-banner'),
  configErrorTitle: document.getElementById('config-error-title'),
  configErrorDetail: document.getElementById('config-error-detail'),
  closeConfigErrorBtn: document.getElementById('close-config-error-btn'),

  // Settings Mode Selector
  viewModeVisualBtn: document.getElementById('view-mode-visual-btn'),
  viewModeTomlBtn: document.getElementById('view-mode-toml-btn'),
  settingsVisualView: document.getElementById('settings-visual-view'),
  settingsTomlView: document.getElementById('settings-toml-view'),

  // Form Fields
  cfgInstanceName: document.getElementById('cfg-instance-name'),
  cfgHostname: document.getElementById('cfg-hostname'),
  cfgIpv4: document.getElementById('cfg-ipv4'),
  cfgDhcp: document.getElementById('cfg-dhcp'),
  cfgNetworkName: document.getElementById('cfg-network-name'),
  cfgNetworkSecret: document.getElementById('cfg-network-secret'),
  toggleSecretBtn: document.getElementById('toggle-secret-btn'),

  listenersContainer: document.getElementById('listeners-list-container'),
  newListenerInput: document.getElementById('new-listener-input'),
  addListenerBtn: document.getElementById('add-listener-btn'),
  presetChips: document.querySelectorAll('[data-preset-listener]'),

  peersContainer: document.getElementById('peers-list-container'),
  newPeerInput: document.getElementById('new-peer-input'),
  addPeerBtn: document.getElementById('add-peer-btn'),

  cfgMtu: document.getElementById('cfg-mtu'),
  cfgDevName: document.getElementById('cfg-dev-name'),
  cfgRpcPortal: document.getElementById('cfg-rpc-portal'),

  flagEncryption: document.getElementById('cfg-flag-encryption'),
  flagIpv6: document.getElementById('cfg-flag-ipv6'),
  flagLatency: document.getElementById('cfg-flag-latency'),
  flagP2p: document.getElementById('cfg-flag-p2p'),
  flagBind: document.getElementById('cfg-flag-bind'),
  flagPrivate: document.getElementById('cfg-flag-private'),
  flagExit: document.getElementById('cfg-flag-exit'),
  flagNoUdpPunch: document.getElementById('cfg-flag-no-udp-punch'),
  flagNoTcpPunch: document.getElementById('cfg-flag-no-tcp-punch'),
  flagKcpProxy: document.getElementById('cfg-flag-kcp-proxy'),
  flagSmoltcp: document.getElementById('cfg-flag-smoltcp'),
  comboHintCard: document.getElementById('kcp-smoltcp-combo-hint'),
  comboHintTitle: document.getElementById('kcp-smoltcp-combo-title'),
  comboHintDesc: document.getElementById('kcp-smoltcp-combo-desc'),

  // Route strategy switch
  routeStrategyBadge: document.getElementById('route-strategy-badge'),
  routeStrategyBadgeText: document.getElementById('route-strategy-badge-text'),
  routeStrategyOfficialBtn: document.getElementById('route-strategy-official-btn'),
  routeStrategyLegacyBtn: document.getElementById('route-strategy-legacy-btn'),
  routeStrategySummary: document.getElementById('route-strategy-summary'),

  // Outbound-only hotspot client access
  hotspotAccessToggle: document.getElementById('hotspot-access-toggle'),
  hotspotAccessBadge: document.getElementById('hotspot-access-badge'),
  hotspotAccessBadgeText: document.getElementById('hotspot-access-badge-text'),
  hotspotAccessStatus: document.getElementById('hotspot-access-status'),
  hotspotAccessInterface: document.getElementById('hotspot-access-interface'),
  hotspotAccessCidr: document.getElementById('hotspot-access-cidr'),
  hotspotAccessTun: document.getElementById('hotspot-access-tun'),
  hotspotAccessTargets: document.getElementById('hotspot-access-targets'),
  hotspotAccessClients: document.getElementById('hotspot-access-clients'),
  hotspotAccessError: document.getElementById('hotspot-access-error'),
  hotspotAccessRefreshBtn: document.getElementById('hotspot-access-refresh-btn'),
  hotspotAccessReapplyBtn: document.getElementById('hotspot-access-reapply-btn'),

  // TOML Editor
  tomlRawEditor: document.getElementById('toml-raw-editor'),
  editorFormatBtn: document.getElementById('editor-format-btn'),
  editorResetTemplateBtn: document.getElementById('editor-reset-template-btn'),
  editorStatusText: document.getElementById('editor-status-text'),
  editorCharCount: document.getElementById('editor-char-count'),

  // Settings Actions
  actionValidate: document.getElementById('cfg-action-validate'),
  actionBackup: document.getElementById('cfg-action-backup'),
  actionReload: document.getElementById('cfg-action-reload'),
  actionSave: document.getElementById('cfg-action-save'),
  actionSaveRestart: document.getElementById('cfg-action-save-restart'),

  // Logs Tab
  logSegmentedBtns: document.querySelectorAll('[data-log-target]'),
  logAutoRefreshToggle: document.getElementById('log-auto-refresh-toggle'),
  logRefreshBtn: document.getElementById('log-refresh-btn'),
  logSearchInput: document.getElementById('log-search-input'),
  logClearSearchBtn: document.getElementById('log-clear-search-btn'),
  logLinesSelect: document.getElementById('log-lines-select'),
  logCopyBtn: document.getElementById('log-copy-btn'),
  logScrollBottomBtn: document.getElementById('log-scroll-bottom-btn'),
  logActivePath: document.getElementById('log-active-path'),
  logLinesCounter: document.getElementById('log-lines-counter'),
  logOutputContainer: document.getElementById('log-output-container'),
};

// Error Banner Dismiss
dom.closeConfigErrorBtn?.addEventListener('click', () => {
  if (dom.configErrorBanner) dom.configErrorBanner.style.display = 'none';
});

function showConfigError(title, detail) {
  if (dom.configErrorBanner && dom.configErrorTitle && dom.configErrorDetail) {
    dom.configErrorTitle.textContent = title;
    dom.configErrorDetail.textContent = detail;
    dom.configErrorBanner.style.display = 'flex';
  }
  showToast(`${title}: ${detail}`, 'error');
}

function hideConfigError() {
  if (dom.configErrorBanner) dom.configErrorBanner.style.display = 'none';
}

// ==========================================
// Tab Navigation
// ==========================================

function switchTab(targetTabId) {
  if (state.activeTab !== targetTabId) readRequests.logs.invalidate();
  state.activeTab = targetTabId;

  dom.navItems.forEach((item) => {
    const isCurrent = item.dataset.target === targetTabId;
    item.classList.toggle('is-active', isCurrent);
    item.setAttribute('aria-selected', isCurrent ? 'true' : 'false');
  });

  dom.tabPanels.forEach((panel) => {
    panel.classList.toggle('is-active', panel.id === targetTabId);
  });

  if (targetTabId === 'tab-overview') {
    refreshOverviewStatus({ quiet: true });
  } else if (targetTabId === 'tab-settings') {
    if (!state.settingsLoaded) loadSettingsConfig();
    refreshRouteStrategyStatus({ quiet: true });
    refreshHotspotAccessStatus({ quiet: true });
  } else if (targetTabId === 'tab-logs') {
    loadCurrentLogs();
  }
}

dom.navItems.forEach((btn) => {
  btn.addEventListener('click', () => switchTab(btn.dataset.target));
});

// ==========================================
// Settings View Switching & Form Sync
// ==========================================

function presentSettingsMode(mode) {
  state.settingsMode = mode;
  dom.viewModeVisualBtn.classList.toggle('is-active', mode === 'visual');
  dom.viewModeTomlBtn.classList.toggle('is-active', mode === 'toml');
  dom.settingsVisualView.classList.toggle('is-active', mode === 'visual');
  dom.settingsTomlView.classList.toggle('is-active', mode === 'toml');
}

function switchSettingsMode(mode) {
  if (mode === state.settingsMode) return;
  try {
    if (mode === 'visual') {
      const parsed = parseToml(dom.tomlRawEditor.value);
      state.config = parsed;
      populateVisualForm(parsed);
      dom.editorStatusText.textContent = '已同步至表单';
    } else {
      collectVisualForm();
      dom.tomlRawEditor.value = generateToml(state.config);
      updateEditorStats();
    }
    presentSettingsMode(mode);
  } catch (error) {
    showConfigError('无法切换配置视图', String(error));
  }
}

dom.viewModeVisualBtn?.addEventListener('click', () => switchSettingsMode('visual'));
dom.viewModeTomlBtn?.addEventListener('click', () => switchSettingsMode('toml'));

function updateEditorStats() {
  const val = dom.tomlRawEditor?.value || '';
  if (dom.editorCharCount) dom.editorCharCount.textContent = `${val.length} 字符 · ${val.split('\n').length} 行`;
}

dom.tomlRawEditor?.addEventListener('input', updateEditorStats);

dom.editorFormatBtn?.addEventListener('click', () => {
  try {
    const document = parseTomlDocument(dom.tomlRawEditor.value);
    const parsed = parseToml(dom.tomlRawEditor.value);
    dom.tomlRawEditor.value = stringifyTomlDocument(document);
    state.config = parsed;
    populateVisualForm(parsed);
    updateEditorStats();
    hideConfigError();
    showToast('当前 TOML 已格式化', 'success');
  } catch (error) {
    showConfigError('格式化失败，已保留原文', String(error));
  }
});

dom.editorResetTemplateBtn?.addEventListener('click', async () => {
  const ok = await showConfirmModal('重置为默认模板', '将恢复为 EasyTier 初始默认配置，未保存的内容将丢失。', '恢复默认', true);
  if (!ok) return;
  state.config = cloneConfig(DEFAULT_CONFIG_TEMPLATE);
  dom.tomlRawEditor.value = generateToml(state.config);
  populateVisualForm(state.config);
  updateEditorStats();
  hideConfigError();
  showToast('已重置为默认配置模板', 'info');
});

// ==========================================
// Visual Form Population & Collection
// ==========================================

function populateVisualForm(cfg) {
  if (!cfg) return;
  dom.cfgInstanceName.value = cfg.instance_name || 'default';
  dom.cfgHostname.value = cfg.hostname || '';
  dom.cfgIpv4.value = cfg.ipv4 || '';
  dom.cfgDhcp.checked = Boolean(cfg.dhcp);
  dom.cfgNetworkName.value = cfg.network_identity?.network_name || 'default';
  dom.cfgNetworkSecret.value = cfg.network_identity?.network_secret || '';

  dom.cfgMtu.value = cfg.flags?.mtu || 1380;
  dom.cfgDevName.value = typeof cfg.flags?.dev_name === 'string' ? cfg.flags.dev_name : (cfg.flags?.dev_name ?? 'tiernest0');
  dom.cfgRpcPortal.value = cfg.rpc_portal || '127.0.0.1:15888';

  dom.flagEncryption.checked = cfg.flags?.enable_encryption !== false;
  dom.flagIpv6.checked = Boolean(cfg.flags?.enable_ipv6);
  dom.flagLatency.checked = Boolean(cfg.flags?.latency_first);
  dom.flagP2p.checked = Boolean(cfg.flags?.disable_p2p);
  dom.flagBind.checked = Boolean(cfg.flags?.bind_device);
  dom.flagPrivate.checked = Boolean(cfg.flags?.private_mode);
  dom.flagExit.checked = Boolean(cfg.flags?.enable_exit_node);
  dom.flagNoUdpPunch.checked = Boolean(cfg.flags?.disable_udp_hole_punching);
  dom.flagNoTcpPunch.checked = Boolean(cfg.flags?.disable_tcp_hole_punching);
  if (dom.flagKcpProxy) dom.flagKcpProxy.checked = Boolean(cfg.flags?.enable_kcp_proxy);
  if (dom.flagSmoltcp) dom.flagSmoltcp.checked = Boolean(cfg.flags?.use_smoltcp);

  updateKcpSmoltcpComboHint();
  renderListenersList();
  renderPeersList();
}

function collectVisualForm() {
  state.config.instance_name = dom.cfgInstanceName.value.trim() || 'default';
  state.config.hostname = dom.cfgHostname.value.trim();
  state.config.ipv4 = dom.cfgIpv4.value.trim();
  state.config.dhcp = dom.cfgDhcp.checked;

  state.config.network_identity = state.config.network_identity || {};
  state.config.network_identity.network_name = dom.cfgNetworkName.value.trim() || 'default';
  state.config.network_identity.network_secret = dom.cfgNetworkSecret.value;

  state.config.rpc_portal = dom.cfgRpcPortal.value.trim() || '127.0.0.1:15888';

  state.config.flags = state.config.flags || {};
  state.config.flags.dev_name = dom.cfgDevName.value.trim();
  state.config.flags.mtu = parseInt(dom.cfgMtu.value, 10) || 1380;
  state.config.flags.enable_encryption = dom.flagEncryption.checked;
  state.config.flags.enable_ipv6 = dom.flagIpv6.checked;
  state.config.flags.latency_first = dom.flagLatency.checked;
  state.config.flags.disable_p2p = dom.flagP2p.checked;
  state.config.flags.bind_device = dom.flagBind.checked;
  state.config.flags.private_mode = dom.flagPrivate.checked;
  state.config.flags.enable_exit_node = dom.flagExit.checked;
  state.config.flags.disable_udp_hole_punching = dom.flagNoUdpPunch.checked;
  state.config.flags.disable_tcp_hole_punching = dom.flagNoTcpPunch.checked;
  if (dom.flagKcpProxy) state.config.flags.enable_kcp_proxy = dom.flagKcpProxy.checked;
  if (dom.flagSmoltcp) state.config.flags.use_smoltcp = dom.flagSmoltcp.checked;

  return state.config;
}

function updateKcpSmoltcpComboHint() {
  if (!dom.comboHintCard || !dom.comboHintTitle || !dom.comboHintDesc) return;
  const kcp = Boolean(dom.flagKcpProxy?.checked);
  const smoltcp = Boolean(dom.flagSmoltcp?.checked);

  dom.comboHintCard.classList.remove('is-safe', 'is-warning', 'is-compat');

  if (!kcp) {
    dom.comboHintCard.classList.add('is-safe');
    dom.comboHintTitle.textContent = '✅ 推荐配置：TCP 直连稳定';
    dom.comboHintDesc.textContent = 'KCP 代理已关闭，所有 TCP 流量使用标准直连模式，无额外开销，各机型兼容性最佳。';
  } else if (!smoltcp) {
    dom.comboHintCard.classList.add('is-warning');
    dom.comboHintTitle.textContent = '⚠️ 高风险警告：可能发生 TCP 握手超时';
    dom.comboHintDesc.textContent = '已启用 KCP 但未启用用户态 TCP 栈。在部分小米/HyperOS/定制内核设备上极易出现“Ping 正常但 HTTP/SSH 等 TCP 无法建连”。如遇异常请关闭 KCP 或开启下方“用户态 TCP 栈”。';
  } else {
    dom.comboHintCard.classList.add('is-compat');
    dom.comboHintTitle.textContent = '💡 兼容模式：用户态 TCP 代理';
    dom.comboHintDesc.textContent = 'KCP 配合 smoltcp 用户态协议栈运行，可有效规避内核 TCP 握手异常，但会增加少量 CPU 与内存开销。';
  }
}

dom.flagKcpProxy?.addEventListener('change', updateKcpSmoltcpComboHint);
dom.flagSmoltcp?.addEventListener('change', updateKcpSmoltcpComboHint);

// Password show/hide toggle
dom.toggleSecretBtn?.addEventListener('click', () => {
  const isPwd = dom.cfgNetworkSecret.type === 'password';
  dom.cfgNetworkSecret.type = isPwd ? 'text' : 'password';
  const icon = document.getElementById('eye-icon');
  if (icon) {
    icon.innerHTML = isPwd
      ? '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>'
      : '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
  }
});

// Listeners dynamic list
function renderListenersList() {
  const list = state.config.listeners || [];
  if (list.length === 0) {
    dom.listenersContainer.innerHTML = '<div class="empty-item-placeholder">暂未配置监听端口 (将无法被其他节点主动连接)</div>';
    return;
  }

  dom.listenersContainer.innerHTML = list
    .map(
      (item, idx) => `
    <div class="item-chip-row">
      <span class="item-chip-text font-mono" title="${escapeHtml(item)}">${escapeHtml(item)}</span>
      <button class="item-delete-btn" data-del-listener="${idx}" type="button" aria-label="删除">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
      </button>
    </div>
  `,
    )
    .join('');

  dom.listenersContainer.querySelectorAll('[data-del-listener]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const idx = parseInt(btn.dataset.delListener, 10);
      state.config.listeners.splice(idx, 1);
      renderListenersList();
    });
  });
}

function addListener(val) {
  const clean = (val || '').trim();
  if (!clean) return;
  state.config.listeners = state.config.listeners || [];
  if (state.config.listeners.includes(clean)) {
    showToast('该监听地址已存在', 'info');
    return;
  }
  state.config.listeners.push(clean);
  dom.newListenerInput.value = '';
  renderListenersList();
}

dom.addListenerBtn?.addEventListener('click', () => addListener(dom.newListenerInput.value));
dom.newListenerInput?.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') addListener(dom.newListenerInput.value);
});

dom.presetChips.forEach((chip) => {
  chip.addEventListener('click', () => addListener(chip.dataset.presetListener));
});

// Peers dynamic list
function renderPeersList() {
  const peers = state.config.peers || [];
  if (peers.length === 0) {
    dom.peersContainer.innerHTML = '<div class="empty-item-placeholder">暂未添加对等中继节点 (可在下方输入公网服务器 URI 添加)</div>';
    return;
  }

  dom.peersContainer.innerHTML = peers
    .map((p, idx) => {
      const uri = typeof p === 'string' ? p : p.uri || '';
      return `
      <div class="item-chip-row">
        <span class="item-chip-text font-mono" title="${escapeHtml(uri)}">${escapeHtml(uri)}</span>
        <button class="item-delete-btn" data-del-peer="${idx}" type="button" aria-label="删除">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
        </button>
      </div>
    `;
    })
    .join('');

  dom.peersContainer.querySelectorAll('[data-del-peer]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const idx = parseInt(btn.dataset.delPeer, 10);
      state.config.peers.splice(idx, 1);
      renderPeersList();
    });
  });
}

function addPeer(val) {
  const clean = (val || '').trim();
  if (!clean) return;
  state.config.peers = state.config.peers || [];
  const exists = state.config.peers.some((p) => (typeof p === 'string' ? p === clean : p.uri === clean));
  if (exists) {
    showToast('该对等节点已在列表中', 'info');
    return;
  }
  state.config.peers.push({ uri: clean });
  dom.newPeerInput.value = '';
  renderPeersList();
}

dom.addPeerBtn?.addEventListener('click', () => addPeer(dom.newPeerInput.value));
dom.newPeerInput?.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') addPeer(dom.newPeerInput.value);
});

// ==========================================
// Persistent route strategy switch
// ==========================================

function renderRouteStrategyStatus(status) {
  if (!dom.routeStrategyOfficialBtn || !dom.routeStrategyLegacyBtn) return;
  const strategy = status.strategy === 'legacy' ? 'legacy' : 'official';
  state.routeStrategy = strategy;
  const legacy = strategy === 'legacy';
  dom.routeStrategyOfficialBtn.classList.toggle('is-active', !legacy);
  dom.routeStrategyLegacyBtn.classList.toggle('is-active', legacy);
  dom.routeStrategyOfficialBtn.disabled = state.routeStrategyBusy || !legacy;
  dom.routeStrategyLegacyBtn.disabled = state.routeStrategyBusy || legacy;
  if (dom.routeStrategyBadge) dom.routeStrategyBadge.dataset.state = 'running';
  if (dom.routeStrategyBadgeText) dom.routeStrategyBadgeText.textContent = legacy ? '经典方案' : '官方方案';
  if (dom.routeStrategySummary) {
    const mode = status.route_mode || (legacy ? 'dedicated' : 'auto');
    const mirrored = status.android_table_mirroring === '1';
    dom.routeStrategySummary.textContent = legacy
      ? `当前：TierNest 经典方案 · ${mode} · Android 网络表镜像${mirrored ? '已启用' : '未启用'}`
      : `当前：官方兼容方案 · ${mode} · Android 网络表镜像关闭`;
  }
}

async function refreshRouteStrategyStatus({ quiet = false } = {}) {
  if (!dom.routeStrategyOfficialBtn || state.routeStrategyBusy) return;
  const sequence = ++state.routeStatusSeq;
  try {
    const result = await runControl('route-strategy-status');
    if (state.routeStrategyBusy || sequence !== state.routeStatusSeq || !pageIsVisible()) return;
    if (result.errno !== 0) throw new Error(result.stderr || '状态读取失败');
    renderRouteStrategyStatus(parseKeyValue(result.stdout));
  } catch (error) {
    if (sequence !== state.routeStatusSeq || state.routeStrategyBusy || !pageIsVisible()) return;
    if (dom.routeStrategyBadge) dom.routeStrategyBadge.dataset.state = 'error';
    if (dom.routeStrategyBadgeText) dom.routeStrategyBadgeText.textContent = '读取失败';
    if (!quiet) showToast(`路由方案读取失败：${String(error)}`, 'error');
  }
}

async function switchRouteStrategy(strategy) {
  if (state.routeStrategyBusy || strategy === state.routeStrategy) return;
  state.routeStrategyBusy = true;
  state.routeStatusSeq++;
  dom.routeStrategyOfficialBtn.disabled = true;
  dom.routeStrategyLegacyBtn.disabled = true;
  if (dom.routeStrategyBadge) dom.routeStrategyBadge.dataset.state = 'loading';
  if (dom.routeStrategyBadgeText) dom.routeStrategyBadgeText.textContent = '切换并重启中';
  showToast(`正在切换到${strategy === 'legacy' ? '经典' : '官方'}方案并重启 EasyTier…`, 'info');
  try {
    const result = await runControl(`route-strategy-${strategy}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || '切换失败');
    renderRouteStrategyStatus(parseKeyValue(result.stdout));
    showToast('路由方案已切换，EasyTier 已重启', 'success');
    setTimeout(() => refreshOverviewStatus({ quiet: true, force: true }), 600);
  } catch (error) {
    showToast(`路由方案切换失败：${String(error)}`, 'error');
  } finally {
    state.routeStrategyBusy = false;
    await refreshRouteStrategyStatus({ quiet: true });
    if (!state.routeStrategyBusy) {
      dom.routeStrategyOfficialBtn.disabled = state.routeStrategy === 'official';
      dom.routeStrategyLegacyBtn.disabled = state.routeStrategy === 'legacy';
    }
  }
}

dom.routeStrategyOfficialBtn?.addEventListener('click', () => switchRouteStrategy('official'));
dom.routeStrategyLegacyBtn?.addEventListener('click', () => switchRouteStrategy('legacy'));

// ==========================================
// Outbound-only hotspot client access
// ==========================================

const HOTSPOT_ACCESS_STATUS_LABELS = {
  active: '运行中',
  disabled: '已关闭',
  waiting: '等待条件',
  'waiting-core': '等待核心',
  'waiting-tun': '等待 TUN',
  'waiting-hotspot': '等待手机热点',
  'waiting-routes': '等待组网路由',
  'ip-forward-disabled': '系统转发未就绪',
  'subnet-advertised': '热点网段已发布',
  'too-many-targets': '目标过多',
  'apply-failed': '规则应用失败',
};

function renderHotspotAccessStatus(status) {
  if (!dom.hotspotAccessToggle) return;
  const enabled = status.enabled === '1';
  const active = status.active === '1';
  const code = status.status || (enabled ? 'waiting' : 'disabled');
  const label = HOTSPOT_ACCESS_STATUS_LABELS[code] || code;
  const isError = enabled && !active && !code.startsWith('waiting');

  state.hotspotEnabled = enabled;
  dom.hotspotAccessToggle.checked = enabled;
  dom.hotspotAccessToggle.disabled = state.hotspotAccessBusy;
  if (dom.hotspotAccessBadge) dom.hotspotAccessBadge.dataset.state = active ? 'running' : (isError ? 'error' : 'stopped');
  if (dom.hotspotAccessBadgeText) dom.hotspotAccessBadgeText.textContent = active ? '单向访问运行中' : label;
  if (dom.hotspotAccessStatus) dom.hotspotAccessStatus.textContent = label;
  if (dom.hotspotAccessInterface) dom.hotspotAccessInterface.textContent = status.interface || '—';
  if (dom.hotspotAccessCidr) dom.hotspotAccessCidr.textContent = status.cidr || '—';
  if (dom.hotspotAccessTun) dom.hotspotAccessTun.textContent = status.tun || '—';
  if (dom.hotspotAccessTargets) dom.hotspotAccessTargets.textContent = `${Number(status.target_count) || 0} 个`;
  if (dom.hotspotAccessClients) dom.hotspotAccessClients.textContent = `${Number(status.client_count) || 0} 台`;
  if (dom.hotspotAccessError) {
    const detail = status.error_detail || '';
    dom.hotspotAccessError.textContent = detail;
    dom.hotspotAccessError.style.display = enabled && detail ? 'block' : 'none';
  }
}

async function refreshHotspotAccessStatus({ quiet = false } = {}) {
  if (!dom.hotspotAccessToggle || state.hotspotAccessBusy) return false;
  const sequence = ++state.hotspotStatusSeq;
  try {
    const result = await runControl('hotspot-access-status');
    if (state.hotspotAccessBusy || sequence !== state.hotspotStatusSeq || !pageIsVisible()) return false;
    if (result.errno !== 0) throw new Error(result.stderr || '状态读取失败');
    renderHotspotAccessStatus(parseKeyValue(result.stdout));
    return true;
  } catch (error) {
    if (sequence !== state.hotspotStatusSeq || state.hotspotAccessBusy) return false;
    dom.hotspotAccessToggle.checked = state.hotspotEnabled;
    if (dom.hotspotAccessBadge) dom.hotspotAccessBadge.dataset.state = 'error';
    if (dom.hotspotAccessBadgeText) dom.hotspotAccessBadgeText.textContent = '状态未确认';
    if (!quiet) showToast(`热点单向访问状态读取失败：${String(error)}`, 'error');
    return false;
  }
}

async function runHotspotAccessCommand(command, successText) {
  if (state.hotspotAccessBusy) return;
  state.hotspotAccessBusy = true;
  state.hotspotStatusSeq++;
  let failed = false;
  if (dom.hotspotAccessToggle) dom.hotspotAccessToggle.disabled = true;
  if (dom.hotspotAccessRefreshBtn) dom.hotspotAccessRefreshBtn.disabled = true;
  if (dom.hotspotAccessReapplyBtn) dom.hotspotAccessReapplyBtn.disabled = true;
  try {
    const result = await runControl(command);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || '后端执行失败');
    const status = parseKeyValue(result.stdout);
    renderHotspotAccessStatus(status);
    if (status.active === '1') showToast(successText, 'success');
    else if (status.enabled === '0') showToast('热点设备单向访问已关闭', 'info');
    else showToast(HOTSPOT_ACCESS_STATUS_LABELS[status.status] || '已启用，正在等待运行条件', 'info');
  } catch (error) {
    failed = true;
    if (dom.hotspotAccessToggle) dom.hotspotAccessToggle.checked = state.hotspotEnabled;
    showToast(`热点单向访问操作失败：${String(error)}`, 'error');
  } finally {
    state.hotspotAccessBusy = false;
    // Refresh only AFTER releasing busy; otherwise the status function skips it.
    if (failed) await refreshHotspotAccessStatus({ quiet: true });
    if (!state.hotspotAccessBusy) {
      if (dom.hotspotAccessToggle) dom.hotspotAccessToggle.disabled = false;
      if (dom.hotspotAccessRefreshBtn) dom.hotspotAccessRefreshBtn.disabled = false;
      if (dom.hotspotAccessReapplyBtn) dom.hotspotAccessReapplyBtn.disabled = false;
    }
  }
}

dom.hotspotAccessToggle?.addEventListener('change', () => {
  const enable = dom.hotspotAccessToggle.checked;
  runHotspotAccessCommand(enable ? 'hotspot-access-enable' : 'hotspot-access-disable', '热点设备单向访问已启用');
});
dom.hotspotAccessRefreshBtn?.addEventListener('click', () => refreshHotspotAccessStatus());
dom.hotspotAccessReapplyBtn?.addEventListener('click', () => runHotspotAccessCommand('hotspot-access-reapply', '单向访问规则已安全重应用'));

// ==========================================
// Settings Backend Actions (Strict API - No Direct File Fallbacks)
// ==========================================

function getCurrentTomlPayload() {
  if (state.settingsMode === 'visual') {
    collectVisualForm();
    return generateToml(state.config);
  }
  return dom.tomlRawEditor.value;
}

async function runConfigAction(action) {
  if (state.configBusy) return false;
  if (!state.settingsLoaded && action !== loadSettingsConfig) {
    showConfigError('配置尚未加载', '请先加载磁盘配置后再操作，避免覆盖原配置');
    return false;
  }
  state.configBusy = true;
  const buttons = [dom.actionValidate, dom.actionSave, dom.actionSaveRestart, dom.actionReload, dom.actionBackup];
  buttons.forEach(button => { if (button) button.disabled = true; });
  try { return await action(); }
  catch (error) { showConfigError('配置操作失败', String(error)); return false; }
  finally { state.configBusy = false; buttons.forEach(button => { if (button) button.disabled = false; }); }
}

function loadSettingsConfig() {
  return readRequests.settings.run('settings', async isCurrent => {
    try {
      const result = await runControl('config-read-b64');
      if (!isCurrent() || !pageIsVisible()) return false;
      if (result.errno !== 0 || !result.stdout.trim()) throw new Error(result.stderr || '配置内容为空');
      const tomlContent = base64ToUtf8(result.stdout.trim());
      dom.tomlRawEditor.value = tomlContent;
      updateEditorStats();
      state.settingsLoaded = true; // Disk read succeeded, even if syntax needs repair.
      let config;
      try { config = parseToml(tomlContent); }
      catch (error) { presentSettingsMode('toml'); throw error; }
      state.config = config;
      populateVisualForm(config);
      updateEditorStats();
      state.settingsLoaded = true;
      hideConfigError();
      return true;
    } catch (error) {
      if (isCurrent()) showConfigError('加载配置失败', String(error));
      return false;
    }
  });
}

async function validateConfigAction() {
  const toml = getCurrentTomlPayload();
  const b64 = utf8ToBase64(toml);

  const result = await runControl('config-validate-b64', b64);
  if (result.errno === 0) {
    hideConfigError();
    showToast('✓ TOML 配置验证通过，格式正确！', 'success');
  } else {
    const errorMsg = result.stderr || result.stdout || '配置语法校验失败';
    showConfigError('配置校验失败', errorMsg);
  }
}

async function saveConfigAction(andRestart = false) {
  const toml = getCurrentTomlPayload();
  const b64 = utf8ToBase64(toml);

  const result = await runControl('config-save-b64', b64);
  if (result.errno !== 0) {
    const errorMsg = result.stderr || result.stdout || '后端拒绝保存配置';
    showConfigError('配置保存失败', errorMsg);
    return false;
  }

  hideConfigError();
  const parsedRes = parseKeyValue(result.stdout);
  const backupPath = parsedRes.backup || '';
  showToast(backupPath ? `配置已保存，备份：${backupPath}` : '配置已安全保存', 'success');

  if (andRestart) {
    showToast('正在重启 EasyTier 服务…', 'info');
    const rRes = await runControl('restart');
    if (rRes.errno === 0) {
      showToast('EasyTier 已重启', 'success');
      setTimeout(() => { if (state.activeTab === 'tab-settings') switchTab('tab-overview'); }, 800);
    } else {
      showToast(`重启失败: ${rRes.stderr || '请查看运行日志'}`, 'error');
    }
  }

  return true;
}

async function backupConfigAction() {
  const result = await runControl('config-backup');
  if (result.errno === 0) {
    const path = result.stdout.trim().split('\n').at(-1) || 'config.toml.bak';
    showToast(`已创建备份：${path}`, 'success');
  } else {
    showToast(`备份失败: ${result.stderr || '无法创建备份'}`, 'error');
  }
}

dom.actionValidate?.addEventListener('click', () => runConfigAction(validateConfigAction));
dom.actionSave?.addEventListener('click', () => runConfigAction(() => saveConfigAction(false)));
dom.actionSaveRestart?.addEventListener('click', async () => {
  const ok = await showConfirmModal('保存并重启', '保存当前配置并将立即重启 EasyTier 网络核心，是否继续？', '保存并重启');
  if (ok) runConfigAction(() => saveConfigAction(true));
});
dom.actionReload?.addEventListener('click', async () => {
  await runConfigAction(loadSettingsConfig);
});
dom.actionBackup?.addEventListener('click', () => runConfigAction(backupConfigAction));

// ==========================================
// Overview & Metrics Polling (Exact Backend Mapping)
// ==========================================

function updateStatusUI(status, metrics = {}) {
  const wasManuallyStopped = state.lastStatus?.manual_stop === '1';
  state.lastStatus = status;
  state.lastMetrics = metrics;
  if (wasManuallyStopped !== (status.manual_stop === '1')) syncPollingVisibility();
  renderServiceMode(status);

  const running = status.state === 'running';
  const homePaused = status.home_paused === '1' && status.manual_stop !== '1';
  if (!running) {
    readRequests.topology.invalidate();
    dom.topologyRefreshBtn?.classList.remove('is-spinning');
    renderTopology([]);
    state.lastTopologyAt = 0;
  }

  // Global Header State Pill
  dom.globalStatePill.dataset.state = running ? 'running' : 'stopped';
  dom.globalStatePill.querySelector('.state-text').textContent = running ? '运行中' : homePaused ? '自动待机' : '已停止';

  // Version Badge with clean short formatting
  if (status.module_version && dom.versionBadge) {
    const shortVer = formatShortVersion(status.module_version);
    dom.versionBadge.textContent = shortVer;
    dom.versionBadge.title = `TierNest Core ${status.module_version}`;
  }

  // Overview Hero Card
  dom.heroIconBox.dataset.state = running ? 'running' : 'stopped';
  dom.heroIconBox.innerHTML = running
    ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>'
    : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="10" y1="15" x2="10" y2="9"/><line x1="14" y1="15" x2="14" y2="9"/></svg>';

  dom.overviewStateHeadline.textContent = running ? 'EasyTier 核心正常运行中' : status.manual_stop === '1' ? '已手动停止 · 全部后台已关闭' : homePaused ? `自动待机 · ${status.home_detection_mode === 'event' ? '已连接可信网络' : '路由器代理可用'}` : 'EasyTier 已停止 (未启动)';
  dom.overviewUpdatedTime.textContent = new Date().toLocaleTimeString();
  dom.overviewFrameworkTag.textContent = status.framework || 'KernelSU';

  // Mode badge & warning banner
  const isArgsMode = status.config_mode === 'command_args';
  if (dom.overviewModeBadge) {
    dom.overviewModeBadge.textContent = isArgsMode ? '参数模式 (args)' : '配置模式 (TOML)';
    dom.overviewModeBadge.classList.toggle('args-mode', isArgsMode);
  }
  if (dom.commandArgsBanner) {
    dom.commandArgsBanner.style.display = isArgsMode ? 'flex' : 'none';
  }

  // Quick Status Items
  dom.statPid.textContent = status.pid || '—';
  dom.statPid.title = status.pid || '—';
  dom.statTun.textContent = status.tun || '—';
  dom.statTun.title = status.tun || '—';
  dom.statIp.textContent = status.virtual_ipv4 || '未分配';
  dom.statIp.title = status.virtual_ipv4 || '未分配';
  dom.statNetwork.textContent = status.network_name || '—';
  dom.statNetwork.title = status.network_name || '—';

  const routeCountSuffix = metrics.route_count !== undefined ? ` · ${metrics.route_count} 条` : '';
  const localOverrideCount = Number(metrics.local_route_override_count ?? status.local_route_override_count) || 0;
  const localOverrideSuffix = localOverrideCount > 0 ? ` · 本地直连 ${localOverrideCount}` : '';
  const androidTableCount = Number(metrics.android_app_table_count ?? status.android_app_table_count) || 0;
  const androidTableSuffix = androidTableCount > 0 ? ` · Android表 ${androidTableCount}` : '';
  const modeLabels = { upstream: '上游主表', 'target-main': 'VPN主表', dedicated: '专用表' };
  const modeLabel = modeLabels[status.route_mode_active] || status.route_mode_active || '';
  const modeSuffix = modeLabel ? ` · ${modeLabel}` : '';
  const routeText = status.rule_priority
    ? `表 ${status.route_table || '20110'} (pref ${status.rule_priority})${routeCountSuffix}${localOverrideSuffix}${androidTableSuffix}${modeSuffix}`
    : status.route_table
      ? `表 ${status.route_table}${routeCountSuffix}${localOverrideSuffix}${androidTableSuffix}${modeSuffix}`
      : '未启用';
  dom.statRoute.textContent = routeText;
  dom.statRoute.title = routeText;

  const vpnText = status.external_vpn === 'none' || !status.external_vpn ? '未检测到' : status.external_vpn;
  dom.statVpn.textContent = vpnText;
  dom.statVpn.title = vpnText;

  // Performance Metrics (Mapped accurately from backend metrics.sh)
  // 1. CPU
  const cpuPercent = metrics.cpu_percent !== undefined ? metrics.cpu_percent : '0.0';
  const cpuStr = String(cpuPercent).includes('%') ? String(cpuPercent) : `${cpuPercent}%`;
  dom.metricCpu.textContent = cpuStr;
  const cpuNum = parseFloat(cpuPercent) || 0;
  dom.metricCpuBar.style.width = `${Math.min(100, Math.max(2, cpuNum * 2))}%`;

  // 2. RSS & VM & Threads & FDs
  const rssKb = parseInt(metrics.rss_kb, 10) || 0;
  const vmKb = parseInt(metrics.vm_kb, 10) || 0;
  dom.metricRss.textContent = rssKb > 0 ? formatBytes(rssKb * 1024) : (running ? '0 B' : '—');
  const threads = metrics.threads || 0;
  const fds = metrics.fd_count || 0;
  dom.metricRssNote.textContent = running && (vmKb > 0 || threads > 0)
    ? `虚拟: ${formatBytes(vmKb * 1024)} · 线程: ${threads} · FD: ${fds}`
    : '常驻内存集';

  // 3. Runtime / Uptime
  const runtimeSec = parseInt(metrics.runtime_seconds, 10) || 0;
  dom.metricUptime.textContent = runtimeSec > 0 ? formatUptime(runtimeSec) : (running ? '运行中' : '已停止');
  dom.metricUptimeNote.textContent = runtimeSec > 0 ? '自核心启动' : (running ? '刚启动' : '核心未运行');

  // 4. TUN RX / TX
  const rxBytes = parseInt(metrics.tun_rx_bytes, 10) || 0;
  const txBytes = parseInt(metrics.tun_tx_bytes, 10) || 0;
  dom.metricTunRx.textContent = formatBytes(rxBytes);
  dom.metricTunTx.textContent = formatBytes(txBytes);
  dom.metricTunNote.textContent = status.tun ? `网卡 ${status.tun} 累计传输` : '网卡累计传输';

  // 5. Log Size
  const totalLogBytes = parseInt(metrics.log_total_bytes, 10) || 0;
  dom.metricLogSize.textContent = totalLogBytes > 0 ? formatBytes(totalLogBytes) : '0 B';
  const coreLogBytes = parseInt(metrics.core_log_bytes, 10) || 0;
  const netLogBytes = parseInt(metrics.network_log_bytes, 10) || 0;
  const transportLogBytes = parseInt(metrics.transport_log_bytes, 10) || 0;
  const modLogBytes = parseInt(metrics.module_log_bytes, 10) || 0;
  dom.metricLogDetail.textContent = `核心 ${formatBytes(coreLogBytes)} · 监测 ${formatBytes(netLogBytes)} · 传输 ${formatBytes(transportLogBytes)} · 模块 ${formatBytes(modLogBytes)}`;

  // 6. VPN Restarts & Health
  const vpnRestarts = Number(metrics.vpn_restart_count) || 0;
  const underlayRestarts = Number(metrics.underlay_restart_count) || 0;
  const rpcRestarts = Number(metrics.rpc_restart_count) || 0;
  const healthRestarts = Number(metrics.health_restart_count) || 0;
  const routeSyncs = Number(metrics.route_sync_count) || 0;
  const endpointCount = Number(metrics.transport_endpoint_count ?? status.transport_endpoint_count) || 0;
  const recoveryReason = metrics.last_recovery_reason && metrics.last_recovery_reason !== 'none'
    ? metrics.last_recovery_reason
    : '';
  const recoveryStatus = metrics.last_recovery_status && metrics.last_recovery_status !== 'none'
    ? metrics.last_recovery_status
    : '';
  const recoveryDuration = Number(metrics.last_recovery_duration) || 0;
  dom.metricVpnRestarts.textContent = `${vpnRestarts + underlayRestarts + rpcRestarts + healthRestarts} 次重启`;
  dom.metricHealthDetail.textContent = `VPN ${vpnRestarts} · 上联 ${underlayRestarts} · RPC ${rpcRestarts} · 健康 ${healthRestarts} · 路由 ${routeSyncs} · 端点 ${endpointCount}`;
  dom.metricHealthDetail.title = recoveryReason
    ? `最近恢复：${recoveryReason} / ${recoveryStatus || 'unknown'} / ${recoveryDuration}s`
    : '尚无自动恢复记录';
}


const SVG_NS = 'http://www.w3.org/2000/svg';
const topologyKindLabels = { local: '本机', gateway: '子网网关', peer: '设备节点', public: '公网中继', subnet: '代理网段', unknown: '信息缺失' };

function topologyText(value, fallback = '—') {
  const text = String(value ?? '').trim();
  return text && text !== '-' ? text : fallback;
}

function topologyShortLabel(value, max = 26) {
  const text = topologyText(value, '未知');
  let width = 0, result = '';
  for (const character of text) {
    width += character.codePointAt(0) > 255 ? 2 : 1;
    if (width > max - 1) return `${result}…`;
    result += character;
  }
  return result;
}

function createSvgElement(tag, attrs = {}) {
  const element = document.createElementNS(SVG_NS, tag);
  Object.entries(attrs).forEach(([key, value]) => element.setAttribute(key, String(value)));
  return element;
}

function formatNodeConnectionText(node) {
  if (node.connectionType === 'local') return '本机';
  if (node.connectionType === 'subnet') return `由 ${node.nextHopHostname} 发布`;
  if (node.connectionType === 'direct') return '直连 (DIRECT)';
  if (node.connectionType === 'relay') return `经公网服务器 ${node.relayedBy || node.nextHopHostname || '公网中继'}`;
  if (node.connectionType === 'virtual_hop') return `经虚拟节点 ${node.nextHopHostname || node.nextHopIpv4 || '虚拟下一跳'}`;
  return node.reported ? `经未知/其他下一跳 ${node.nextHopHostname || node.nextHopIpv4 || '待确认'}` : '未上报完整信息（占位）';
}

function showTopologyDetail(node) {
  if (!dom.topologyDetail || !node) return;
  state.selectedTopologyNodeId = node.id;

  // Highlight selected node visual in SVG
  if (dom.topologySvg) {
    dom.topologySvg.querySelectorAll('.topology-node').forEach((el) => {
      const selected = el.getAttribute('data-node-id') === node.id;
      el.classList.toggle('is-selected', selected);
      el.setAttribute('aria-pressed', String(selected));
    });
  }

  const ancestors = new Set();
  const byId = new Map(state.topologyNodes.map(item => [item.id, item]));
  for (let cursor = node; cursor && !ancestors.has(cursor.id); cursor = byId.get(cursor.displayParentId)) ancestors.add(cursor.id);
  dom.topologySvg?.querySelectorAll('.topology-edge').forEach(edge => {
    edge.classList.toggle('is-path', ancestors.has(edge.dataset.edgeFrom) && ancestors.has(edge.dataset.edgeTo));
  });

  // Highlight selected card in virtual nodes list
  if (dom.topologyVirtualNodesList) {
    dom.topologyVirtualNodesList.querySelectorAll('.topology-node-card').forEach((el) => {
      el.classList.toggle('is-selected', el.dataset.nodeId === node.id);
      el.setAttribute('aria-pressed', String(el.dataset.nodeId === node.id));
    });
  }

  const title = document.createElement('div');
  title.className = 'topology-detail-title';

  const nameWrap = document.createElement('div');
  nameWrap.className = 'topology-detail-name-wrap';
  const dot = document.createElement('i');
  dot.className = `topology-legend-dot ${node.kind}`;
  const name = document.createElement('strong');
  name.textContent = node.hostname;
  nameWrap.append(dot, name);

  const badge = document.createElement('span');
  badge.className = 'section-badge';
  badge.textContent = topologyKindLabels[node.kind] || node.kind;
  title.append(nameWrap, badge);

  const grid = document.createElement('div');
  grid.className = 'topology-detail-grid';

  const fields = [
    ['虚拟 IP', node.ipv4],
    ['节点类型', topologyKindLabels[node.kind] || node.kind],
    ['连接方式', formatNodeConnectionText(node)],
    ['连接路径', node.connectionPath],
    ['延迟', node.latency > 0 ? `${Math.round(node.latency)} ms` : (node.kind === 'local' ? '0 ms (本地)' : '—')],
    ['路径跳数', node.pathLength > 0 ? `${node.pathLength} 跳` : (node.kind === 'local' ? '0 跳' : '—')],
    ['具体下一跳', node.nextHopHostname || node.nextHopIpv4],
    ['代理网段', node.proxyCidrs],
    ['路径说明', node.warning || (node.foldedVia?.length ? `公网节点已折叠：${node.foldedVia.join(' → ')}` : '基于本机当前路由，不代表全网所有物理连接')],
    ['核心版本', node.version ? `v${node.version}` : '—'],
  ];

  fields.forEach(([label, value]) => {
    const item = document.createElement('span');
    const strong = document.createElement('strong');
    strong.textContent = `${label}：`;
    item.append(strong, document.createTextNode(topologyText(value)));
    grid.append(item);
  });

  dom.topologyDetail.replaceChildren(title, grid);
}

function renderVirtualNodesList(virtualNodes) {
  if (!dom.topologyVirtualNodesList) return;
  dom.topologyVirtualNodesList.replaceChildren();

  if (dom.topologyVirtualCountBadge) {
    dom.topologyVirtualCountBadge.textContent = `${virtualNodes.length} 个虚拟节点`;
  }

  if (virtualNodes.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty-item-placeholder';
    empty.textContent = '暂无虚拟节点连接数据';
    dom.topologyVirtualNodesList.append(empty);
    return;
  }

  virtualNodes.forEach((node) => {
    const card = document.createElement('article');
    const isSelected = state.selectedTopologyNodeId === node.id;
    card.className = `topology-node-card ${node.kind}${isSelected ? ' is-selected' : ''}`;
    card.dataset.nodeId = node.id;
    card.setAttribute('role', 'button');
    card.setAttribute('aria-pressed', String(isSelected));
    card.setAttribute('tabindex', '0');

    // Header
    const header = document.createElement('div');
    header.className = 'topology-node-card-header';

    const titleWrap = document.createElement('div');
    titleWrap.className = 'topology-node-card-title-wrap';

    const dot = document.createElement('i');
    dot.className = `topology-legend-dot ${node.kind}`;

    const title = document.createElement('strong');
    title.className = 'topology-node-card-name';
    title.textContent = node.hostname;

    titleWrap.append(dot, title);

    const badgesWrap = document.createElement('div');
    badgesWrap.className = 'topology-node-card-badges';

    const kindLabel = topologyKindLabels[node.kind] || node.kind;
    const kindBadge = document.createElement('span');
    kindBadge.className = `mode-tag ${node.kind}`;
    kindBadge.textContent = kindLabel;

    badgesWrap.append(kindBadge);
    header.append(titleWrap, badgesWrap);

    // Body Grid
    const grid = document.createElement('div');
    grid.className = 'topology-node-card-grid';

    const items = [
      ['虚拟 IP', node.ipv4 || '—'],
      ['连接方式', formatNodeConnectionText(node)],
      ['连接路径', node.connectionPath || '—'],
      ['具体下一跳', node.nextHopHostname || node.nextHopIpv4 || '—'],
      ['路径跳数', node.pathLength > 0 ? `${node.pathLength} 跳` : (node.kind === 'local' ? '0 跳' : '—')],
      ['路径延迟', node.latency > 0 ? `${Math.round(node.latency)} ms` : (node.kind === 'local' ? '0 ms (本地)' : '—')],
      ['代理网段', node.proxyCidrs || '—'],
      ['核心版本', node.version ? `v${node.version}` : '—'],
    ];

    items.forEach(([label, value]) => {
      const item = document.createElement('div');
      item.className = 'topology-node-card-item';
      const k = document.createElement('span');
      k.className = 'topology-node-card-key';
      k.textContent = label;
      const v = document.createElement('span');
      v.className = 'topology-node-card-val font-mono';
      v.textContent = String(value);
      item.append(k, v);
      grid.append(item);
    });

    card.append(header, grid);

    const activate = () => {
      showTopologyDetail(node);
      dom.topologyVirtualNodesList?.querySelectorAll('.topology-node-card').forEach((c) => {
        c.classList.toggle('is-selected', c.dataset.nodeId === node.id);
      });
    };
    card.addEventListener('click', activate);
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        activate();
      }
    });

    dom.topologyVirtualNodesList.append(card);
  });
}

function renderTopology(rawRoutes) {
  if (!dom.topologySvg) return;
  state.rawTopologyRoutes = Array.isArray(rawRoutes) ? rawRoutes : [];
  const graph = buildTopologyGraph(state.rawTopologyRoutes, state.topologyFilter);
  const { nodes, virtualNodes, edges, localNode } = graph;
  state.topologyNodes = nodes;
  dom.topologySvg.replaceChildren();
  dom.topologySvg.setAttribute('viewBox', `0 0 ${graph.width} ${graph.height}`);
  dom.topologySvg.style.aspectRatio = `${graph.width} / ${graph.height}`;
  dom.topologySvg.setAttribute('aria-label', '本机路由拓扑树；实线为已知路由连接，虚线为折叠或未完整展开的路径');
  const byId = new Map(nodes.map(node => [node.id, node]));
  edges.forEach(edge => {
    const from = byId.get(edge.from), to = byId.get(edge.to);
    if (!from || !to) return;
    const path = createSvgElement('path', {
      d: `M ${from.x + 12} ${from.y + from.height} V ${to.y + to.height / 2} H ${to.x}`,
      class: `topology-edge${edge.relay ? ' is-relay' : ''}${edge.folded ? ' is-folded' : ''}${edge.uncertain ? ' is-uncertain' : ''}${edge.subnet ? ' is-subnet' : ''}`,
      'data-edge-from': edge.from, 'data-edge-to': edge.to,
      'data-uncertain': String(edge.uncertain),
    });
    const title = createSvgElement('title'); title.textContent = edge.label;
    path.append(title); dom.topologySvg.append(path);
  });
  for (const node of nodes) {
    const group = createSvgElement('g', {
      id: node.id, 'data-node-id': node.id,
      class: `topology-node ${node.kind}${node.reported ? '' : ' is-placeholder-node'}`,
      transform: `translate(${node.x} ${node.y})`,
      tabindex: '0', role: 'button',
      'aria-label': `${node.hostname}，${formatNodeConnectionText(node)}`,
      'aria-pressed': 'false',
      'data-topology-x': node.x, 'data-topology-y': node.y,
      'data-topology-depth': node.depth, 'data-reported': String(Boolean(node.reported)),
    });
    const title = createSvgElement('title');
    title.textContent = `${node.hostname}\n${node.ipv4 || '无虚拟 IP'}\n${node.connectionPath || node.warning || ''}`;
    group.append(title, createSvgElement('rect', { width: node.width, height: node.height, rx: 12, class: 'topology-node-box' }));
    group.append(createSvgElement('circle', { cx: 15, cy: 20, r: 4, class: 'topology-node-core' }));
    const name = createSvgElement('text', { x: 27, y: 24, class: 'topology-node-label' });
    name.textContent = topologyShortLabel(node.hostname, Math.floor((node.width - 44) / 7.6));
    const address = createSvgElement('text', { x: 15, y: 43, class: 'topology-node-address' });
    address.textContent = node.kind === 'subnet' ? topologyShortLabel(`网关 ${node.nextHopHostname}`, Math.floor((node.width - 30) / 6.6)) : node.ipv4 || (node.reported ? '无虚拟 IP · 公网节点' : '缺少节点记录 · 仅路径占位');
    const meta = createSvgElement('text', { x: 15, y: 61, class: 'topology-node-meta' });
    const connection = node.connectionType === 'local' ? '本机 · 路由观察起点'
      : node.kind === 'subnet' ? '代理网段 · 由上级网关发布'
      : !node.reported ? '路径信息缺失 · 待确认'
      : node.foldedVia?.length ? `中继路径 · 经 ${node.foldedVia.join(' → ')}`
      : node.edgeUncertain ? (node.pathLength > 2 ? `${node.pathLength} 跳 · 中间路径未展开` : '路径未确认')
      : `${topologyKindLabels[node.kind]} · ${node.connectionType === 'direct' ? '直连' : '经上级下一跳'}`;
    const latency = node.latency > 0 ? ` · ${Math.round(node.latency)} ms` : '';
    meta.textContent = topologyShortLabel(connection + latency, Math.floor((node.width - 30) / 6.3));
    group.append(name, address, meta);
    const activate = () => showTopologyDetail(node);
    group.addEventListener('click', activate);
    group.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); activate(); }
    });
    dom.topologySvg.append(group);
  }
  const visibleDevices = nodes.filter(n => n.reported);
  const placeholders = nodes.filter(n => !n.reported && n.kind !== 'subnet').length;
  dom.topologyPlaceholder.style.display = nodes.length ? 'none' : 'grid';
  dom.topologyNodeCount.textContent = `${graph.reportedCount} 个节点`;
  dom.topologySummaryTitle.textContent = localNode ? `${localNode.hostname} 的路由拓扑` : nodes.length ? '本机信息未上报' : '等待 EasyTier 节点数据';
  dom.topologySummaryText.textContent = nodes.length
    ? `显示 ${visibleDevices.length}/${graph.reportedCount} 个节点 · ${nodes.filter(n => n.kind === 'subnet').length} 个代理网段${placeholders ? ` · ${placeholders} 个待确认占位` : ''}`
    : 'EasyTier 连接后将在这里显示实际下一跳关系。';
  renderVirtualNodesList(virtualNodes);
  const selected = nodes.find(n => n.id === state.selectedTopologyNodeId) || localNode || nodes[0];
  if (selected) showTopologyDetail(selected);
  else { state.selectedTopologyNodeId = null; dom.topologyDetail?.replaceChildren(); }
}

function loadTopology({ quiet = false, force = false } = {}) {
  if (!dom.topologySvg || !pageIsVisible()) return Promise.resolve();
  return readRequests.topology.run('topology', async isCurrent => {
    if (!quiet) dom.topologyRefreshBtn?.classList.add('is-spinning');
    try {
      const result = await runControl('topology-json');
      if (!isCurrent() || !pageIsVisible()) return;
      if (result.errno !== 0) throw new Error(result.stderr || '拓扑读取失败');
      const routes = JSON.parse(result.stdout?.trim() || '[]');
      if (!Array.isArray(routes)) throw new Error('拓扑数据格式无效');
      renderTopology(routes);
      state.lastTopologyAt = Date.now();
    } catch (error) {
      if (!isCurrent() || !pageIsVisible()) return;
      if (!quiet) showToast(`拓扑加载失败：${String(error)}`, 'error');
      renderTopology([]);
    } finally {
      if (isCurrent()) dom.topologyRefreshBtn?.classList.remove('is-spinning');
    }
  }, { force });
}

function parseOverviewSnapshot(stdout) {
  const values = parseKeyValue(stdout);
  if (values.schema !== '1' || !['running', 'stopped'].includes(values['status.state'])) throw new Error('概览快照格式无效');
  const status = {}, metrics = {};
  Object.entries(values).forEach(([key, value]) => {
    if (key.startsWith('status.')) status[key.slice(7)] = value;
    else if (key.startsWith('metrics.')) metrics[key.slice(8)] = value;
  });
  return { status, metrics };
}

function refreshOverviewStatus({ quiet = false, force = false } = {}) {
  if (!pageIsVisible()) return Promise.resolve();
  return readRequests.overview.run('overview', async isCurrent => {
    if (!quiet) { state.busy = true; document.body.classList.add('is-busy'); }
    try {
      const result = await runControl('overview');
      if (!isCurrent() || !pageIsVisible()) return;
      if (result.errno !== 0) throw new Error(result.stderr || result.stdout || '概览读取失败');
      const { status, metrics } = parseOverviewSnapshot(result.stdout);
      updateStatusUI(status, metrics);
    } catch (error) {
      if (!isCurrent() || !pageIsVisible()) return;
      console.error('refreshOverviewStatus error:', error);
      dom.globalStatePill.dataset.state = 'error';
      dom.globalStatePill.querySelector('.state-text').textContent = '读取失败';
    } finally {
      if (isCurrent()) { state.busy = false; document.body.classList.remove('is-busy'); }
    }
  }, { force });
}

// Global Refresh Button
dom.globalRefreshBtn?.addEventListener('click', () => {
  refreshOverviewStatus();
  if (state.activeTab === 'tab-logs') loadCurrentLogs();
  showToast('状态已刷新', 'info');
});

let serviceModeBusy = false;
let serviceModeDirty = false;
let homeFieldsLoaded = false;
let detectionDirty = false;
let detectionLoaded = false;
const modeSelect = document.getElementById('service-mode-select');
const modeSave = document.getElementById('service-mode-save');
const homeLearn = document.getElementById('home-network-learn');
const homeTarget = document.getElementById('home-network-target');
const homePort = document.getElementById('home-network-port');
const homeNetworkList = document.getElementById('home-network-list');
const detectionSelect = document.getElementById('home-detection-select');
const detectionInterval = document.getElementById('home-check-interval');
const detectionSave = document.getElementById('home-detection-save');

function renderDetectionFields() {
  const eventMode = detectionSelect?.value === 'event';
  document.getElementById('home-interval-field').hidden = eventMode;
  document.getElementById('home-detection-hint').textContent = eventMode
    ? '首次保存网络时验证代理；之后只在 Wi-Fi 连接、断开或切换时判断。Wi-Fi 未断开时，路由器代理故障不会自动唤起手机核心。'
    : '输入正整数秒，例如 30、60 或 300。同一网络连续两次代理验证失败后恢复手机核心。';
}

function renderHomeNetworks(status) {
  let networks = [];
  try {
    networks = base64ToUtf8(status.home_networks_b64 || '').split('\n').filter(Boolean).map(row => row.split('|'))
      .filter(parts => parts.length === 5 && /^wlan\d+$/.test(parts[0]) &&
        /^\d{1,3}(\.\d{1,3}){3}$/.test(parts[1]) && /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/.test(parts[2]) &&
        /^\d{1,3}(\.\d{1,3}){3}$/.test(parts[3]) && /^\d{1,5}$/.test(parts[4]));
  } catch { /* An invalid status payload must never become executable markup. */ }
  document.getElementById('home-network-status').textContent = networks.length
    ? `已记住 ${networks.length} 个可代理网络` : '尚未记住可代理的网络';
  if (!homeNetworkList) return;
  homeNetworkList.replaceChildren();
  networks.forEach(([iface, gateway, mac, target, port]) => {
    const id = `${iface}-${gateway}-${mac.replace(/:/g, '')}`;
    const row = document.createElement('div');
    row.className = 'home-network-row';
    const info = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = `网关 ${gateway}`;
    const detail = document.createElement('span');
    detail.className = 'form-hint';
    detail.textContent = `MAC ${mac} · 验证 ${target}:${port}`;
    info.append(title, detail);
    if (status.home_paused === '1' && status.manual_stop !== '1' && status.home_active_id === id) {
      const active = document.createElement('span');
      active.className = 'home-network-active';
      active.textContent = status.home_detection_mode === 'event' ? '已连接此可信网络' : '正在代替手机组网';
      info.append(active);
    }
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn btn-secondary';
    remove.dataset.homeNetworkId = id;
    remove.textContent = '移除';
    remove.setAttribute('aria-label', `移除网关 ${gateway}，MAC ${mac}`);
    remove.disabled = serviceModeBusy;
    remove.addEventListener('click', async () => {
      if (serviceModeBusy || !/^[a-zA-Z0-9_.-]+$/.test(id)) return;
      const lastHint = networks.length === 1 ? '这是最后一条记录，移除后会切回手动模式；已手动停止的服务仍保持停止。' : '';
      if (await showConfirmModal('移除此网络', `移除 ${gateway} 后，连接它将不再自动待机。${lastHint}`, '移除', true)) {
        runModeAction('home-forget', id);
      }
    });
    row.append(info, remove);
    homeNetworkList.append(row);
  });
}

function renderServiceMode(status) {
  if (!modeSelect) return;
  if (!serviceModeDirty && !serviceModeBusy) modeSelect.value = status.service_mode === 'auto' ? 'auto' : 'manual';
  const modeText = status.service_mode === 'auto' ? '自动模式' : '手动模式';
  document.getElementById('service-mode-status').textContent = status.manual_stop === '1'
    ? `${modeText} · 已手动停止，点击启动才会恢复。`
    : status.home_paused === '1' ? `${modeText} · 自动待机，${status.home_detection_mode === 'event' ? '已连接可信网络' : '路由器代理可用'}。`
    : `${modeText} · ${status.state === 'running' ? '服务运行中' : '服务未运行'}`;
  if (!detectionDirty && !serviceModeBusy) {
    detectionSelect.value = status.home_detection_mode === 'event' ? 'event' : 'poll';
    detectionInterval.value = status.home_check_interval || '30';
    detectionLoaded = true;
    renderDetectionFields();
  }
  document.getElementById('home-detection-status').textContent = status.home_watch_error
    ? `检测异常：${status.home_watch_error}`
    : `${status.home_detection_mode === 'event' ? '已保存：网络变化时检测' : `已保存：每 ${status.home_check_interval || '30'} 秒检测`}。${status.service_mode !== 'auto' || status.manual_stop === '1' ? '下次启动自动模式时生效。' : ''}`;
  renderHomeNetworks(status);
  if (!homeFieldsLoaded && status.home_configured === '1') {
    if (homeTarget && document.activeElement !== homeTarget && !homeTarget.value) homeTarget.value = status.home_target || '';
    if (homePort && document.activeElement !== homePort) homePort.value = status.home_port || '80';
    homeFieldsLoaded = true;
  }
}

modeSelect?.addEventListener('change', () => { serviceModeDirty = true; });
detectionSelect?.addEventListener('change', () => { detectionDirty = true; renderDetectionFields(); });
detectionInterval?.addEventListener('input', () => { detectionDirty = true; });
async function runModeAction(cmd, ...args) {
  if (serviceModeBusy) return;
  serviceModeBusy = true;
  [modeSave, modeSelect, homeLearn, detectionSave, detectionSelect, detectionInterval].forEach(el => { if (el) el.disabled = true; });
  homeNetworkList?.querySelectorAll('button').forEach(el => { el.disabled = true; });
  try {
    const result = await runControl(cmd, ...args);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || '操作失败');
    if (cmd === 'home-detection-save') detectionDirty = false;
    else if (cmd.startsWith('service-mode-') || cmd === 'home-forget') serviceModeDirty = false;
    showToast(cmd === 'home-detection-save' ? '检测设置已保存' : cmd === 'home-learn' ? '当前 Wi-Fi 已保存，已有记录保留' : cmd === 'home-forget' ? '网络记录已移除' : '运行方式已应用', 'success');
  } catch (error) {
    showToast(error.message || '操作失败', 'error');
  } finally {
    serviceModeBusy = false;
    [modeSave, modeSelect, homeLearn, detectionSave, detectionSelect, detectionInterval].forEach(el => { if (el) el.disabled = false; });
    homeNetworkList?.querySelectorAll('button').forEach(el => { el.disabled = false; });
    await refreshOverviewStatus({ quiet: true, force: true });
  }
}
modeSave?.addEventListener('click', () => {
  const mode = modeSelect.value;
  if (mode !== 'manual' && mode !== 'auto') return;
  runModeAction(`service-mode-${mode}`);
});
detectionSave?.addEventListener('click', () => {
  if (!detectionLoaded) { showToast('请先等待检测设置读取完成', 'info'); return; }
  const mode = detectionSelect.value;
  const value = detectionInterval.value.trim();
  if (!['poll', 'event'].includes(mode) || !/^\d+$/.test(value) ||
      !Number.isSafeInteger(Number(value)) || Number(value) < 1 || Number(value) > 2147483647) {
    showToast('检测间隔须为正整数秒（最大 2147483647）', 'error');
    return;
  }
  runModeAction('home-detection-save', mode, String(Number(value)));
});
homeLearn?.addEventListener('click', () => {
  const ip = homeTarget.value.trim();
  const port = homePort.value.trim();
  // Only numeric values cross the shell bridge; never interpolate arbitrary input.
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip) || ip.split('.').some(n => Number(n) > 255) ||
      !/^\d{1,5}$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
    showToast('请填写有效的 IPv4 地址和 1–65535 的 HTTP 端口', 'error');
    return;
  }
  runModeAction('home-learn', ip, String(Number(port)));
});

// Service Control Buttons
dom.controlBtns.forEach((btn) => {
  btn.addEventListener('click', async () => {
    const cmd = btn.dataset.controlCmd;

    if (cmd === 'export-log') {
      btn.disabled = true;
      showToast('正在聚合诊断日志并导出…', 'info');
      const res = await runControl('export-log');
      btn.disabled = false;
      if (res.errno === 0) {
        const path = res.stdout.trim().split('\n').at(-1);
        dom.exportPathText.textContent = path;
        showToast('日志已导出到 Download 目录', 'success');
      } else {
        showToast(`导出失败: ${res.stderr || '未知错误'}`, 'error');
      }
      return;
    }

    const actionMap = {
      start: { title: '启动服务', msg: '按所选模式启动？自动模式在已记住的路由器可代理时进入待机。', confirmText: '启动', isDanger: false },
      stop: { title: '停止全部服务', msg: '关闭核心、守护、网络监视和自动模式。配置保留，重启手机后也保持停止，直到再次点击启动。确认继续？', confirmText: '停止服务', isDanger: true },
      restart: { title: '重启 EasyTier', msg: '重启会短暂中断 EasyTier 网络连接，确认继续？', confirmText: '重启', isDanger: false },
      'sync-routes': { title: '同步路由保护', msg: '立即校验并同步 EasyTier 策略路由表？', confirmText: '同步路由', isDanger: false },
    };

    const action = actionMap[cmd];
    if (action) {
      const ok = await showConfirmModal(action.title, action.msg, action.confirmText, action.isDanger);
      if (!ok) return;
    }

    btn.disabled = true;
    showToast(`正在执行 ${cmd}…`, 'info');
    const res = await runControl(cmd);
    btn.disabled = false;

    if (res.errno === 0) {
      showToast(`${action ? action.title : cmd} 完成`, 'success');
      await refreshOverviewStatus({ quiet: true, force: true });
    } else {
      showToast(`执行失败: ${res.stderr || res.stdout || '请检查模块日志'}`, 'error');
    }
  });
});

// Copy Export Path
dom.exportResultBox?.addEventListener('click', async () => {
  const path = dom.exportPathText.textContent.trim();
  if (!path || path === '尚未导出') return;
  try {
    await navigator.clipboard.writeText(path);
    showToast('导出路径已复制到剪贴板', 'success');
  } catch {
    showToast('无法自动复制，请长按路径复制', 'info');
  }
});

// ==========================================
// Logs Viewer & Syntax Highlighter
// ==========================================

function renderLogsView() {
  const lines = state.rawLogContent.split('\n');
  const kw = state.logFilterKeyword.trim();

  const filtered = filterLogLines(lines, kw);

  dom.logLinesCounter.textContent = `${filtered.length} / ${lines.length} 行`;

  if (filtered.length === 0) {
    dom.logOutputContainer.innerHTML = '<div class="log-placeholder">无匹配日志内容</div>';
    return;
  }

  dom.logOutputContainer.innerHTML = filtered.map((line) => formatLogLine(line, kw)).join('');
}

function loadCurrentLogs({ scrollToBottom = false } = {}) {
  if (!pageIsVisible() || state.activeTab !== 'tab-logs') return Promise.resolve();
  const target = state.activeLogType, lines = state.logLinesLimit;
  const files = { network: 'network-watch.log', transport: 'transport.log', hotspot: 'hotspot.log', tiernest: 'tiernest.log' };
  const logFile = `${MODDIR}/logs/${files[target] || files.tiernest}`;
  dom.logActivePath.textContent = logFile;
  return readRequests.logs.run(`${target}:${lines}`, async isCurrent => {
    const canApply = () => isCurrent() && pageIsVisible() && state.activeTab === 'tab-logs' && state.activeLogType === target && state.logLinesLimit === lines;
    try {
      const result = await safeExec(`tail -n ${lines} "${logFile}" 2>/dev/null`);
      if (!canApply()) return;
      state.rawLogContent = result.errno !== 0 ? `无法读取日志: ${result.stderr || '日志不存在或无读取权限'}` : result.stdout?.trimEnd() || '暂无日志内容';
      renderLogsView();
      if (scrollToBottom) dom.logOutputContainer.scrollTop = dom.logOutputContainer.scrollHeight;
    } catch (error) {
      if (!canApply()) return;
      state.rawLogContent = `读取日志异常: ${String(error)}`;
      renderLogsView();
    }
  });
}

// Log Tab Controls
dom.logSegmentedBtns.forEach((btn) => {
  btn.addEventListener('click', () => {
    dom.logSegmentedBtns.forEach((b) => b.classList.remove('is-active'));
    btn.classList.add('is-active');
    state.activeLogType = btn.dataset.logTarget;
    loadCurrentLogs({ scrollToBottom: true });
  });
});

dom.logLinesSelect?.addEventListener('change', () => {
  state.logLinesLimit = parseInt(dom.logLinesSelect.value, 10) || 200;
  loadCurrentLogs();
});

dom.logSearchInput?.addEventListener('input', () => {
  state.logFilterKeyword = dom.logSearchInput.value;
  dom.logClearSearchBtn.style.display = state.logFilterKeyword ? 'block' : 'none';
  renderLogsView();
});

dom.logClearSearchBtn?.addEventListener('click', () => {
  dom.logSearchInput.value = '';
  state.logFilterKeyword = '';
  dom.logClearSearchBtn.style.display = 'none';
  renderLogsView();
});

dom.logRefreshBtn?.addEventListener('click', () => {
  loadCurrentLogs();
  showToast('日志已刷新', 'info');
});

dom.logScrollBottomBtn?.addEventListener('click', () => {
  dom.logOutputContainer.scrollTop = dom.logOutputContainer.scrollHeight;
});

dom.logCopyBtn?.addEventListener('click', async () => {
  if (!state.rawLogContent) return;
  try {
    await navigator.clipboard.writeText(state.rawLogContent);
    showToast('全部日志已复制到剪贴板', 'success');
  } catch {
    showToast('复制失败，请手动选择复制', 'error');
  }
});

dom.logAutoRefreshToggle?.addEventListener('change', (e) => {
  state.autoRefreshLog = e.target.checked;
  if (state.autoRefreshLog) {
    showToast('日志自动刷新已开启 (5秒，后台自动暂停)', 'info');
    startLogPolling();
  } else {
    showToast('日志自动刷新已关闭', 'info');
    stopLogPolling();
  }
});

dom.topologyRefreshBtn?.addEventListener('click', () => loadTopology());
dom.topologyFilterBtns.forEach((button) => {
  button.addEventListener('click', () => {
    const filter = button.dataset.topologyFilter === 'virtual_only' ? 'virtual_only' : 'all';
    state.topologyFilter = filter;
    if (typeof localStorage !== 'undefined') localStorage.setItem('tiernest_topology_filter', filter);
    dom.topologyFilterBtns.forEach((item) => item.classList.toggle('is-active', item === button));
    renderTopology(state.rawTopologyRoutes);
  });
});

// ==========================================
// Initialization
// ==========================================

async function initializeApp() {
  try {
    const info = typeof moduleInfo === 'function' ? moduleInfo() : null;
    if (dom.versionBadge) {
      dom.versionBadge.textContent = formatShortVersion(info);
    }
  } catch (e) {
    if (dom.versionBadge) dom.versionBadge.textContent = '版本未知';
  }

  // Sync initial button states
  dom.topologyFilterBtns.forEach((item) => item.classList.toggle('is-active', item.dataset.topologyFilter === state.topologyFilter));

  // Initial load
  await refreshOverviewStatus();
  await loadTopology({ quiet: true });

  // KernelSU may keep the WebView alive after the shortcut is backgrounded.
  // Pause every shell-backed poll while hidden, then refresh immediately on resume.
  syncPollingVisibility();
  document.addEventListener('visibilitychange', () => {
    syncPollingVisibility({ refreshNow: pageIsVisible() });
  });

  window.addEventListener('beforeunload', () => {
    stopStatusPolling();
    stopLogPolling();
  });
}

initializeApp();
