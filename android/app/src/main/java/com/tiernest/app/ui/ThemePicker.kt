package com.tiernest.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tiernest.app.data.ThemeStyle

@Composable fun ThemePicker(selected: ThemeStyle, onSelect: (ThemeStyle) -> Unit) {
    Column(Modifier.fillMaxWidth().selectableGroup(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ThemeOption(ThemeStyle.LIQUID, "通透玻璃、柔和光影与悬浮导航",
            selected == ThemeStyle.LIQUID, { onSelect(ThemeStyle.LIQUID) }, prominent = true)
        Text("经典主题 · 随时切换", color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(start = 6.dp, top = 6.dp))
        ThemeOption(ThemeStyle.CONSOLE, "原版控制台与静态光晕",
            selected == ThemeStyle.CONSOLE, { onSelect(ThemeStyle.CONSOLE) })
        ThemeOption(ThemeStyle.MATERIAL, "经典 Material 组件与壁纸取色",
            selected == ThemeStyle.MATERIAL, { onSelect(ThemeStyle.MATERIAL) })
        ThemeOption(ThemeStyle.HYPER, "原版 Miuix 组件与圆角卡片",
            selected == ThemeStyle.HYPER, { onSelect(ThemeStyle.HYPER) })
    }
}

@Composable private fun ThemeOption(
    theme: ThemeStyle,
    description: String,
    selected: Boolean,
    onSelect: () -> Unit,
    prominent: Boolean = false,
) {
    val colors = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(if (prominent) 26.dp else 20.dp)
    Column(Modifier.fillMaxWidth().clip(shape)
        .background(if (selected) colors.primary.copy(alpha = 0.07f) else colors.surfaceContainerLow)
        .border(if (selected) 1.5.dp else 1.dp,
            if (selected) colors.primary.copy(alpha = 0.7f) else colors.outlineVariant.copy(alpha = 0.6f), shape)
        .selectable(selected = selected, role = Role.RadioButton, onClick = onSelect)
        .padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (prominent) ThemePreview(theme, Modifier.fillMaxWidth().height(112.dp))
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!prominent) ThemePreview(theme, Modifier.size(58.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (prominent) Text("LIQUID GLASS", color = colors.primary,
                    style = MaterialTheme.typography.labelSmall, letterSpacing = 1.4.sp)
                Text(styleName(theme), style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (selected || prominent) FontWeight.SemiBold else FontWeight.Medium)
                Text(description, style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
            }
            RadioButton(selected = selected, onClick = null)
        }
    }
}

// Decorative, static swatches avoid running four renderers in the theme chooser.
@Composable private fun ThemePreview(theme: ThemeStyle, modifier: Modifier) {
    val dark = LocalAppearance.current.dark
    val accent = when (theme) {
        ThemeStyle.LIQUID -> if (dark) Color(0xFF8FDACB) else Color(0xFF3B867C)
        ThemeStyle.CONSOLE -> if (dark) Color(0xFF76D9B0) else Color(0xFF147453)
        ThemeStyle.MATERIAL, ThemeStyle.HYPER -> Color(0xFF3977E8)
    }
    val background = if (dark) Color(0xFF172632) else Color(0xFFE9EFF2)
    val panel = if (dark) Color(0xFF324452) else Color.White
    val line = if (dark) Color(0xFFBBCAD3) else Color(0xFF82949E)
    Canvas(modifier.clip(RoundedCornerShape(if (theme == ThemeStyle.LIQUID) 18.dp else 14.dp))) {
        val w = size.width
        val h = size.height
        drawRect(background)
        when (theme) {
            ThemeStyle.LIQUID -> {
                drawRect(Brush.linearGradient(listOf(
                    if (dark) Color(0xFF183B43) else Color(0xFFC8E2DD),
                    if (dark) Color(0xFF304452) else Color(0xFFE6E3D9),
                )))
                drawCircle(Brush.radialGradient(listOf(accent.copy(alpha = 0.46f), Color.Transparent),
                    center = Offset(w * 0.2f, h * 0.2f), radius = w * 0.6f), w * 0.6f, Offset(w * 0.2f, h * 0.2f))
                val topLeft = Offset(w * 0.12f, h * 0.15f)
                val cardSize = Size(w * 0.76f, h * 0.7f)
                val corner = CornerRadius(20.dp.toPx())
                drawRoundRect(Brush.linearGradient(listOf(panel.copy(alpha = 0.8f), panel.copy(alpha = 0.45f))),
                    topLeft, cardSize, corner)
                drawRoundRect(Color.White.copy(alpha = if (dark) 0.34f else 0.9f),
                    topLeft, cardSize, corner, style = Stroke(1.dp.toPx()))
                drawCircle(accent.copy(alpha = 0.24f), h * 0.16f, Offset(w * 0.25f, h * 0.5f))
                drawCircle(accent, h * 0.055f, Offset(w * 0.25f, h * 0.5f))
                drawRoundRect(line.copy(alpha = 0.65f), Offset(w * 0.38f, h * 0.33f),
                    Size(w * 0.26f, h * 0.065f), CornerRadius(h * 0.04f))
                drawRoundRect(line.copy(alpha = 0.32f), Offset(w * 0.38f, h * 0.46f),
                    Size(w * 0.35f, h * 0.045f), CornerRadius(h * 0.04f))
                drawRoundRect(accent.copy(alpha = 0.28f), Offset(w * 0.38f, h * 0.61f),
                    Size(w * 0.2f, h * 0.1f), CornerRadius(h * 0.08f))
            }
            ThemeStyle.CONSOLE -> {
                drawCircle(accent.copy(alpha = 0.16f), w * 0.7f, Offset(w * 0.95f, 0f))
                drawRoundRect(panel.copy(alpha = 0.85f), Offset(w * 0.14f, h * 0.16f),
                    Size(w * 0.72f, h * 0.52f), CornerRadius(w * 0.13f))
                drawRoundRect(accent.copy(alpha = 0.55f), Offset(w * 0.25f, h * 0.31f),
                    Size(w * 0.5f, h * 0.08f), CornerRadius(w * 0.04f))
                drawRoundRect(line.copy(alpha = 0.35f), Offset(w * 0.25f, h * 0.47f),
                    Size(w * 0.35f, h * 0.05f), CornerRadius(w * 0.04f))
                drawRoundRect(panel, Offset(w * 0.14f, h * 0.75f),
                    Size(w * 0.72f, h * 0.13f), CornerRadius(w * 0.1f))
            }
            ThemeStyle.MATERIAL -> {
                drawRoundRect(accent.copy(alpha = 0.22f), Offset(w * 0.12f, h * 0.12f),
                    Size(w * 0.76f, h * 0.43f), CornerRadius(w * 0.16f))
                drawCircle(accent, w * 0.1f, Offset(w * 0.34f, h * 0.34f))
                drawRoundRect(panel, Offset(w * 0.12f, h * 0.63f),
                    Size(w * 0.34f, h * 0.24f), CornerRadius(w * 0.1f))
                drawRoundRect(panel, Offset(w * 0.54f, h * 0.63f),
                    Size(w * 0.34f, h * 0.24f), CornerRadius(w * 0.1f))
            }
            ThemeStyle.HYPER -> {
                repeat(3) { row ->
                    val y = h * (0.12f + row * 0.27f)
                    drawRoundRect(panel, Offset(w * 0.12f, y),
                        Size(w * 0.76f, h * 0.22f), CornerRadius(w * 0.09f))
                    drawCircle(accent.copy(alpha = if (row == 0) 0.9f else 0.3f),
                        w * 0.055f, Offset(w * 0.26f, y + h * 0.11f))
                    drawRoundRect(line.copy(alpha = 0.45f), Offset(w * 0.4f, y + h * 0.085f),
                        Size(w * 0.3f, h * 0.05f), CornerRadius(w * 0.025f))
                }
            }
        }
    }
}
