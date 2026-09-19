package com.tiernest.app.data

enum class DesiredConnection { STOPPED, CONNECTED, HOME_STANDBY, SCREEN_STANDBY }

object ConnectionPolicy {
    fun decide(requested: Boolean, suspendScreen: Boolean, interactive: Boolean,
               automatic: Boolean, trustedHome: Boolean, eventSourceHealthy: Boolean): DesiredConnection = when {
        !requested -> DesiredConnection.STOPPED
        automatic && !eventSourceHealthy -> DesiredConnection.CONNECTED
        suspendScreen && !interactive -> DesiredConnection.SCREEN_STANDBY
        automatic && trustedHome -> DesiredConnection.HOME_STANDBY
        else -> DesiredConnection.CONNECTED
    }
}
