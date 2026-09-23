package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class MinimalRoutesTest {
    @Test fun peerChurnInsideAnExistingSubnetKeepsTheVpnRouteSignature() {
        val before = listOf("10.77.0.0/24", "198.51.100.9/32")
        val joined = before + listOf("10.77.0.2/32", "10.77.0.9/32", "10.77.0.0/24")
        assertEquals(RoutePlanner.minimalRoutes(before), RoutePlanner.minimalRoutes(joined))
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

    @Test fun cidrParsingAcceptsOnlyDottedDecimalOctets() {
        assertEquals("10.77.0.0/24", RoutePlanner.cidr("10.77.0.9/24").toString())
        assertEquals("1.2.3.4/32", RoutePlanner.cidr("001.2.3.4").toString())
        for (invalid in listOf("", "10.77.0", "10.77.0.9.1", "10.77.0.256", "10.77.0.9a", "1.2.3.4/33", "1.2.3.4/x",
            "1.2.3.4/24/1", "1..3.4", "1.2.3.1234", "٣.2.3.4", "-1.2.3.4", "+1.2.3.4", "1.2.3.4 ")) {
            assertNull(invalid, RoutePlanner.cidr(invalid))
        }
    }
}
