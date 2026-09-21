package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class ModuleImportCommitTest {
    private val oldToml = "# Existing synthetic config\r\ninstance_name = \"tiernest-old\"\r\ndhcp = true\r\n"
    private val newToml = "# Imported synthetic config\r\ninstance_name = \"tiernest-imported\"\r\ndhcp = false\r\n"

    private val basePrefs = Preferences(
        theme = ThemeStyle.HYPER,
        colors = ColorMode.DARK,
        dynamicColor = false,
        requested = false,
        boot = true,
        screenSuspend = true,
        automatic = false,
        detection = DetectionMode.EVENT,
        interval = 30,
        homes = emptyList(),
        migrationReview = "",
        accent = "coral",
        reduceMotion = true,
        connectionMode = ConnectionMode.ROOT,
        hotspotAccess = true,
    )

    private val importedPrefs = basePrefs.copy(
        requested = false,
        automatic = true,
        detection = DetectionMode.HTTP,
        interval = 45,
        homes = listOf(HomeNetwork("wlan0", "192.168.1.1", "00:11:22:33:44:55", "10.77.0.1", 80)),
        migrationReview = "已备份原模块配置，请核对迁移项。",
    )

    @Test fun successfulCommitExecutesPreferencesThenConfigAndPreservesUnrelatedSettings() {
        var currentConfig = oldToml
        var currentPrefs = basePrefs
        val callLog = mutableListOf<String>()
        val snapshots = mutableListOf<Pair<String, String>>()

        fun record() = snapshots.add(currentConfig to currentPrefs.migrationReview)
        record()

        val committed = ModuleImportCommit.commit(
            oldConfig = oldToml,
            newConfig = newToml,
            oldPrefs = basePrefs,
            newPrefs = importedPrefs,
            writeConfig = { config ->
                callLog.add("writeConfig")
                currentConfig = config
                record()
            },
            writePrefs = { change ->
                callLog.add("writePrefs")
                currentPrefs = change(currentPrefs)
                record()
                currentPrefs
            },
        )

        assertEquals(listOf("writePrefs", "writeConfig"), callLog)
        assertEquals(newToml, currentConfig)
        assertEquals(importedPrefs.migrationReview, currentPrefs.migrationReview)
        assertTrue(currentPrefs.automatic)
        assertEquals(DetectionMode.HTTP, currentPrefs.detection)
        assertEquals(45, currentPrefs.interval)
        assertEquals(1, currentPrefs.homes.size)
        assertFalse(currentPrefs.requested)

        // Verify unrelated preferences are preserved from current
        assertEquals(ThemeStyle.HYPER, committed.theme)
        assertEquals(ColorMode.DARK, committed.colors)
        assertEquals("coral", committed.accent)
        assertTrue(committed.boot)
        assertTrue(committed.screenSuspend)
        assertTrue(committed.hotspotAccess)
        assertTrue(committed.reduceMotion)

        // Verify that no intermediate state had newConfig with empty review
        assertTrue(snapshots.none { (config, review) -> config == newToml && review.isBlank() })
    }

    @Test fun initialPreferencesFailureDoesNotTouchConfig() {
        var currentConfig = oldToml
        val callLog = mutableListOf<String>()

        val error = assertThrows(IllegalStateException::class.java) {
            ModuleImportCommit.commit(
                oldConfig = oldToml,
                newConfig = newToml,
                oldPrefs = basePrefs,
                newPrefs = importedPrefs,
                writeConfig = { config ->
                    callLog.add("writeConfig")
                    currentConfig = config
                },
                writePrefs = {
                    callLog.add("writePrefs")
                    throw IllegalStateException("SharedPreferences commit failed")
                },
            )
        }

        assertEquals("SharedPreferences commit failed", error.message)
        assertEquals(listOf("writePrefs"), callLog)
        assertEquals(oldToml, currentConfig)
    }

    @Test fun configWriteFailureRollsBackConfigAndPreferencesKeepingRequestedFalse() {
        var currentConfig = oldToml
        // Even if oldPrefs had requested=true, rollback MUST force requested=false
        val runningOldPrefs = basePrefs.copy(requested = true)
        var currentPrefs = runningOldPrefs
        val callLog = mutableListOf<String>()

        val error = assertThrows(IOException::class.java) {
            ModuleImportCommit.commit(
                oldConfig = oldToml,
                newConfig = newToml,
                oldPrefs = runningOldPrefs,
                newPrefs = importedPrefs,
                writeConfig = { config ->
                    callLog.add("writeConfig:$config")
                    if (config == newToml) throw IOException("Config disk write failed")
                    currentConfig = config
                },
                writePrefs = { change ->
                    callLog.add("writePrefs")
                    currentPrefs = change(currentPrefs)
                    currentPrefs
                },
            )
        }

        assertEquals("Config disk write failed", error.message)
        assertEquals(listOf("writePrefs", "writeConfig:$newToml", "writeConfig:$oldToml", "writePrefs"), callLog)
        assertEquals(oldToml, currentConfig)
        assertEquals("", currentPrefs.migrationReview)
        assertFalse(currentPrefs.automatic)
        assertEquals(0, currentPrefs.homes.size)
        // Strictly verify that requested did not roll back to true
        assertFalse(currentPrefs.requested)
    }

    @Test fun configRollbackFailureRetainsMigrationGatekeeperAndSuppressesError() {
        var currentPrefs = basePrefs
        val callLog = mutableListOf<String>()

        val error = assertThrows(IOException::class.java) {
            ModuleImportCommit.commit(
                oldConfig = oldToml,
                newConfig = newToml,
                oldPrefs = basePrefs,
                newPrefs = importedPrefs,
                writeConfig = { config ->
                    callLog.add("writeConfig:$config")
                    if (config == newToml) throw IOException("Primary write failed")
                    throw IOException("Rollback write failed")
                },
                writePrefs = { change ->
                    callLog.add("writePrefs")
                    currentPrefs = change(currentPrefs)
                    currentPrefs
                },
            )
        }

        assertEquals("Primary write failed", error.message)
        assertEquals(listOf("writePrefs", "writeConfig:$newToml", "writeConfig:$oldToml"), callLog)
        // Preferences rollback must NOT have been called
        assertEquals(importedPrefs.migrationReview, currentPrefs.migrationReview)
        assertFalse(currentPrefs.requested)
        // Secondary rollback exception must be added as suppressed
        assertEquals(1, error.suppressed.size)
        assertEquals("Rollback write failed", error.suppressed[0].message)
    }

    @Test fun failureAfterConfigReplacementRestoresBytesAndKeepsLatestUnrelatedChoice() {
        var config = oldToml
        var prefs = basePrefs
        val failure = IOException("Verification failed after replacement")
        val states = mutableListOf<Pair<String, Preferences>>()
        val error = assertThrows(IOException::class.java) {
            ModuleImportCommit.commit(oldToml, newToml, basePrefs, importedPrefs,
                writeConfig = { text ->
                    config = text
                    states.add(config to prefs)
                    if (text == newToml) {
                        // Another explicit choice while the file operation ran.
                        prefs = prefs.copy(theme = ThemeStyle.MATERIAL, hotspotAccess = false)
                        throw failure
                    }
                },
                writePrefs = { change ->
                    prefs = change(prefs)
                    states.add(config to prefs)
                    prefs
                })
        }
        assertSame(failure, error)
        assertEquals(oldToml, config)
        assertEquals(ThemeStyle.MATERIAL, prefs.theme)
        assertFalse(prefs.hotspotAccess)
        assertFalse(prefs.requested)
        assertTrue(states.none { (text, state) -> text == newToml && state.migrationReview.isBlank() })
    }

    @Test fun preferencesRollbackFailureSuppressesErrorAndKeepsConfigRestored() {
        var currentConfig = oldToml
        var currentPrefs = basePrefs
        var prefsWriteCount = 0

        val error = assertThrows(IOException::class.java) {
            ModuleImportCommit.commit(
                oldConfig = oldToml,
                newConfig = newToml,
                oldPrefs = basePrefs,
                newPrefs = importedPrefs,
                writeConfig = { config ->
                    if (config == newToml) throw IOException("Config write failed")
                    currentConfig = config
                },
                writePrefs = { change ->
                    prefsWriteCount++
                    if (prefsWriteCount > 1) throw IllegalStateException("Prefs rollback commit failed")
                    currentPrefs = change(currentPrefs)
                    currentPrefs
                },
            )
        }

        assertEquals("Config write failed", error.message)
        assertEquals(oldToml, currentConfig)
        assertEquals(1, error.suppressed.size)
        assertEquals("Prefs rollback commit failed", error.suppressed[0].message)
    }

    @Test fun validationRejectsBlankReviewOrRequestedTrue() {
        assertThrows(IllegalArgumentException::class.java) {
            ModuleImportCommit.commit(
                oldConfig = oldToml, newConfig = newToml, oldPrefs = basePrefs,
                newPrefs = importedPrefs.copy(migrationReview = "   "),
                writeConfig = {}, writePrefs = { it(basePrefs) },
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            ModuleImportCommit.commit(
                oldConfig = oldToml, newConfig = newToml, oldPrefs = basePrefs,
                newPrefs = importedPrefs.copy(requested = true),
                writeConfig = {}, writePrefs = { it(basePrefs) },
            )
        }
    }

    @Test fun exactTomlBytesWithCommentsAndCrlfPreserved() {
        val verbatimOld = "# Section 1\r\n[network_identity]\r\nnetwork_name = \"alpha\"\r\n"
        val verbatimNew = "# Section 2\r\n# Extra comment\r\n[network_identity]\r\nnetwork_name = \"beta\"\r\n"
        var written = ""

        ModuleImportCommit.commit(
            oldConfig = verbatimOld,
            newConfig = verbatimNew,
            oldPrefs = basePrefs,
            newPrefs = importedPrefs,
            writeConfig = { written = it },
            writePrefs = { it(basePrefs) },
        )

        assertEquals(verbatimNew, written)
        assertTrue(written.contains("\r\n"))
        assertTrue(written.startsWith("# Section 2\r\n# Extra comment\r\n"))
    }
}
