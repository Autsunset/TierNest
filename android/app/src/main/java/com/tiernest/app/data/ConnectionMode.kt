package com.tiernest.app.data

enum class ConnectionMode(val label: String) { VPN("VPN 模式"), ROOT("Root 模式") }

object ModePolicy {
    fun initial(saved: String?, hasLegacyPreferences: Boolean): ConnectionMode =
        ConnectionMode.entries.firstOrNull { it.name == saved }
            ?: if (hasLegacyPreferences) ConnectionMode.ROOT else ConnectionMode.VPN

    fun automatic(mode: ConnectionMode, preference: Boolean) = mode == ConnectionMode.ROOT && preference
}
