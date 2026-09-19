package com.tiernest.app.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object AppMotion {
    const val PAGE_MS = 180
    const val FADE_MS = 120
    val easeOut = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
    // interstellar-proxy GlassDock's spring and color timing.
    const val DOCK_DAMPING = 0.85f
    const val DOCK_STIFFNESS = 420f
    const val DOCK_COLOR_MS = 250
    val dockEase = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f)
}

@Composable fun AmbientBackground(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val appearance = LocalAppearance.current
    Box(modifier.background(colors.background).then(if (appearance.console) Modifier.drawWithCache {
        val wash = Brush.radialGradient(listOf(colors.primary.copy(alpha = 0.12f), Color.Transparent),
            center = Offset(size.width * 0.95f, size.height * 0.12f), radius = size.width * 0.85f)
        onDrawBehind { drawRect(wash) }
    } else Modifier)) { content() }
}

// Original Compose implementation, visually inspired by interstellar-proxy's
// MIT-licensed glass panels and grouped preference rows. No blur or render loop.
@Composable fun SettingsCard(modifier: Modifier = Modifier, padding: Dp = 16.dp, content: @Composable ColumnScope.() -> Unit) {
    val colors = MaterialTheme.colorScheme
    val appearance = LocalAppearance.current
    if (appearance.hyper) {
        top.yukonga.miuix.kmp.basic.Card(modifier = modifier.fillMaxWidth(), insideMargin = PaddingValues(padding)) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
        }
        return
    }
    val shape = RoundedCornerShape(if (appearance.console) 22.dp else 24.dp)
    val fill = if (appearance.dark) listOf(Color(0xFF253246).copy(alpha = 0.8f), Color(0xFF172334).copy(alpha = 0.9f))
        else listOf(Color.White.copy(alpha = 0.94f), Color.White.copy(alpha = 0.70f))
    val shell = if (appearance.console) Modifier.background(Brush.linearGradient(fill))
        .border(1.dp, if (appearance.dark) Color.White.copy(alpha = 0.10f) else Color.White, shape)
        else Modifier.background(colors.surfaceContainerLow)
    Column(modifier.fillMaxWidth().clip(shape).then(shell).padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

@Composable fun SettingsHeader(title: String, subtitle: String = "", onBack: (() -> Unit)? = null, trailing: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回设置") }
        Column(Modifier.weight(1f)) {
            if (subtitle.isNotEmpty()) Text(subtitle, color = MaterialTheme.colorScheme.primary, fontSize = 11.sp, letterSpacing = 1.sp)
            Text(title, fontWeight = FontWeight.Bold, fontSize = 27.sp, modifier = Modifier.padding(top = 4.dp))
        }
        trailing?.invoke()
    }
}

@Composable fun GroupLabel(title: String) {
    Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge,
        modifier = Modifier.padding(start = 6.dp, top = 8.dp, bottom = 2.dp))
}

@Composable fun PreferenceRow(icon: ImageVector, title: String, summary: String, value: String = "", onClick: () -> Unit) {
    if (LocalAppearance.current.hyper) {
        top.yukonga.miuix.kmp.extra.SuperArrow(title = title, summary = summary,
            rightText = value.takeIf { it.isNotBlank() }, onClick = onClick,
            leftAction = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(end = 14.dp).size(24.dp)) })
        return
    }
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick)
        .heightIn(min = 52.dp).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.background(
            MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), RoundedCornerShape(12.dp)).padding(10.dp).size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium)
            Text(summary, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
        if (value.isNotEmpty()) Text(value, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium)
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
    }
}

@Composable fun PreferenceSwitch(title: String, summary: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).toggleable(value, role = Role.Switch, onValueChange = onChange)
        .padding(horizontal = 4.dp, vertical = 10.dp).heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, fontWeight = FontWeight.Medium)
            Text(summary, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (LocalAppearance.current.hyper) top.yukonga.miuix.kmp.basic.Switch(value, onCheckedChange = null)
        else Switch(value, onCheckedChange = null)
    }
}

@Composable fun ChoiceStrip(labels: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    if (LocalAppearance.current.hyper) {
        top.yukonga.miuix.kmp.basic.TabRow(tabs = labels, selectedTabIndex = selected, modifier = modifier, onTabSelected = onSelect)
        return
    }
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
        .padding(4.dp).selectableGroup(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        labels.forEachIndexed { index, title ->
            Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                .background(if (selected == index) MaterialTheme.colorScheme.surface else Color.Transparent)
                .selectable(selected == index, role = Role.Tab, onClick = { onSelect(index) })
                .heightIn(min = 44.dp).padding(horizontal = 5.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = if (selected == index) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (selected == index) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable fun SmallNote(text: String, error: Boolean = false) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = if (error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
}
