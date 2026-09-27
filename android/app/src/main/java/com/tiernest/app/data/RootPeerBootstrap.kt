package com.tiernest.app.data

import java.net.Inet6Address
import java.net.InetAddress
import java.net.URI

/** Give the Root core a numeric IPv6 bootstrap peer when Android resolves an
 * AAAA-only hostname. Keep the named peer so later reconnects can follow DNS. */
object RootPeerBootstrap {
    @Suppress("UNCHECKED_CAST")
    fun augment(configText: String, resolve: (String) -> List<InetAddress> = { InetAddress.getAllByName(it).toList() }): String {
        val config = ConfigCodec.parse(configText)
        val flags = config["flags"] as? Map<String, Any> ?: emptyMap()
        if (flags["enable_ipv6"] == false) return configText
        val peers = config["peer"] as? List<Map<String, Any>> ?: return configText
        val known = peers.mapNotNull { it["uri"] as? String }.toMutableSet()
        val bootstrapped = mutableListOf<Map<String, Any>>()
        var changed = false
        for (peer in peers) {
            val value = peer["uri"] as? String
            val uri = value?.let { runCatching { URI(it) }.getOrNull() }
            val host = uri?.host
            val authority = uri?.rawAuthority
            if (value != null && host != null && authority != null &&
                uri.scheme in setOf("tcp", "udp", "wg") && uri.port in 1..65535 &&
                ':' !in host && authority.endsWith("$host:${uri.port}", ignoreCase = true)) {
                val addresses = runCatching { resolve(host) }.getOrDefault(emptyList())
                if (addresses.isNotEmpty() && addresses.all { it is Inet6Address }) {
                    val authorityStart = value.indexOf("://") + 3
                    val hostStart = authorityStart + authority.length - host.length - uri.port.toString().length - 1
                    addresses.asSequence().filterIsInstance<Inet6Address>()
                        .filterNot { it.isAnyLocalAddress || it.isLinkLocalAddress || it.isLoopbackAddress || it.isMulticastAddress }
                        .map { value.replaceRange(hostStart, hostStart + host.length, "[${it.hostAddress}]") }
                        .distinct().take(4).forEach { candidate ->
                            if (known.add(candidate)) { bootstrapped += peer + ("uri" to candidate); changed = true }
                        }
                }
            }
            bootstrapped += peer
        }
        if (!changed) return configText
        config["peer"] = bootstrapped
        return ConfigCodec.encode(config)
    }
}
