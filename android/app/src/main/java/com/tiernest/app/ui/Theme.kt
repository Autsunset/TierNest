package com.tiernest.app.ui

import android.os.Build
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.tiernest.app.data.*

data class Appearance(val console: Boolean = false, val dark: Boolean = false, val reduceMotion: Boolean = false, val hyper: Boolean = false)
val LocalAppearance = staticCompositionLocalOf { Appearance() }
data class Accent(val id: String, val label: String, val light: Color, val dark: Color)
val accents = listOf(
    Accent("mint", "薄荷", Color(0xFF147453), Color(0xFF76D9B0)),
    Accent("blue", "晴空", Color(0xFF286898), Color(0xFF8EC8FF)),
    Accent("purple", "香芋", Color(0xFF7052A5), Color(0xFFC4AFF0)),
    Accent("orange", "暖杏", Color(0xFF985921), Color(0xFFEABD8C)),
)

@Composable fun TierNestTheme(prefs: Preferences, content: @Composable () -> Unit) {
    val dark = when (prefs.colors) { ColorMode.SYSTEM -> isSystemInDarkTheme(); ColorMode.DARK -> true; ColorMode.LIGHT -> false }
    val hyper = prefs.theme == ThemeStyle.HYPER
    val miuixColors = if (dark) top.yukonga.miuix.kmp.theme.darkColorScheme() else top.yukonga.miuix.kmp.theme.lightColorScheme()
    val console = prefs.theme == ThemeStyle.CONSOLE
    val accent = accents.firstOrNull { it.id == prefs.accent } ?: accents.first()
    val reduced = prefs.reduceMotion || !android.animation.ValueAnimator.areAnimatorsEnabled()
    val targetColors = when {
        hyper -> (if (dark) darkColorScheme() else lightColorScheme()).copy(
            primary = miuixColors.primary, onPrimary = miuixColors.onPrimary,
            primaryContainer = miuixColors.primaryContainer, onPrimaryContainer = miuixColors.onPrimaryContainer,
            background = miuixColors.background, onBackground = miuixColors.onBackground,
            surface = miuixColors.surface, onSurface = miuixColors.onSurface,
            surfaceContainerLow = miuixColors.surface, surfaceContainer = miuixColors.surfaceContainer,
            surfaceContainerHigh = miuixColors.surfaceContainerHigh, onSurfaceVariant = miuixColors.onSurfaceVariantSummary,
            outline = miuixColors.outline, outlineVariant = miuixColors.dividerLine)
        console && dark -> darkColorScheme(primary = accent.dark, onPrimary = Color(0xFF0C201A),
            primaryContainer = accent.dark.copy(alpha = 0.13f), onPrimaryContainer = accent.dark,
            secondary = Color(0xFF98BAD4), secondaryContainer = Color(0xFF25354B),
            background = Color(0xFF0D1422), surface = Color(0xFF172131), onSurface = Color(0xFFEDF2F8),
            onSurfaceVariant = Color(0xFFA8B5C6), surfaceContainerLow = Color(0xFF192435),
            surfaceContainer = Color(0xFF202D40), surfaceContainerHigh = Color(0xFF27374C),
            outline = Color(0xFF607086), outlineVariant = Color(0xFF334357), tertiary = Color(0xFFEABD8C))
        console -> lightColorScheme(primary = accent.light, onPrimary = Color.White,
            primaryContainer = accent.light.copy(alpha = 0.10f), onPrimaryContainer = accent.light,
            secondary = Color(0xFF466378), secondaryContainer = Color(0xFFDCE8EF),
            background = Color(0xFFF0F3F6), surface = Color(0xFFFAFCFF), onSurface = Color(0xFF192735),
            onSurfaceVariant = Color(0xFF59697A), surfaceContainerLow = Color.White,
            surfaceContainer = Color(0xFFE8EEF3), surfaceContainerHigh = Color(0xFFDCE5ED),
            outline = Color(0xFF6B7C8D), outlineVariant = Color(0xFFCED9E2), tertiary = Color(0xFF97592D))
        !hyper && prefs.dynamicColor && Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(LocalContext.current) else dynamicLightColorScheme(LocalContext.current)
        dark -> darkColorScheme(primary = Color(0xFFAAC7FF), onPrimary = Color(0xFF002D6E),
            primaryContainer = Color(0xFF1A3970), onPrimaryContainer = Color(0xFFD6E3FF),
            background = Color(if (hyper) 0xFF000000 else 0xFF101318), surface = Color(0xFF14171C),
            surfaceContainer = Color(0xFF1C1E23), surfaceContainerLow = Color(0xFF181B20),
            surfaceContainerHigh = Color(0xFF25282F))
        else -> lightColorScheme(primary = Color(0xFF246BFD), onPrimary = Color.White,
            primaryContainer = Color(0xFFDCE8FF), onPrimaryContainer = Color(0xFF0A2856),
            background = Color(if (hyper) 0xFFF5F5F7 else 0xFFF8F9FF), surface = Color.White,
            surfaceContainer = Color(if (hyper) 0xFFFFFFFF else 0xFFEDF1FA),
            surfaceContainerLow = Color.White, surfaceContainerHigh = Color(0xFFE7ECF6))
    }
    // One shared color transition prevents different controls from flashing at
    // different times when the accent changes. Rapid choices retarget in place.
    val colorSpec = if (console) tween<Color>(if (reduced) AppMotion.FADE_MS else AppMotion.DOCK_COLOR_MS,
        easing = AppMotion.dockEase) else snap<Color>()
    val primary by animateColorAsState(targetColors.primary, colorSpec, label = "theme-primary")
    val onPrimary by animateColorAsState(targetColors.onPrimary, colorSpec, label = "theme-on-primary")
    val primaryContainer by animateColorAsState(targetColors.primaryContainer, colorSpec, label = "theme-primary-container")
    val onPrimaryContainer by animateColorAsState(targetColors.onPrimaryContainer, colorSpec, label = "theme-on-primary-container")
    val colors = targetColors.copy(primary = primary, onPrimary = onPrimary,
        primaryContainer = primaryContainer, onPrimaryContainer = onPrimaryContainer)
    top.yukonga.miuix.kmp.theme.MiuixTheme(colors = miuixColors) {
    CompositionLocalProvider(LocalAppearance provides Appearance(console, dark,
        reduced, hyper)) {
    MaterialTheme(colorScheme = colors,
        shapes = Shapes(medium = RoundedCornerShape(if (hyper) 22.dp else 16.dp),
            large = RoundedCornerShape(if (hyper) 28.dp else 24.dp), extraLarge = RoundedCornerShape(32.dp)),
        content = content)
    }
    }
}
