package com.tiernest.app.data

object ThemePolicy {
    fun resolve(savedName: String?, existingInstallation: Boolean): ThemeStyle =
        ThemeStyle.entries.firstOrNull { it.name == savedName }
            // A missing preference on an older installation is not a request to
            // change its appearance. Only a clean install starts in Liquid Glass.
            ?: if (existingInstallation) ThemeStyle.CONSOLE else ThemeStyle.LIQUID
}
