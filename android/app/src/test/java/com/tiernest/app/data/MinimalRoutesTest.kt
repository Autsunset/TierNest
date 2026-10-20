package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class MinimalRoutesTest {
    @Test fun peerChurnInsideAnExistingSubnetKeepsTheVpnRouteSignature() {
        val before = listOf("10.77.0.0/24", "198.51.100.9/32")
        val joined = before + listOf("10.77.0.2/32", "10.77.0.9/32", "10.77.0.0/24")
        assertEquals(RoutePlanner.minimalRoutes(before), RoutePlanner.minimalRoutes(joined))
    }

    @Test fun peerChurnInsideAnExistingSubnetDoesNotDirtyRootOrHotspotRules() {
        val peers = (2..200).map { Peer("fixture-$it", "10.77.0.$it", 1, null, "DIRECT", emptyList()) }
        val before = RoutePlanner.plan("10.77.0.1/24", emptyList(), emptyList())
        val joined = RoutePlanner.plan("10.77.0.1/24", peers, emptyList())
        assertEquals(listOf("10.77.0.0/24"), joined.routes)
        assertEquals(before.routes, joined.routes)
        val maintenance = RootMaintenancePolicy()
        maintenance.routesSynced(before.routes, now = 0)
        maintenance.hotspotSynced(true, now = 0)
        assertFalse(maintenance.routeSyncNeeded(joined.routes, leaseHeld = true, now = 1))
        assertFalse(maintenance.hotspotSyncNeeded(true, HotspotState.ACTIVE, now = 1))
    }

    @Test fun independentHostsAndSubnetsAreNotExpandedOrDropped() {
        val routes = listOf("10.77.0.2/32", "10.77.0.3/32", "198.51.100.0/25", "198.51.100.128/25")
        assertEquals(routes.sorted(), RoutePlanner.minimalRoutes(routes.reversed()))
    }

    @Test fun physicalConflictExclusionStillHappensBeforeMinimizing() {
        val peer = Peer("fixture", "10.77.0.9", 1, null, "DIRECT", emptyList())
        val plan = RoutePlanner.plan("10.77.0.2/24", listOf(peer), listOf("10.77.0.128/25"))
        assertEquals(listOf("10.77.0.9/32"), RoutePlanner.minimalRoutes(plan.routes))
        assertTrue(plan.excluded.contains("10.77.0.2/24"))
    }

    @Test fun nestedRangesKeepExactCoverageRegardlessOfInputOrder() {
        val routes = listOf("10.77.2.9/32", "10.77.2.128/25", "10.77.2.0/24", "10.77.0.0/23",
            "10.77.1.0/24", "10.77.3.4/32", "10.77.3.6/32", "198.51.100.8/30", "198.51.100.9/32")
        val expected = listOf("10.77.0.0/23", "10.77.2.0/24", "10.77.3.4/32", "10.77.3.6/32", "198.51.100.8/30")
        assertEquals(expected, RoutePlanner.minimalRoutes(routes))
        assertEquals(expected, RoutePlanner.minimalRoutes(routes.reversed()))
    }

    @Test fun removingABroadAdvertisementRestoresTheRemainingHostRoute() {
        val host = Peer("fixture-host", "198.51.100.9", 1, null, "DIRECT", emptyList())
        val gateway = Peer("fixture-gateway", "10.77.0.2", 1, null, "DIRECT", listOf("198.51.100.0/24"))
        assertEquals(listOf("10.77.0.0/24", "198.51.100.0/24"),
            RoutePlanner.plan("10.77.0.1/24", listOf(host, gateway), emptyList()).routes)
        assertEquals(listOf("10.77.0.0/24", "198.51.100.9/32"),
            RoutePlanner.plan("10.77.0.1/24", listOf(host), emptyList()).routes)
    }

    @Test fun mappedSubnetRoutesOnlyTheOverlayDestinationAndSharesNormalCompaction() {
        val mapped = "127.0.0.1/32->198.51.100.9/32"
        val peer = Peer("fixture-proxy", "10.77.0.2", 1, null, "DIRECT",
            listOf(mapped, "192.0.2.0/24->198.51.100.0/24", "203.0.113.0/24"))
        val plan = RoutePlanner.plan("10.77.0.1/24", listOf(peer), listOf("192.0.2.3/24"))
        assertEquals(listOf("10.77.0.0/24", "198.51.100.0/24", "203.0.113.0/24"), plan.routes)
        assertTrue(plan.excluded.isEmpty())
        assertEquals(mapped, peer.subnets.first())
        assertEquals(listOf("10.77.0.0/24", "198.51.100.9/32"),
            RoutePlanner.plan("10.77.0.1/24", listOf(peer.copy(subnets = listOf(mapped))), emptyList()).routes)
    }

    @Test fun mappedDestinationsStillRejectUnsafePhysicalAndMalformedRoutes() {
        val excluded = listOf(
            "198.51.100.0/24->192.0.2.0/24", "198.51.100.9/32->127.0.0.1/32",
            "10.0.0.0/8->0.0.0.0/8", "198.51.100.0/24->169.254.0.0/24",
            "198.51.100.9/32->224.0.0.1/32", "10.0.0.0/8->198.51.100.9/32",
            "bad->198.51.100.9/32", "->198.51.100.9/32", "198.51.100.9/32->",
            "127.0.0.1/32->198.51.100.9/32->203.0.113.9/32")
        val peer = Peer("fixture-proxy", "10.77.0.2", 1, null, "DIRECT", excluded)
        val plan = RoutePlanner.plan("10.77.0.1/24", listOf(peer), listOf("192.0.2.3/24"))
        assertEquals(listOf("10.77.0.0/24"), plan.routes)
        assertEquals(excluded, plan.excluded)
        assertNull(RoutePlanner.cidr("127.0.0.1/32->198.51.100.9/32"))
    }

    @Test fun compactingMixedPrefixesPreservesEveryAddressAndNeverMergesNeighbors() {
        val random = java.util.Random(7)
        repeat(20) {
            val original = List(100) {
                RoutePlanner.cidr("10.77.${random.nextInt(16)}.${random.nextInt(256)}/${24 + random.nextInt(9)}")!!
            }
            val compacted = RoutePlanner.minimalRoutes(original.map { it.toString() }).map { RoutePlanner.cidr(it)!! }
            assertTrue(compacted.all { it in original })
            for (suffix in 0L until 4096L) {
                val address = Ipv4Cidr(0x0a4d0000L + suffix, 32)
                assertEquals(address.toString(), original.any { it.overlaps(address) }, compacted.any { it.overlaps(address) })
            }
        }
    }

    @Test fun cidrParsingAcceptsOnlyDottedDecimalOctets() {
        assertEquals("10.77.0.0/24", RoutePlanner.cidr("10.77.0.9/24").toString())
        assertEquals("1.2.3.4/32", RoutePlanner.cidr("001.2.3.4").toString())
        for (invalid in listOf("", "10.77.0", "10.77.0.9.1", "10.77.0.256", "10.77.0.9a", "1.2.3.4/33", "1.2.3.4/x",
            "1.2.3.4/24/1", "1..3.4", "1.2.3.1234", "٣.2.3.4", "-1.2.3.4", "+1.2.3.4", "1.2.3.4 ")) {
            assertNull(invalid, RoutePlanner.cidr(invalid))
        }
    }
}
