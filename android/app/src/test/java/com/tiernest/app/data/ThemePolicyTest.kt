package com.tiernest.app.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ThemePolicyTest {
    @Test fun cleanInstallationDefaultsToLiquidGlass() {
        assertEquals(ThemeStyle.LIQUID, Preferences().theme)
        assertEquals(ThemeStyle.LIQUID, ThemePolicy.resolve(null, existingInstallation = false))
    }

    @Test fun olderInstallationWithoutThemeKeepsItsConsoleAppearance() {
        assertEquals(ThemeStyle.CONSOLE, ThemePolicy.resolve(null, existingInstallation = true))
        assertEquals(ThemeStyle.CONSOLE, ThemePolicy.resolve("", existingInstallation = true))
    }

    @Test fun unknownSavedThemeFallsBackWithoutOptingExistingUsersIntoGlass() {
        assertEquals(ThemeStyle.CONSOLE, ThemePolicy.resolve("UNRECOGNIZED", existingInstallation = true))
        assertEquals(ThemeStyle.LIQUID, ThemePolicy.resolve("UNRECOGNIZED", existingInstallation = false))
    }

    @Test fun originalSerializedNamesKeepTheirMeaning() {
        assertEquals(ThemeStyle.MATERIAL, ThemePolicy.resolve("MATERIAL", existingInstallation = true))
        assertEquals(ThemeStyle.HYPER, ThemePolicy.resolve("HYPER", existingInstallation = true))
        assertEquals(ThemeStyle.CONSOLE, ThemePolicy.resolve("CONSOLE", existingInstallation = true))
    }

    @Test fun savedChoiceAlwaysWinsOverInstallationDefault() {
        ThemeStyle.entries.forEach { theme ->
            assertEquals(theme, ThemePolicy.resolve(theme.name, existingInstallation = false))
            assertEquals(theme, ThemePolicy.resolve(theme.name, existingInstallation = true))
        }
    }

    @Test fun glassCanBeRestoredAfterSwitchingBackToEveryLegacyTheme() {
        var current = ThemeStyle.LIQUID
        listOf(ThemeStyle.CONSOLE, ThemeStyle.MATERIAL, ThemeStyle.HYPER, ThemeStyle.LIQUID).forEach { next ->
            current = ThemePolicy.resolve(next.name, existingInstallation = true)
            assertEquals(next, current)
        }
        assertEquals(ThemeStyle.LIQUID, current)
    }
}
