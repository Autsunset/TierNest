package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class ConfigurationDefaultsTest {
    private class Store(
        initial: Map<String, String> = emptyMap(),
        var configExists: Boolean = false,
    ) {
        val memory = initial.toMutableMap()
        val disk = initial.toMutableMap()
        val calls = mutableListOf<String>()

        fun load(): Preferences {
            val existing = memory.isNotEmpty() || configExists
            return Preferences(
                theme = ThemePolicy.resolve(memory["theme"], existing),
                connectionMode = ModePolicy.initial(memory["connectionMode"], existing),
            )
        }

        fun save(preferencesCommitSucceeds: Boolean = true, configFailure: Exception? = null) {
            ConfigurationDefaults.commit(load(), persistDefaults = { choices ->
                calls += "preferences"
                memory.putAll(choices)
                // SharedPreferences updates memory even if commit reports failure.
                check(preferencesCommitSucceeds) { "Preferences commit failed" }
                disk.clear()
                disk.putAll(memory)
            }) {
                calls += "config"
                if (configFailure != null) throw configFailure
                configExists = true
            }
        }

        fun restart() {
            memory.clear()
            memory.putAll(disk)
        }
    }

    @Test fun firstConfigPinsFreshDefaultsBeforeTheFileAndSurvivesRestart() {
        val store = Store()
        assertEquals(ThemeStyle.LIQUID, store.load().theme)
        assertEquals(ConnectionMode.VPN, store.load().connectionMode)
        assertTrue(store.calls.isEmpty())
        assertTrue(store.disk.isEmpty())

        store.save()

        assertEquals(listOf("preferences", "config"), store.calls)
        assertTrue(store.configExists)
        store.restart()
        assertEquals(ThemeStyle.LIQUID, store.load().theme)
        assertEquals(ConnectionMode.VPN, store.load().connectionMode)
    }

    @Test fun legacyConfigWithoutPreferencesKeepsConsoleAndRoot() {
        val store = Store(configExists = true)
        store.save()
        store.restart()
        assertEquals(ThemeStyle.CONSOLE, store.load().theme)
        assertEquals(ConnectionMode.ROOT, store.load().connectionMode)
    }

    @Test fun legacyPreferencesWithoutConfigKeepConsoleAndRoot() {
        val store = Store(mapOf("boot" to "true"))
        store.save()
        store.restart()
        assertEquals(ThemeStyle.CONSOLE, store.load().theme)
        assertEquals(ConnectionMode.ROOT, store.load().connectionMode)
        assertEquals("true", store.disk["boot"])
    }

    @Test fun everyExistingChoiceAndUnrelatedPreferenceIsPreserved() {
        ThemeStyle.entries.forEach { theme ->
            ConnectionMode.entries.forEach { mode ->
                val original = mapOf(
                    "theme" to theme.name,
                    "connectionMode" to mode.name,
                    "homes" to "[{\"id\":\"fixture-home\"}]",
                    "requested" to "false",
                    "accent" to "blue",
                    "interval" to "47",
                )
                val store = Store(original, configExists = true)
                store.save()
                store.restart()
                assertEquals(original, store.disk)
                assertEquals(theme, store.load().theme)
                assertEquals(mode, store.load().connectionMode)
            }
        }
    }

    @Test fun failedCommitAbortsConfigAndRetryStillPersistsInMemoryChoices() {
        val store = Store()
        assertThrows(IllegalStateException::class.java) { store.save(preferencesCommitSucceeds = false) }
        assertFalse(store.configExists)
        assertTrue(store.disk.isEmpty())
        assertEquals("LIQUID", store.memory["theme"])
        assertEquals("VPN", store.memory["connectionMode"])

        store.save()

        assertEquals(listOf("preferences", "preferences", "config"), store.calls)
        store.restart()
        assertEquals(ThemeStyle.LIQUID, store.load().theme)
        assertEquals(ConnectionMode.VPN, store.load().connectionMode)
    }

    @Test fun configFailurePropagatesWithoutLosingPinnedChoices() {
        val store = Store()
        val failure = IOException("Config write failed")
        val thrown = assertThrows(IOException::class.java) { store.save(configFailure = failure) }
        assertSame(failure, thrown)
        assertFalse(store.configExists)
        assertEquals(listOf("preferences", "config"), store.calls)
        store.restart()
        assertEquals(ThemeStyle.LIQUID, store.load().theme)
        assertEquals(ConnectionMode.VPN, store.load().connectionMode)
    }

    @Test fun unknownValuesPinCurrentFallbacksWithoutOverwritingOtherKeys() {
        val store = Store(mapOf(
            "theme" to "UNRECOGNIZED",
            "connectionMode" to "UNRECOGNIZED",
            "requested" to "false",
        ))
        store.save()
        store.restart()
        assertEquals(mapOf(
            "theme" to "CONSOLE",
            "connectionMode" to "ROOT",
            "requested" to "false",
        ), store.disk)
    }
}
