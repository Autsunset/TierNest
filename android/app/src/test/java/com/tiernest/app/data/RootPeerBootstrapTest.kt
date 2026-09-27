package com.tiernest.app.data

import java.net.InetAddress
import org.junit.Assert.*
import org.junit.Test

class RootPeerBootstrapTest {
    private val peerUri = "tcp://edge.example.invalid:25680"
    private fun input(enabled: Boolean = true): String = ConfigCodec.encode(linkedMapOf(
        "peer" to listOf(mapOf("uri" to peerUri, "public_key" to "fixture-only")),
        "flags" to mapOf("enable_ipv6" to enabled),
    ))

    @Test fun aaaaOnlyPeerBootstrapsWithoutChangingSavedConfig() {
        val original = input()
        val runtime = RootPeerBootstrap.augment(original) { listOf(InetAddress.getByName("2001:db8::7")) }
        val peers = ConfigCodec.parse(runtime)["peer"] as List<*>
        assertEquals(2, peers.size)
        val numeric = peers[0] as Map<*, *>
        assertEquals("tcp://[2001:db8:0:0:0:0:0:7]:25680", numeric["uri"])
        assertEquals("fixture-only", numeric["public_key"])
        assertEquals(peerUri, (peers[1] as Map<*, *>)["uri"])
        assertEquals(peerUri, ((ConfigCodec.parse(original)["peer"] as List<*>)[0] as Map<*, *>)["uri"])
    }

    @Test fun mixedDnsDisabledIpv6AndFailedDnsKeepOriginal() {
        val mixed = listOf(InetAddress.getByName("192.0.2.7"), InetAddress.getByName("2001:db8::7"))
        assertEquals(input(), RootPeerBootstrap.augment(input()) { mixed })
        assertEquals(input(false), RootPeerBootstrap.augment(input(false)) { listOf(InetAddress.getByName("2001:db8::7")) })
        assertEquals(input(), RootPeerBootstrap.augment(input()) { error("DNS unavailable") })
    }
}
