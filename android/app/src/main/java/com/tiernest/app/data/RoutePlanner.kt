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
    fun minimalRoutes(routes: List<String>): List<String> {
        val kept = mutableListOf<Ipv4Cidr>()
        routes.map { requireNotNull(cidr(it)) { "无效 IPv4 路由" } }.distinct()
            .sortedWith(compareBy<Ipv4Cidr> { it.prefix }.thenBy { it.network }).forEach { candidate ->
                if (kept.none { it.prefix <= candidate.prefix && it.overlaps(candidate) }) kept.add(candidate)
            }
        return kept.map { it.toString() }.sorted()
    }

    fun plan(local: String, peers: List<Peer>, physicalNetworks: List<String>): RoutePlan {
        val physical = physicalNetworks.mapNotNull(::cidr)
        val candidates = listOf(local) + peers.flatMap { listOf(it.ipv4) + it.subnets }
        val excluded = mutableListOf<String>()
        val routes = candidates.filter { it.isNotBlank() && it != "-" }.mapNotNull { raw ->
            val value = cidr(raw)
            if (value == null || !safe(value) || physical.any { value.overlaps(it) }) {
                excluded.add(raw); null
            } else value.toString()
        }.distinct().sorted()
        return RoutePlan(routes, excluded.distinct())
    }
}
