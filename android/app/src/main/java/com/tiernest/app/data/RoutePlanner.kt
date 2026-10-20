package com.tiernest.app.data

data class Ipv4Cidr(val network: Long, val prefix: Int) {
    override fun toString(): String = "${(24 downTo 0 step 8).joinToString(".") { ((network shr it) and 255).toString() }}/$prefix"
    fun overlaps(other: Ipv4Cidr): Boolean {
        val mask = mask(minOf(prefix, other.prefix))
        return network and mask == other.network and mask
    }
    companion object { fun mask(prefix: Int) = if (prefix == 0) 0L else (0xffffffffL shl (32 - prefix)) and 0xffffffffL }
}

data class RoutePlan(val routes: List<String>, val excluded: List<String>)

object RoutePlanner {
    fun cidr(input: String): Ipv4Cidr? {
        val parts = input.split('/')
        if (parts.size > 2) return null
        val octets = parts[0].split('.')
        if (octets.size != 4 || octets.any { it.length !in 1..3 || !it.all { c -> c in '0'..'9' } }) return null
        val values = octets.map { it.toInt() }
        if (values.any { it !in 0..255 }) return null
        val prefix = if (parts.size == 1) 32 else parts[1].toIntOrNull() ?: return null
        if (prefix !in 0..32) return null
        val address = values.fold(0L) { acc, value -> (acc shl 8) or value.toLong() }
        return Ipv4Cidr(address and Ipv4Cidr.mask(prefix), prefix)
    }

    fun safe(value: Ipv4Cidr): Boolean {
        val first = value.network shr 24
        return value.prefix >= 8 && first != 0L && first != 127L && first < 224 &&
            !value.overlaps(Ipv4Cidr(0xa9fe0000, 16))
    }

    /** Keep exactly the same address coverage while dropping routes already
     * covered by a broader route. Never merge adjacent ranges into new space. */
    fun minimalRoutes(routes: List<String>): List<String> =
        compact(routes.map { requireNotNull(cidr(it)) { "无效 IPv4 路由" } })

    private fun compact(routes: List<Ipv4Cidr>): List<String> {
        val kept = mutableListOf<Ipv4Cidr>()
        // Normalized CIDRs are either disjoint or nested. In address order,
        // only the last retained range can cover the next candidate.
        routes.sortedWith(compareBy<Ipv4Cidr> { it.network }.thenBy { it.prefix }).forEach { candidate ->
            if (kept.lastOrNull()?.overlaps(candidate) != true) kept.add(candidate)
        }
        return kept.map { it.toString() }.sorted()
    }

    private fun proxyDestination(input: String): Ipv4Cidr? {
        val arrow = input.indexOf("->")
        if (arrow < 0) return cidr(input)
        // EasyTier advertises real_cidr->mapped_cidr. Only the mapped side is
        // reachable through the overlay; the real side may even be loopback.
        val source = cidr(input.substring(0, arrow)) ?: return null
        val destination = cidr(input.substring(arrow + 2)) ?: return null
        return destination.takeIf { it.prefix == source.prefix }
    }

    fun plan(local: String, peers: List<Peer>, physicalNetworks: List<String>): RoutePlan {
        val physical = physicalNetworks.mapNotNull(::cidr)
        val excluded = mutableListOf<String>()
        val routes = mutableListOf<Ipv4Cidr>()
        fun add(raw: String, proxy: Boolean = false) {
            if (raw.isBlank() || raw == "-") return
            val value = if (proxy) proxyDestination(raw) else cidr(raw)
            if (value == null || !safe(value) || physical.any { value.overlaps(it) }) {
                excluded.add(raw)
            } else routes.add(value)
        }
        add(local)
        for (peer in peers) {
            add(peer.ipv4)
            peer.subnets.forEach { add(it, proxy = true) }
        }
        // Both backends and hotspot sharing use the same minimal coverage.
        // A peer joining an already-routed subnet must not rebuild kernel rules.
        return RoutePlan(compact(routes), excluded.distinct())
    }
}
