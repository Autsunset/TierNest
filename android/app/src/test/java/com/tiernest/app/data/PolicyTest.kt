package com.tiernest.app.data

import com.tiernest.app.LegacyImport
import org.junit.Assert.*
import org.junit.Test

class PolicyTest {
    @Test fun manualStopDominatesEveryAutomaticCombination() {
        for (screen in listOf(false, true)) for (interactive in listOf(false, true))
            for (automatic in listOf(false, true)) for (home in listOf(false, true))
                for (healthy in listOf(false, true)) assertEquals(DesiredConnection.STOPPED,
                    ConnectionPolicy.decide(false, screen, interactive, automatic, home, healthy))
    }

    @Test fun eventFailureResumesWithoutChangingTheSelectedMode() {
        assertEquals(DesiredConnection.CONNECTED, ConnectionPolicy.decide(true, false, true, true, true, false))
        assertEquals(DesiredConnection.HOME_STANDBY, ConnectionPolicy.decide(true, false, true, true, true, true))
        assertEquals(DesiredConnection.SCREEN_STANDBY, ConnectionPolicy.decide(true, true, false, false, false, true))
        assertEquals(DesiredConnection.CONNECTED, ConnectionPolicy.decide(true, false, false, false, false, true))
    }

    @Test fun routesNeverIncludeExitRoutesOrPhysicalNetworks() {
        val peer = Peer("test-node", "10.77.0.8", 1, 4.0, "DIRECT",
            listOf("0.0.0.0/0", "0.0.0.0/1", "128.0.0.0/1", "127.0.0.1/32", "192.0.2.0/24", "198.51.100.0/24", "::/0", "224.0.0.0/4"))
        val plan = RoutePlanner.plan("10.77.0.2/24", listOf(peer), listOf("192.0.2.8/24"))
        assertEquals(listOf("10.77.0.0/24", "10.77.0.8/32", "198.51.100.0/24"), plan.routes)
        assertTrue(plan.excluded.contains("192.0.2.0/24"))
        assertTrue(plan.excluded.contains("::/0"))
    }

    @Test fun withdrawnPeerRoutesDisappear() {
        val peer = Peer("test", "10.77.0.3", 1, null, "DIRECT", listOf("198.51.100.0/24"))
        assertTrue(RoutePlanner.plan("10.77.0.2/24", listOf(peer), emptyList()).routes.contains("198.51.100.0/24"))
        assertFalse(RoutePlanner.plan("10.77.0.2/24", emptyList(), emptyList()).routes.contains("198.51.100.0/24"))
    }

    @Test fun invalidAddressesAndLinkLocalAreRejected() {
        listOf("1.2.3.999", "1.2.3.-1", "1.2.3", "1.2.3.4/33", "1.2.3.4/24/8", "1.2.3.4;id").forEach { assertNull(RoutePlanner.cidr(it)) }
        assertFalse(RoutePlanner.safe(RoutePlanner.cidr("169.254.0.0/16")!!))
        assertEquals("10.77.0.0/24", RoutePlanner.cidr("10.77.0.42/24").toString())
    }

    @Test fun oldSingleAndMultiHomeRecordsAreReadableWithoutRewritingOriginals() {
        val old = "interface=wlan0\ngateway=192.0.2.1\nmac=02:00:00:00:00:01\ntarget=10.77.0.1\nport=80\n"
        val multi = "# fixture\nnetwork=wlan0|192.0.2.1|02:00:00:00:00:01|10.77.0.1|80\nnetwork=wlan1|198.51.100.1|02:00:00:00:00:02|10.78.0.1|8080\n"
        assertEquals(1, LegacyImport.homes(old).size)
        assertEquals(2, LegacyImport.homes(multi).size)
        assertEquals("02:00:00:00:00:01", LegacyImport.homes(old).single().mac)
    }

    @Test fun peerLatencyIsTheNextHopAndUnknownIsNotZero() {
        val peers = PeerCodec.decode("""[{"hostname":"synthetic","ipv4":"10.77.0.2","path_len":2,"next_hop_hostname":"relay","next_hop_lat":3.5,"proxy_cidrs":"198.51.100.0/24"}, {"hostname":"unknown"}]""")
        assertEquals(3.5, peers.first().latency!!, 0.0)
        assertNull(peers.last().latency)
        assertNull(peers.last().hops)
    }
}
