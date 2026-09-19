package com.tiernest.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** A single moving selection surface, with the same spring as the page dock. */
@Composable fun AccentPicker(selected: String, onSelect: (String) -> Unit) {
    val appearance = LocalAppearance.current
    val colors = MaterialTheme.colorScheme
    val selectedIndex = accents.indexOfFirst { it.id == selected }.coerceAtLeast(0)
    val position by animateFloatAsState(selectedIndex.toFloat(),
        if (appearance.reduceMotion) snap() else spring(
            dampingRatio = AppMotion.DOCK_DAMPING, stiffness = AppMotion.DOCK_STIFFNESS), label = "accent-position")
    BoxWithConstraints(Modifier.fillMaxWidth().height(84.dp).clip(RoundedCornerShape(24.dp))
        .background(colors.surfaceContainerLow).selectableGroup()) {
        val itemWidth = maxWidth / accents.size
        Box(Modifier.width(itemWidth).fillMaxHeight().graphicsLayer { translationX = position * size.width }
            .padding(4.dp).clip(RoundedCornerShape(20.dp)).background(colors.surfaceContainerHigh)
            .border(1.dp, colors.outlineVariant.copy(alpha = 0.6f), RoundedCornerShape(20.dp)))
        Row(Modifier.fillMaxSize()) {
            accents.forEachIndexed { index, accent ->
                val active by animateFloatAsState(if (index == selectedIndex) 1f else 0f,
                    tween(if (appearance.reduceMotion) AppMotion.FADE_MS else AppMotion.DOCK_COLOR_MS,
                        easing = AppMotion.dockEase), label = "accent-label")
                Column(Modifier.weight(1f).fillMaxHeight().selectable(index == selectedIndex, role = Role.RadioButton,
                    interactionSource = remember { MutableInteractionSource() }, indication = null,
                    onClick = { onSelect(accent.id) }), verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(30.dp).background(if (appearance.dark) accent.dark else accent.light, CircleShape))
                    Spacer(Modifier.height(6.dp))
                    Text(accent.label, color = lerp(colors.onSurfaceVariant, colors.onSurface, active),
                        style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}
