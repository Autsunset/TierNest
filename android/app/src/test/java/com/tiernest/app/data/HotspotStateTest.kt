package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class HotspotStateTest {
    @Test fun oldPreferencesLeaveHotspotSharingOff() {
        assertFalse(Preferences().hotspotAccess)
        val prefs = Preferences(hotspotAccess = true, screenSuspend = true)
        assertTrue(prefs.copy(connectionMode = ConnectionMode.VPN).hotspotAccess)
        assertTrue(prefs.copy(requested = false).screenSuspend)
    }

    @Test fun unsupportedOrUnknownStatusNeverClaimsSharingIsActive() {
        assertEquals(HotspotState.DISABLED, HotspotState.parse(null))
        assertEquals(HotspotState.ACTIVE, HotspotState.parse("active"))
        assertEquals(HotspotState.ERROR, HotspotState.parse("unexpected"))
        assertEquals(HotspotState.UNAVAILABLE, HotspotState.parse("unavailable"))
        assertEquals(HotspotState.CONFLICT, HotspotState.parse("conflict"))
    }

    @Test fun advertisedHotspotSubnetIsExcludedFromTheOverlayPlan() {
        val peer = Peer("synthetic", "10.77.0.9", 1, null, "DIRECT", listOf("192.168.77.0/24", "198.51.100.0/24"))
        val plan = RoutePlanner.plan("10.77.0.2/24", listOf(peer), listOf("192.168.77.1/24"))
        assertFalse(plan.routes.contains("192.168.77.0/24"))
        assertTrue(plan.excluded.contains("192.168.77.0/24"))
        assertTrue(plan.routes.contains("198.51.100.0/24"))
    }
}
