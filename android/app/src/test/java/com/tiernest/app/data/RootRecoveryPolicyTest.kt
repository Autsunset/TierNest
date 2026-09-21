package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class RootRecoveryPolicyTest {
    private fun decide(policy: RootRecoveryPolicy, requested: Boolean = true, mode: ConnectionMode = ConnectionMode.ROOT,
                       failedMode: ConnectionMode? = ConnectionMode.ROOT, requestChanged: Boolean = false,
                       rootTimeout: Boolean = true, cleanupSucceeded: Boolean = true, standby: Boolean = false) =
        policy.decide(requested, mode, failedMode, requestChanged, rootTimeout, cleanupSucceeded, standby)

    @Test fun manualStopWinsEvenWhenCleanupFailedOrTimedOut() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        for (cleanup in listOf(false, true)) for (timeout in listOf(false, true))
            for (changed in listOf(false, true)) for (standby in listOf(false, true))
                assertEquals(RecoveryDecision.STOPPED,
                    decide(policy, requested = false, requestChanged = changed, rootTimeout = timeout,
                        cleanupSucceeded = cleanup, standby = standby))
        assertEquals(RecoveryDecision.RETRY, decide(policy))
    }

    @Test fun neverEstablishedRootDoesNotAutoRetry() {
        assertEquals(RecoveryDecision.FAILED, decide(RootRecoveryPolicy()))
        val vpnOnly = RootRecoveryPolicy()
        vpnOnly.connected(ConnectionMode.VPN)
        assertEquals(RecoveryDecision.FAILED, decide(vpnOnly))
    }

    @Test fun firstTimeoutAfterRootReadyRetriesExactlyOnce() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RETRY, decide(policy))
        policy.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(policy))
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(policy))
    }

    @Test fun vpnFailuresAndNonTimeoutErrorsNeverRetry() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(policy, mode = ConnectionMode.VPN, failedMode = ConnectionMode.VPN))
        assertEquals(RecoveryDecision.FAILED, decide(policy, rootTimeout = false))
        assertEquals(RecoveryDecision.FAILED, decide(policy, failedMode = null))
        assertEquals(RecoveryDecision.RETRY, decide(policy))
    }

    @Test fun failedCleanupNeverRetries() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(policy, cleanupSucceeded = false))
        assertEquals(RecoveryDecision.RETRY, decide(policy))
    }

    @Test fun newRequestOrModeSwitchReconcilesInsteadOfOverwritingUserIntent() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RECONCILE, decide(policy, requestChanged = true))
        assertEquals(RecoveryDecision.RECONCILE, decide(policy, mode = ConnectionMode.VPN, failedMode = ConnectionMode.ROOT))
        assertEquals(RecoveryDecision.RETRY, decide(policy))
    }

    @Test fun standbyReconcilesWithoutSpendingTheSingleRetry() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RECONCILE, decide(policy, standby = true))
        assertEquals(RecoveryDecision.RETRY, decide(policy))
        policy.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(policy))
        assertEquals(RecoveryDecision.RECONCILE, decide(policy, standby = true))
    }

    @Test fun freshServiceLifetimeReceivesOneNewRetryBudget() {
        val first = RootRecoveryPolicy()
        first.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RETRY, decide(first))
        first.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(first))
        val second = RootRecoveryPolicy()
        second.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RETRY, decide(second))
        second.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(second))
    }

    @Test fun homeOrScreenStandbyDuringBackoffDoesNotSpendRetryBudget() {
        for (standby in listOf(DesiredConnection.HOME_STANDBY, DesiredConnection.SCREEN_STANDBY)) {
            val policy = RootRecoveryPolicy()
            policy.connected(ConnectionMode.ROOT)
            assertEquals(RecoveryDecision.RETRY, decide(policy))
            policy.reconcile(standby)
            policy.reconcile(DesiredConnection.CONNECTED)
            policy.starting(ConnectionMode.ROOT) // Normal home-away/screen-on start.
            policy.connected(ConnectionMode.ROOT)
            assertEquals(RecoveryDecision.RETRY, decide(policy))
            policy.starting(ConnectionMode.ROOT) // This recovery really runs.
            assertEquals(RecoveryDecision.FAILED, decide(policy))
        }
    }

    @Test fun stopOrModeSwitchDuringBackoffCannotConsumeRootRetry() {
        val policy = RootRecoveryPolicy()
        policy.connected(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RETRY, decide(policy))
        policy.reconcile(DesiredConnection.STOPPED)
        policy.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RETRY, decide(policy))
        policy.starting(ConnectionMode.VPN)
        policy.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.RETRY, decide(policy))
        policy.starting(ConnectionMode.ROOT)
        assertEquals(RecoveryDecision.FAILED, decide(policy))
    }

}
