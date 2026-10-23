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
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tiernest.app.data.*

data class Appearance(val console: Boolean = false, val dark: Boolean = false, val reduceMotion: Boolean = false,
    val hyper: Boolean = false, val liquid: Boolean = false)
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
    val liquid = prefs.theme == ThemeStyle.LIQUID
    val accent = accents.firstOrNull { it.id == prefs.accent } ?: accents.first()
    val reduced = prefs.reduceMotion || !android.animation.ValueAnimator.areAnimatorsEnabled()
    val targetColors = when {
        liquid && dark -> darkColorScheme(
            primary = accent.dark, onPrimary = Color(0xFF082C24),
            primaryContainer = lerp(Color(0xFF182831), accent.dark, 0.14f), onPrimaryContainer = accent.dark,
            secondary = Color(0xFF9DCEDE), onSecondary = Color(0xFF10343F),
            secondaryContainer = Color(0xFF223D48), onSecondaryContainer = Color(0xFFC6EAF4),
            tertiary = Color(0xFFF0C49A), onTertiary = Color(0xFF402C17),
            background = Color(0xFF101D26), onBackground = Color(0xFFECF5F6),
            surface = Color(0xFF1C2D37), onSurface = Color(0xFFECF5F6),
            surfaceContainerLowest = Color(0xFF111F29), surfaceContainerLow = Color(0xFF21343D),
            surfaceContainer = Color(0xFF2A3E47), surfaceContainerHigh = Color(0xFF344C55),
            surfaceContainerHighest = Color(0xFF415B64), onSurfaceVariant = Color(0xFFB5CBD0),
            outline = Color(0xFF809DA5), outlineVariant = Color(0xFF49616B))
        liquid -> lightColorScheme(
            primary = accent.light, onPrimary = Color.White,
            primaryContainer = lerp(Color(0xFFE9F1F2), accent.light, 0.12f), onPrimaryContainer = accent.light,
            secondary = Color(0xFF3C6C80), onSecondary = Color.White,
            secondaryContainer = Color(0xFFD6EAF2), onSecondaryContainer = Color(0xFF163E4E),
            tertiary = Color(0xFF87552B), onTertiary = Color.White,
            background = Color(0xFFE9F1F2), onBackground = Color(0xFF192E37),
            surface = Color(0xFFF5FAFA), onSurface = Color(0xFF192E37),
            surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF2F8F8),
            surfaceContainer = Color(0xFFE1ECEE), surfaceContainerHigh = Color(0xFFD3E4E7),
            surfaceContainerHighest = Color(0xFFC5DADD), onSurfaceVariant = Color(0xFF49636C),
            outline = Color(0xFF6D8991), outlineVariant = Color(0xFFB3CBCF))
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
    val colorSpec = if (console || liquid) tween<Color>(if (reduced) AppMotion.FADE_MS else AppMotion.DOCK_COLOR_MS,
        easing = AppMotion.dockEase) else snap<Color>()
    val primary by animateColorAsState(targetColors.primary, colorSpec, label = "theme-primary")
    val onPrimary by animateColorAsState(targetColors.onPrimary, colorSpec, label = "theme-on-primary")
    val primaryContainer by animateColorAsState(targetColors.primaryContainer, colorSpec, label = "theme-primary-container")
    val onPrimaryContainer by animateColorAsState(targetColors.onPrimaryContainer, colorSpec, label = "theme-on-primary-container")
    val colors = targetColors.copy(primary = primary, onPrimary = onPrimary,
        primaryContainer = primaryContainer, onPrimaryContainer = onPrimaryContainer)
    val typography = if (liquid) Typography().let { base ->
        base.copy(
            headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.8).sp),
            headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.6).sp),
            titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.3).sp),
            bodyMedium = base.bodyMedium.copy(lineHeight = 22.sp),
            labelSmall = base.labelSmall.copy(letterSpacing = 0.4.sp))
    } else Typography()
    top.yukonga.miuix.kmp.theme.MiuixTheme(colors = miuixColors) {
    CompositionLocalProvider(LocalAppearance provides Appearance(console, dark,
        reduced, hyper, liquid)) {
    MaterialTheme(colorScheme = colors,
        typography = typography,
        shapes = Shapes(medium = RoundedCornerShape(if (hyper || liquid) 22.dp else 16.dp),
            large = RoundedCornerShape(if (hyper || liquid) 28.dp else 24.dp), extraLarge = RoundedCornerShape(32.dp)),
        content = content)
    }
    }
}
