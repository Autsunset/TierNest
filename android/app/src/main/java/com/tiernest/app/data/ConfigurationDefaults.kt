package com.tiernest.app.data

object ConfigurationDefaults {
    fun commit(
        snapshot: Preferences,
        persistDefaults: (Map<String, String>) -> Unit,
        writeConfig: () -> Unit,
    ) {
        // The first TOML changes installation detection. Pin the current choices
        // first, even on retries: a failed disk commit can leave them in memory.
        persistDefaults(mapOf(
            "theme" to snapshot.theme.name,
            "connectionMode" to snapshot.connectionMode.name,
        ))
        writeConfig()
    }
}
