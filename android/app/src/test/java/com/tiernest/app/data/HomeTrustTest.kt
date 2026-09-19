package com.tiernest.app.data

import com.tiernest.app.LegacyImport
import org.junit.Assert.*
import org.junit.Test

class HomeTrustTest {
    @Test fun failedFirstProbeNeverEntersStandby() {
        val trust = HomeTrust()
        repeat(3) { assertFalse(trust.observe("network-a", false)) }
    }

    @Test fun secondFailureResumesAndOnlySuccessCanRestoreTrust() {
        val trust = HomeTrust()
        assertTrue(trust.observe("network-a", true))
        assertTrue(trust.observe("network-a", false))
        assertFalse(trust.observe("network-a", false))
        assertFalse(trust.observe("network-a", false))
        assertTrue(trust.observe("network-a", true))
    }

    @Test fun differentNetworkOrTargetCannotBorrowFailureGrace() {
        val trust = HomeTrust()
        assertTrue(trust.observe("network-a|target-1", true))
        assertFalse(trust.observe("network-b|target-1", false))
        assertFalse(trust.observe("network-a|target-1", false))
        assertTrue(trust.observe("network-a|target-1", true))
        assertFalse(trust.observe("network-a|target-2", false))
    }

    @Test fun disconnectAndInspectionErrorRevokeGrace() {
        val trust = HomeTrust()
        assertTrue(trust.observe("network-a", true))
        assertFalse(trust.reset())
        assertFalse(trust.observe("network-a", false))
    }

    @Test fun legacyRecordsKeepIdentityButRequirePhysicalWifiVerification() {
        val record = LegacyImport.homes("interface=wlan0\ngateway=192.0.2.1\nmac=02:00:00:00:00:01\ntarget=10.77.0.1\nport=80\n").single()
        assertFalse(record.wifiVerified)
        assertEquals(record.id, record.copy(wifiVerified = true).id)
        assertEquals(record.target, record.copy(wifiVerified = true).target)
    }
}
