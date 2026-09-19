package com.tiernest.app.data

data class TopologyNode(val key: String, val name: String, val address: String,
    val peer: Peer? = null, val placeholder: Boolean = false, val subnet: Boolean = false)
data class TopologyEdge(val parent: String, val child: String, val dashed: Boolean, val label: String)
data class TopologyRow(val node: TopologyNode, val depth: Int, val last: Boolean,
    val rails: List<Boolean>, val edge: TopologyEdge?)
data class Topology(val rows: List<TopologyRow>, val warnings: List<String>)

/** Local routing view, not an inferred physical map. Never invent hidden hops. */
object TopologyBuilder {
    fun build(peers: List<Peer>, localCidr: String): Topology {
        val local = peers.firstOrNull { it.hops == 0 }
        val root = TopologyNode("local", local?.name?.ifBlank { "本机" } ?: "本机", local?.ipv4?.ifBlank { localCidr } ?: localCidr, local)
        val nodes = linkedMapOf(root.key to root)
        val edges = linkedMapOf<String, TopologyEdge>()
        val warnings = linkedSetOf<String>()
        val remotes = peers.filter { it !== local }.mapIndexed { index, peer ->
            val base = if (peer.id.isNotBlank()) "id:${peer.id}" else "peer:${peer.ipv4}:${peer.name}"
            val key = if (base in nodes) "$base:$index" else base
            TopologyNode(key, peer.name, peer.ipv4, peer).also { nodes[key] = it }
        }
        for (node in remotes) {
            val peer = node.peer!!
            if (peer.hops == 1) {
                edges[node.key] = TopologyEdge(root.key, node.key, false, "直连")
                continue
            }
            val candidates = remotes.filter { candidate ->
                val p = candidate.peer!!
                when {
                    peer.nextHopId.isNotBlank() -> p.id == peer.nextHopId
                    validAddress(peer.nextHopIpv4) -> p.ipv4.substringBefore('/') == peer.nextHopIpv4.substringBefore('/')
                    peer.nextHop !in setOf("", "-", "DIRECT", "Local") -> p.name == peer.nextHop
                    else -> false
                }
            }
            var parent = candidates.singleOrNull()
            if (parent == node) parent = null
            if (parent == null && peer.hops != null && peer.hops > 1) {
                val identity = peer.nextHopId.ifBlank { peer.nextHopIpv4.ifBlank { peer.nextHop } }
                val key = "unknown:${identity.ifBlank { node.key }}"
                parent = nodes[key] ?: TopologyNode(key, "未确认的下一跳", identity, placeholder = true).also {
                    nodes[key] = it
                    edges[key] = TopologyEdge(root.key, key, true, "信息未上报")
                }
                warnings += "部分下一跳未上报或无法唯一识别"
            }
            val folded = peer.hops == null || peer.hops > 2 || parent?.peer?.hops != 1
            edges[node.key] = TopologyEdge(parent?.key ?: root.key, node.key, folded,
                when {
                    peer.hops == null -> "路径未知"
                    peer.hops > 2 -> "折叠 ${peer.hops - 1} 跳"
                    parent?.placeholder == true -> "下一跳未确认"
                    else -> "${peer.hops} 跳路径"
                })
        }
        // Break cycles explicitly, retaining a warning and a dashed root link.
        for (node in remotes) {
            var cursor = node.key
            val visited = mutableSetOf<String>()
            while (cursor != root.key && cursor in edges) {
                if (!visited.add(cursor)) {
                    edges[node.key] = TopologyEdge(root.key, node.key, true, "路由信息冲突")
                    warnings += "发现环路或冲突，已标记为未确认路径"
                    break
                }
                cursor = edges.getValue(cursor).parent
            }
        }
        nodes.values.toList().forEach { node -> node.peer?.subnets.orEmpty().forEach { subnet ->
            val key = "subnet:${node.key}:$subnet"
            nodes[key] = TopologyNode(key, "发布子网", subnet, subnet = true)
            edges[key] = TopologyEdge(node.key, key, true, "子网代理")
        } }
        val children = edges.values.groupBy { it.parent }
        val rows = mutableListOf<TopologyRow>()
        val stack = java.util.ArrayDeque<TopologyRow>()
        stack.add(TopologyRow(root, 0, true, emptyList(), null))
        while (stack.isNotEmpty()) {
            val row = stack.removeLast()
            rows += row
            val next = children[row.node.key].orEmpty().sortedWith(compareBy({ nodes[it.child]?.subnet == true }, { nodes[it.child]?.name }))
            next.withIndex().toList().asReversed().forEach { (index, edge) ->
                val node = nodes[edge.child] ?: return@forEach
                val rails = if (row.depth == 0) emptyList() else row.rails + !row.last
                stack.add(TopologyRow(node, row.depth + 1, index == next.lastIndex, rails, edge))
            }
        }
        return Topology(rows, warnings.toList())
    }
    private fun validAddress(value: String) = RoutePlanner.cidr(value) != null
}
