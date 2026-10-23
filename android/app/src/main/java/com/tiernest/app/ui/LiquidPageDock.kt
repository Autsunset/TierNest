package com.tiernest.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

@Composable
internal fun LiquidPageDock(
    pager: PagerState,
    items: List<Pair<String, ImageVector>>,
    onSelect: (Int) -> Unit,
) {
    val appearance = LocalAppearance.current
    val colors = MaterialTheme.colorScheme
    val layoutDirection = LocalLayoutDirection.current
    val position = animateFloatAsState(
        targetValue = pager.currentPage.toFloat(),
        animationSpec = if (appearance.reduceMotion) snap() else spring(
            dampingRatio = AppMotion.DOCK_DAMPING,
            stiffness = AppMotion.DOCK_STIFFNESS,
        ),
        label = "liquid-dock-position",
    )
    val pillShape = RoundedCornerShape(32.dp)
    val pillFill = Brush.verticalGradient(
        listOf(
            lerp(colors.surface, Color.White, if (appearance.dark) 0.08f else 0.65f),
            lerp(colors.surface, colors.primary, 0.10f),
        ),
    )
    val pillEdge = Brush.verticalGradient(
        listOf(
            Color.White.copy(alpha = if (appearance.dark) 0.30f else 0.96f),
            colors.primary.copy(alpha = 0.16f),
        ),
    )
    Box(
        Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        LiquidSurface(
            modifier = Modifier.widthIn(max = 480.dp).fillMaxWidth(),
            shape = RoundedCornerShape(40.dp),
            prominent = true,
        ) {
            BoxWithConstraints(Modifier.fillMaxWidth().padding(6.dp)) {
                val slotWidth = maxWidth / items.size
                Box(Modifier.matchParentSize()) {
                    Box(
                        Modifier.width(slotWidth).fillMaxHeight().graphicsLayer {
                            // The slot starts at the logical edge; only the translation
                            // changes sign in RTL. Springs retain velocity on retarget.
                            val direction = if (layoutDirection == LayoutDirection.Ltr) 1f else -1f
                            translationX = position.value * size.width * direction
                        }.padding(horizontal = 2.dp)
                            .shadow(3.dp, pillShape, clip = false)
                            .background(pillFill, pillShape)
                            .border(1.dp, pillEdge, pillShape),
                    )
                }
                // Let the labels define the dock's height at large font sizes.
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).selectableGroup()) {
                    items.forEachIndexed { index, (title, icon) ->
                        val selected = pager.currentPage == index
                        val interaction = remember { MutableInteractionSource() }
                        val pressed by interaction.collectIsPressedAsState()
                        val focused by interaction.collectIsFocusedAsState()
                        val foreground = if (selected) colors.primary else colors.onSurfaceVariant
                        Column(
                            Modifier.weight(1f).heightIn(min = 64.dp).fillMaxHeight()
                                .clip(pillShape)
                                .background(if (pressed) colors.primary.copy(alpha = 0.10f) else Color.Transparent)
                                .then(if (focused) Modifier.border(2.dp, colors.primary, pillShape) else Modifier)
                                .selectable(
                                    selected = selected,
                                    role = Role.Tab,
                                    interactionSource = interaction,
                                    indication = null,
                                    onClick = { onSelect(index) },
                                )
                                .padding(horizontal = 4.dp, vertical = 8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(23.dp))
                            Spacer(Modifier.height(4.dp))
                            Text(
                                title,
                                color = foreground,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }
        }
    }
}
