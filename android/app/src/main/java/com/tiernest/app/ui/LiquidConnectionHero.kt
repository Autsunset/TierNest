package com.tiernest.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tiernest.app.Dashboard
import com.tiernest.app.data.Preferences

@Composable
internal fun LiquidConnectionHero(state: Dashboard, prefs: Preferences, onConnect: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    LiquidSurface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(32.dp), prominent = true) {
        Column(Modifier.fillMaxWidth().padding(22.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(7.dp).background(
                    if (state.active) colors.primary else colors.onSurfaceVariant, CircleShape))
                Text("连接状态", Modifier.weight(1f), style = MaterialTheme.typography.labelLarge,
                    color = colors.onSurfaceVariant)
                Text(prefs.connectionMode.label, style = MaterialTheme.typography.labelMedium,
                    color = colors.primary, modifier = Modifier.background(
                        colors.primary.copy(alpha = 0.09f), CircleShape).padding(horizontal = 12.dp, vertical = 6.dp))
            }
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val showArtwork = maxWidth >= 260.dp && LocalDensity.current.fontScale < 1.4f
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(state.phase, style = MaterialTheme.typography.headlineLarge)
                        Text(state.detail, style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                    }
                    if (showArtwork) ConnectionArtwork(state.active, Modifier.size(84.dp))
                }
            }
            if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Button(onClick = onConnect, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                shape = CircleShape, contentPadding = PaddingValues(horizontal = 20.dp, vertical = 14.dp)) {
                Icon(if (prefs.requested) Icons.Rounded.Stop else Icons.Rounded.PlayArrow, null)
                Spacer(Modifier.width(8.dp))
                Text(when {
                    prefs.requested -> "断开并停止"
                    state.error.isNotBlank() -> "重新连接"
                    else -> "连接网络"
                }, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            }
        }
    }
}

// Decorative topology, not a claim about the current peer count or routes.
@Composable
private fun ConnectionArtwork(active: Boolean, modifier: Modifier) {
    val colors = MaterialTheme.colorScheme
    val dark = LocalAppearance.current.dark
    Canvas(modifier) {
        val center = Offset(size.width * 0.5f, size.height * 0.5f)
        val radius = size.minDimension * 0.37f
        drawCircle(Brush.radialGradient(listOf(colors.primary.copy(alpha = 0.13f), Color.Transparent),
            center, size.minDimension * 0.5f), size.minDimension * 0.5f, center)
        drawCircle(colors.primary.copy(alpha = 0.17f), radius, center, style = Stroke(1.dp.toPx()))
        drawCircle(Color.White.copy(alpha = if (dark) 0.18f else 0.8f),
            radius - 2.dp.toPx(), center, style = Stroke(1.dp.toPx()))
        val nodes = listOf(
            Offset(size.width * 0.5f, size.height * 0.13f),
            Offset(size.width * 0.18f, size.height * 0.69f),
            Offset(size.width * 0.82f, size.height * 0.69f))
        nodes.forEach { node ->
            drawLine(colors.primary.copy(alpha = if (active) 0.6f else 0.22f),
                center, node, 1.5.dp.toPx(), StrokeCap.Round)
            drawCircle(colors.surface, 7.dp.toPx(), node)
            drawCircle(colors.primary.copy(alpha = if (active) 0.85f else 0.45f), 3.dp.toPx(), node)
        }
        drawCircle(Brush.linearGradient(listOf(colors.surface, colors.primaryContainer)),
            15.dp.toPx(), center)
        drawCircle(Color.White.copy(alpha = if (dark) 0.4f else 0.95f),
            15.dp.toPx(), center, style = Stroke(1.dp.toPx()))
        drawCircle(colors.primary, 5.dp.toPx(), center)
    }
}
