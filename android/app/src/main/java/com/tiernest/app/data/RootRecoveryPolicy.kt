package com.tiernest.app.data

enum class RecoveryDecision { STOPPED, RECONCILE, RETRY, FAILED }

/** Main-thread/controller-lock confined. At most one automatic retry during a
 * service lifetime; settings/network events never replenish the budget. */
class RootRecoveryPolicy {
    private var rootWasReady = false
    private var retryUsed = false
    private var retryPending = false

    fun connected(mode: ConnectionMode) { if (mode == ConnectionMode.ROOT) rootWasReady = true }

    fun reconcile(desired: DesiredConnection) {
        if (desired != DesiredConnection.CONNECTED) retryPending = false
    }

    /** Commit the budget only when the new backend is actually being started,
     * after backoff and the latest stop/screen/home/mode checks. */
    fun starting(mode: ConnectionMode) {
        if (retryPending && mode == ConnectionMode.ROOT) retryUsed = true
        retryPending = false
    }

    fun decide(requested: Boolean, currentMode: ConnectionMode, failedMode: ConnectionMode?,
               requestChanged: Boolean, rootTimeout: Boolean, cleanupSucceeded: Boolean,
               standby: Boolean): RecoveryDecision {
        retryPending = false
        if (!requested) return RecoveryDecision.STOPPED
        if (!cleanupSucceeded) return RecoveryDecision.FAILED
        if (requestChanged || (failedMode != null && failedMode != currentMode)) return RecoveryDecision.RECONCILE
        if (!rootTimeout || failedMode != ConnectionMode.ROOT || !rootWasReady) return RecoveryDecision.FAILED
        // Lock-screen pause is a user policy, not a failed reconnect attempt.
        if (standby) return RecoveryDecision.RECONCILE
        if (retryUsed) return RecoveryDecision.FAILED
        retryPending = true
        return RecoveryDecision.RETRY
    }
}
