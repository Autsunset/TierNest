package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class ModeTopologyTest {
    @Test fun newInstallUsesVpnAndLegacyChoicesRemainRoot() {
        assertEquals(ConnectionMode.VPN, ModePolicy.initial(null, false))
        assertEquals(ConnectionMode.ROOT, ModePolicy.initial(null, true))
        assertEquals(ConnectionMode.VPN, ModePolicy.initial("VPN", true))
        assertEquals(ConnectionMode.ROOT, ModePolicy.initial("ROOT", false))
        assertFalse(ModePolicy.automatic(ConnectionMode.VPN, true))
        assertTrue(ModePolicy.automatic(ConnectionMode.ROOT, true))
    }

    @Test fun vpnRuntimeDoesNotRewriteTheOriginalConfiguration() {
        val original = """
            hostname = "fixture-phone"
            ipv4 = "10.77.0.2/24"
            dhcp = false
            [network_identity]
            network_name = "fixture-network"
            network_secret = "fixture-only"
            [flags]
            bind_device = true
            dev_name = "customtun0"
        """.trimIndent()
        val vpn = ConfigCodec.effective(original, ConnectionMode.VPN)
        val parsed = ConfigCodec.parse(vpn)
        val flags = parsed["flags"] as Map<*, *>
        assertEquals(false, flags["bind_device"])
        assertEquals("", flags["dev_name"])
        assertTrue(original.contains("bind_device = true"))
        assertEquals("fixture-only", (parsed["network_identity"] as Map<*, *>)["network_secret"])
    }

    private fun peer(name: String, id: String, hops: Int?, next: String = "", subnets: List<String> = emptyList()) =
        Peer(name, "10.77.0.${id.toIntOrNull() ?: 9}", hops, null, "", subnets, id = id, nextHopId = next)

    @Test fun routesUseIdsAndKeepUnknownMultiHopPathsDashed() {
        val peers = listOf(peer("local", "1", 0), peer("same-name", "2", 1),
            peer("same-name", "3", 1), peer("leaf", "4", 2, "2"), peer("far", "5", 4, "3"))
        val graph = TopologyBuilder.build(peers, "10.77.0.1/24")
        val leaf = graph.rows.single { it.node.peer?.id == "4" }
        assertEquals("id:2", leaf.edge!!.parent)
        assertFalse(leaf.edge.dashed)
        assertTrue(graph.rows.single { it.node.peer?.id == "5" }.edge!!.dashed)
    }

    @Test fun cyclesUnknownHopsAndWithdrawalsNeverInventDirectLinks() {
        val graph = TopologyBuilder.build(listOf(peer("local", "1", 0), peer("a", "2", 2, "3"),
            peer("b", "3", 2, "2"), peer("unknown", "4", 3, "99", listOf("198.51.100.0/24"))), "")
        assertEquals(graph.rows.size, graph.rows.map { it.node.key }.toSet().size)
        assertEquals(6, graph.rows.size)
        assertTrue(graph.warnings.isNotEmpty())
        assertTrue(graph.rows.any { it.node.placeholder })
        assertTrue(graph.rows.filter { it.edge != null }.all { it.edge!!.dashed })
        assertEquals(1, TopologyBuilder.build(emptyList(), "").rows.size)
    }

    @Test fun malformedHopCountsAreUnknownInsteadOfLocal() {
        val peers = PeerCodec.decode("""[{"path_len":null},{"path_len":"bad"},{"path_len":-1},{"path_len":0}]""")
        assertTrue(peers.take(3).all { it.hops == null })
        assertEquals(0, peers.last().hops)
    }
}
