import assert from 'node:assert/strict';
import { buildTopologyGraph } from '../webui/src/topology.js';
const local = { hostname: 'local', ipv4: '10.0.0.1/24', path_len: 0, next_hop_hostname: 'Local' };
const peer = (hostname, ipv4 = '', extra = {}) => ({ hostname, ipv4, path_len: 1, next_hop_hostname: 'DIRECT', ...extra });
const find = (g, name) => g.nodes.find(n => n.hostname === name);
const edge = (g, from, to) => g.edges.find(e => e.from === find(g, from)?.id && e.to === find(g, to)?.id);
const routes = [local,
  peer('gateway', '10.0.0.2', { proxy_cidrs: '192.168.1.0/24' }),
  peer('PublicServer_Shenzhen'),
  peer('phone', '10.0.0.3', { next_hop_hostname: 'PublicServer_Shenzhen', path_len: 2 }),
  peer('tablet', '10.0.0.4', { next_hop_hostname: 'gateway', path_len: 2 }),
  peer('direct', '10.0.0.5'),
  peer('distant', '10.0.0.6', { next_hop_hostname: 'gateway', path_len: 4 }),
];
const g = buildTopologyGraph(routes);
assert.equal(g.reportedCount, 7);
assert.equal(g.virtualNodes.length, 6);
assert.equal(g.localNode.hostname, 'local');
for (const [a,b] of [['local','gateway'],['local','PublicServer_Shenzhen'],['PublicServer_Shenzhen','phone'],['gateway','tablet'],['local','direct']]) {
  assert(edge(g,a,b), `${a} → ${b}`); assert.equal(edge(g,a,b).uncertain, false);
}
assert(edge(g,'gateway','192.168.1.0/24').subnet);
assert.equal(find(g,'192.168.1.0/24').reported, false);
assert.equal(edge(g,'gateway','distant').uncertain, true, 'first hop is not necessarily target\'s immediate physical parent');
assert.equal(find(g,'distant').connectionPath, 'local → gateway → … → distant');
assert.match(find(g,'distant').warning, /还有 3 跳/);
assert.equal(find(g,'phone').connectionPath, 'local → PublicServer_Shenzhen → phone');
assert.equal(find(g,'tablet').connectionType, 'virtual_hop');
assert.equal(find(g,'phone').connectionType, 'relay');

const folded = buildTopologyGraph(routes, 'virtual_only');
assert(!find(folded,'PublicServer_Shenzhen'));
assert(edge(folded,'local','phone').folded);
assert(edge(folded,'local','phone').uncertain);
assert(!edge(folded,'local','direct').folded);
assert(!edge(folded,'local','direct').uncertain);
assert.equal(folded.virtualNodes.length, g.virtualNodes.length);
assert.equal(find(folded,'phone').connectionPath, find(g,'phone').connectionPath);
assert.deepEqual(find(folded,'phone').foldedVia, ['PublicServer_Shenzhen']);

// Missing next hops use explicit non-counted placeholders, never invented online peers.
const missing = buildTopologyGraph([local, peer('remote', '10.0.0.2', { next_hop_hostname: 'missing-router', path_len: 3 })]);
assert.equal(missing.reportedCount, 2);
assert.equal(find(missing,'missing-router').reported, false);
assert(edge(missing,'local','missing-router').uncertain);
assert(edge(missing,'missing-router','remote').uncertain);
const missingPublic = buildTopologyGraph([local, peer('remote', '10.0.0.2', { next_hop_hostname: 'PublicServer_absent', path_len: 2 })], 'virtual_only');
assert(!find(missingPublic,'PublicServer_absent'));
assert(edge(missingPublic,'local','remote').folded);

// Ambiguous names must resolve by a unique next-hop address, not Map's last value.
const duplicates = [local, peer('same', '10.0.0.2'), peer('same', '10.0.0.3'), peer('remote','10.0.0.4',{path_len:2,next_hop_hostname:'same',next_hop_ipv4:'10.0.0.2/24'})];
const dup = buildTopologyGraph(duplicates);
assert.equal(find(dup,'remote').parentId, dup.nodes.find(n => n.ipv4 === '10.0.0.2').id);
const ambiguous = buildTopologyGraph(duplicates.map(n => n.hostname === 'remote' ? {...n, next_hop_ipv4:''} : n));
assert.equal(find(ambiguous,'remote').parentId, 'paths-unresolved');
const byIp = buildTopologyGraph([local, peer('gateway','10.0.0.2/24'), peer('remote','10.0.0.3',{path_len:2,next_hop_hostname:'',next_hop_ipv4:'10.0.0.2'})]);
assert(edge(byIp,'gateway','remote'));

// Bad/missing route information cannot create local nodes or fictitious DIRECT links.
for (const bad of [
  peer('remote','10.0.0.2',{path_len:undefined,next_hop_hostname:''}),
  peer('remote','10.0.0.2',{path_len:4,next_hop_hostname:'DIRECT'}),
  peer('remote','10.0.0.2',{path_len:2,next_hop_hostname:'remote'}),
  peer('remote','10.0.0.2',{path_len:1,next_hop_hostname:'another'}),
]) {
  const graph = buildTopologyGraph([bad,local]);
  assert.equal(graph.localNode.hostname,'local');
  assert.equal(find(graph,'remote').parentId,'paths-unresolved');
  assert.equal(find(graph,'remote').connectionType,'unknown_hop');
}
const selfDirect=buildTopologyGraph([local,peer('remote','10.0.0.2',{next_hop_hostname:'remote'})]);
assert(edge(selfDirect,'local','remote'));
const cycle = buildTopologyGraph([local, peer('a','10.0.0.2',{path_len:2,next_hop_hostname:'b'}), peer('b','10.0.0.3',{path_len:2,next_hop_hostname:'a'})]);
assert.equal(find(cycle,'a').parentId,'paths-unresolved'); assert.equal(find(cycle,'b').parentId,'paths-unresolved');
const noLocal = buildTopologyGraph([peer('remote','10.0.0.2')]);
assert(!noLocal.localNode); assert.equal(noLocal.reportedCount,1);
assert.equal(noLocal.nodes[0].reported,false); assert.equal(noLocal.nodes[1].kind,'peer');

// Stable ordering, no overlap, every edge endpoint rendered, even with many subnets.
const layout = graph => graph.nodes.map(n => [n.id,n.x,n.y,n.depth]);
assert.deepEqual(layout(buildTopologyGraph(routes)),layout(buildTopologyGraph([...routes].reverse().map(n => ({...n,path_latency:999})))));
const many = buildTopologyGraph([local,...Array.from({length:80},(_,i)=>peer(`peer-${i}`,`10.0.0.${i+2}`,{proxy_cidrs:`172.16.${i}.0/24`}))]);
assert.equal(many.nodes.filter(n=>n.kind==='subnet').length,80);
assert.equal(many.edges.length,many.nodes.length-1);
for (const graph of [g,folded,missing,noLocal,cycle,many]) {
  const ids = new Set(graph.nodes.map(n=>n.id));
  assert.equal(ids.size,graph.nodes.length);
  for(const e of graph.edges) { assert(ids.has(e.from));assert(ids.has(e.to));assert.notEqual(e.from,e.to); }
  for(let i=0;i<graph.nodes.length;i++) {
    const n=graph.nodes[i];assert(n.x>=0 && n.x+n.width<=graph.width);assert(n.y+n.height<=graph.height);
    if(i)assert(n.y>=graph.nodes[i-1].y+graph.nodes[i-1].height+8);
    if(n.displayParentId) assert(graph.nodes.find(p=>p.id===n.displayParentId).y<n.y);
  }
}
const noName=buildTopologyGraph([local,{ipv4:'10.0.0.2',path_len:1,next_hop_hostname:'DIRECT'}]);
assert(find(noName,'10.0.0.2'));
assert.equal(buildTopologyGraph([null,{},false]).nodes.length,0);
assert.equal(buildTopologyGraph(null).nodes.length,0);
assert.equal(buildTopologyGraph([local,local]).reportedCount,1);
console.log('Routing topology graph tests passed.');
