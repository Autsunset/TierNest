// A local routing view, not a claim about every physical link in the network.
// EasyTier next_hop identifies the FIRST hop. For paths > 2, the rest is unknown.
const text = (value) => String(value ?? '').trim().replace(/^[-]$/, '');
const ipKey = (value) => text(value).split('/')[0];
const hops = (value) => value !== null && value !== undefined && text(value) !== '' && Number.isInteger(Number(value)) && Number(value) >= 0 ? Number(value) : null;
const identity = (hostname, ipv4, peerId = '') => `route-${encodeURIComponent(JSON.stringify([text(peerId), hostname, ipv4]))}`;
const kindOf = (node) => node.isLocal ? 'local' : node.proxyCidrs ? 'gateway' : !node.ipv4 || /^PublicServer[_-]/i.test(node.hostname) ? 'public' : 'peer';

export function buildTopologyGraph(rawRoutes, filter = 'all') {
  const records = new Map();
  for (const item of Array.isArray(rawRoutes) ? rawRoutes : []) {
    if (!item || typeof item !== 'object') continue;
    const ipv4 = text(item.ipv4);
    const hostname = text(item.hostname) || ipv4;
    if (!hostname) continue;
    const node = {
      id: identity(hostname, ipv4, item.peer_id ?? item.peerId), hostname, ipv4,
      proxyCidrs: Array.isArray(item.proxy_cidrs ?? item.proxyCidrs) ? (item.proxy_cidrs ?? item.proxyCidrs).join(', ') : text(item.proxy_cidrs ?? item.proxyCidrs),
      nextHopHostname: text(item.next_hop_hostname ?? item.nextHopHostname),
      nextHopIpv4: text(item.next_hop_ipv4 ?? item.nextHopIpv4),
      pathLength: hops(item.path_len ?? item.pathLen),
      latency: Number(item.path_latency ?? item.pathLatency ?? item.next_hop_lat) || 0,
      version: text(item.version), reported: true, parentId: null,
      connectionType: 'unknown_hop', edgeUncertain: false, warning: '',
    };
    // Prefer an explicit Local record if a duplicate snapshot contains both forms.
    if (!records.has(node.id) || /^Local$/i.test(node.nextHopHostname)) records.set(node.id, node);
  }
  const reportedNodes = [...records.values()].sort((a, b) => a.id.localeCompare(b.id));
  const localNode = reportedNodes.find(n => /^Local$/i.test(n.nextHopHostname)) || reportedNodes.find(n => n.pathLength === 0);
  if (!reportedNodes.length) return { nodes: [], edges: [], virtualNodes: [], localNode: null, reportedCount: 0, width: 400, height: 220 };
  for (const node of reportedNodes) {
    node.isLocal = node === localNode;
    node.kind = kindOf(node);
  }
  const source = localNode || {
    id: 'source-missing', hostname: '本机信息未上报', ipv4: '', kind: 'unknown', reported: false,
    parentId: null, connectionType: 'unknown_hop', warning: '本轮路由数据缺少 Local 记录',
  };
  source.connectionType = localNode ? 'local' : 'unknown_hop';
  const all = new Map(reportedNodes.map(n => [n.id, n]));
  all.set(source.id, source);
  const names = new Map();
  const addresses = new Map();
  for (const n of reportedNodes) {
    names.set(n.hostname, [...(names.get(n.hostname) || []), n]);
    if (n.ipv4) addresses.set(ipKey(n.ipv4), [...(addresses.get(ipKey(n.ipv4)) || []), n]);
  }
  const isDirect = n => n.pathLength === 1 && (!n.nextHopHostname || /^DIRECT$/i.test(n.nextHopHostname) || n.nextHopHostname === n.hostname)
    || n.pathLength === null && /^DIRECT$/i.test(n.nextHopHostname);
  const unresolved = (node, warning) => {
    if (!all.has('paths-unresolved')) all.set('paths-unresolved', {
      id: 'paths-unresolved', hostname: '路径待确认', ipv4: '', kind: 'unknown', reported: false,
      parentId: source.id, connectionType: 'unknown_hop', edgeUncertain: true,
      warning: '下一跳缺失、冲突或未提供足够路径信息',
    });
    node.parentId = 'paths-unresolved';
    node.connectionType = 'unknown_hop';
    node.edgeUncertain = true;
    node.warning = warning;
  };
  for (const node of reportedNodes) {
    if (node === localNode) continue;
    if (isDirect(node)) {
      node.parentId = source.id;
      node.connectionType = 'direct';
      continue;
    }
    const nextName = node.nextHopHostname;
    const nextIp = node.nextHopIpv4;
    if (/^(Local|DIRECT)$/i.test(nextName) || node.pathLength === 0 || node.pathLength === 1) {
      unresolved(node, '跳数与下一跳信息不一致');
      continue;
    }
    let matches = names.get(nextName) || [];
    if (matches.length > 1 && nextIp) matches = matches.filter(n => ipKey(n.ipv4) === ipKey(nextIp));
    if (!nextName && nextIp && !/^(Local|DIRECT)$/i.test(nextIp)) matches = addresses.get(ipKey(nextIp)) || [];
    if (matches.length > 1 || ((names.get(nextName)?.length || 0) > 1 && !matches.length)) {
      unresolved(node, '存在同名下一跳，无法唯一确定连接');
      continue;
    }
    let parent = matches[0];
    if (parent === node || parent === localNode || parent && !isDirect(parent)) {
      unresolved(node, '下一跳不是已确认的一跳邻居，可能存在冲突或环路');
      continue;
    }
    if (!parent) {
      const hint = nextName || (/^(Local|DIRECT)$/i.test(nextIp) ? '' : nextIp);
      if (!hint) { unresolved(node, '缺少下一跳信息'); continue; }
      const id = `missing-${encodeURIComponent(JSON.stringify([hint, nextIp]))}`;
      parent = all.get(id);
      if (!parent) {
        parent = {
          id, hostname: hint, ipv4: nextName ? '' : nextIp, kind: /^PublicServer[_-]/i.test(hint) ? 'public' : 'unknown',
          reported: false, parentId: source.id, connectionType: 'unknown_hop', edgeUncertain: true,
          warning: '其他路由提及此下一跳，但它自身的节点记录未上报',
        };
        all.set(id, parent);
      }
    }
    node.parentId = parent.id;
    node.connectionType = parent.kind === 'public' ? 'relay' : parent.reported ? 'virtual_hop' : 'unknown_hop';
    node.relayedBy = parent.kind === 'public' ? parent.hostname : null;
    node.edgeUncertain = !parent.reported || node.pathLength !== 2;
    if (node.pathLength > 2) node.warning = `从下一跳到目标还有 ${node.pathLength - 1} 跳，中间节点未展开`;
    else if (node.pathLength === null) node.warning = '路径跳数未上报，不能确认下一跳与目标直接相连';
  }
  // Construct the displayed path from observed first-hop facts, never invented intermediates.
  for (const node of reportedNodes) {
    const parent = all.get(node.parentId);
    if (node === localNode) node.connectionPath = node.hostname;
    else if (node.connectionType === 'direct') node.connectionPath = `${source.hostname} → ${node.hostname}`;
    else if (parent && parent.id !== 'paths-unresolved') node.connectionPath = `${source.hostname} → ${parent.hostname} → ${node.pathLength === 2 ? '' : '… → '}${node.hostname}`;
    else node.connectionPath = `${source.hostname} → … → ${node.hostname}（路径待确认）`;
  }
  for (const parent of reportedNodes) {
    for (const cidr of new Set(parent.proxyCidrs.split(/[\s,]+/).filter(Boolean))) {
      const id = `subnet-${parent.id}-${encodeURIComponent(cidr)}`;
      all.set(id, {
        id, hostname: cidr, ipv4: cidr, proxyCidrs: '', kind: 'subnet', reported: false,
        parentId: parent.id, nextHopHostname: parent.hostname, nextHopIpv4: parent.ipv4,
        connectionType: 'subnet', connectionPath: `${parent.connectionPath} → ${cidr}`,
        warning: '此网段由上级节点发布；不是额外的 EasyTier 设备',
      });
    }
  }
  const visible = [...all.values()].filter(n => filter !== 'virtual_only' || n.kind !== 'public' && !(n.kind === 'subnet' && all.get(n.parentId)?.kind === 'public'));
  const visibleIds = new Set(visible.map(n => n.id));
  const edges = [];
  for (const node of visible) {
    if (!node.parentId) continue;
    let parent = all.get(node.parentId);
    const hidden = [];
    const visited = new Set([node.id]);
    while (parent && !visibleIds.has(parent.id) && !visited.has(parent.id)) {
      visited.add(parent.id); hidden.push(parent.hostname); parent = all.get(parent.parentId);
    }
    if (!parent || visited.has(parent.id)) continue;
    node.displayParentId = parent.id;
    const folded = hidden.length > 0;
    edges.push({
      from: parent.id, to: node.id, folded,
      relay: folded || node.connectionType === 'relay',
      uncertain: folded || Boolean(node.edgeUncertain),
      subnet: node.kind === 'subnet',
      label: folded ? `经 ${hidden.join(' → ')}（已折叠）` : node.kind === 'subnet' ? '发布网段' : node.edgeUncertain ? node.warning || '路径信息不完整' : '已知路由连接',
    });
    node.foldedVia = hidden;
  }
  // A compact vertical tree: dedicated branch gutters, no overlapping node cards,
  // and no tiny text from shrinking a wide graph to a phone screen.
  const children = new Map();
  for (const n of visible) if (n.displayParentId) children.set(n.displayParentId, [...(children.get(n.displayParentId) || []), n]);
  const rank = { public: 0, gateway: 1, peer: 2, subnet: 3, unknown: 4 };
  for (const group of children.values()) group.sort((a, b) => (rank[a.kind] ?? 0) - (rank[b.kind] ?? 0) || a.id.localeCompare(b.id));
  const nodes = [];
  const walked = new Set();
  const walk = (node, depth) => {
    if (walked.has(node.id)) return;
    walked.add(node.id);
    node.depth = depth; node.x = 16 + depth * 26; node.y = 16 + nodes.length * 88;
    node.width = 368 - depth * 26; node.height = 72;
    nodes.push(node);
    for (const child of children.get(node.id) || []) walk(child, depth + 1);
  };
  walk(source, 0);
  for (const node of visible) if (!walked.has(node.id)) walk(node, 0);
  return {
    nodes, edges, localNode, virtualNodes: reportedNodes.filter(n => n.kind !== 'public'),
    reportedCount: reportedNodes.length, width: 400, height: Math.max(220, nodes.length * 88 + 16),
  };
}
