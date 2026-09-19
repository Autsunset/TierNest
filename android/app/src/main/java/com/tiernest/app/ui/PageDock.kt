package com.tiernest.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable fun PageDock(pager: PagerState, onSelect: (Int) -> Unit) {
    val appearance = LocalAppearance.current
    val colors = MaterialTheme.colorScheme
    val items = listOf("概览" to Icons.Rounded.Dashboard, "节点" to Icons.Rounded.Hub,
        "组网" to Icons.Rounded.Lan, "设置" to Icons.Rounded.Tune)
    if (appearance.hyper) {
        top.yukonga.miuix.kmp.basic.NavigationBar(
            items = items.map { top.yukonga.miuix.kmp.basic.NavigationItem(it.first, it.second) },
            selected = pager.currentPage, onClick = onSelect, showDivider = false)
        return
    }
    if (!appearance.console) {
        NavigationBar(containerColor = colors.surface) {
            items.forEachIndexed { index, (title, icon) ->
                NavigationBarItem(selected = pager.currentPage == index, onClick = { onSelect(index) },
                    icon = { Icon(icon, null) }, label = { Text(title) })
            }
        }
        return
    }
    Box(Modifier.navigationBarsPadding().padding(horizontal = 18.dp, vertical = 8.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(66.dp).clip(RoundedCornerShape(32.dp))
            .background(colors.surface.copy(alpha = 0.95f)).border(1.dp, colors.outlineVariant.copy(alpha = 0.5f), RoundedCornerShape(32.dp))) {
            val width = maxWidth / 4
            val position by animateFloatAsState(pager.currentPage.toFloat(),
                animationSpec = if (appearance.reduceMotion) snap() else spring(
                    dampingRatio = AppMotion.DOCK_DAMPING, stiffness = AppMotion.DOCK_STIFFNESS), label = "dock-position")
            Box(Modifier.width(width).fillMaxHeight().graphicsLayer {
                // The spring retargets from its current position/velocity. Reading
                // it here avoids recomposing or measuring the page on each frame.
                translationX = position * size.width
            }.padding(5.dp).clip(RoundedCornerShape(28.dp)).background(colors.surfaceContainerHigh)
                .border(1.dp, colors.outlineVariant.copy(alpha = 0.55f), RoundedCornerShape(28.dp)))
            Row(Modifier.fillMaxSize().selectableGroup()) {
                items.forEachIndexed { index, (title, icon) ->
                    val selected = pager.currentPage == index
                    val color by animateColorAsState(if (selected) colors.primary else colors.onSurfaceVariant,
                        tween(if (appearance.reduceMotion) AppMotion.FADE_MS else AppMotion.DOCK_COLOR_MS, easing = AppMotion.dockEase), label = "dock-color")
                    Column(Modifier.weight(1f).fillMaxHeight().selectable(selected, role = Role.Tab,
                        interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = { onSelect(index) }),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Icon(icon, null, tint = color, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.height(3.dp))
                        Text(title, color = color, style = MaterialTheme.typography.labelSmall, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal)
                    }
                }
            }
        }
    }
}
