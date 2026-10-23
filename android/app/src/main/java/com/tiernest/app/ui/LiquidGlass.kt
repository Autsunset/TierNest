package com.tiernest.app.ui

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.dp

@Stable
private class LiquidBackdrop {
    var bounds by mutableStateOf(Rect.Zero)
}

private val LocalLiquidBackdrop = staticCompositionLocalOf<LiquidBackdrop?> { null }

/**
 * Original, stationary artwork shared by the background and glass lenses.
 * Only the artwork is refracted, never text or private screen captures. There
 * are no sensors, bitmap readbacks, frame tickers, or background workers.
 */
@Composable
fun LiquidBackground(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val backdrop = remember { LiquidBackdrop() }
    val paint = rememberLiquidPaint()
    val colors = MaterialTheme.colorScheme
    val dark = LocalAppearance.current.dark
    Box(modifier.background(colors.background).onGloballyPositioned {
        backdrop.bounds = Rect(it.positionInRoot(), Size(it.size.width.toFloat(), it.size.height.toFloat()))
    }.drawWithCache {
        val wash = Brush.radialGradient(
            listOf(colors.primary.copy(alpha = if (dark) 0.25f else 0.18f), Color.Transparent),
            center = Offset(size.width * 0.9f, size.height * 0.15f), radius = size.width)
        val pool = Brush.radialGradient(
            listOf(colors.secondary.copy(alpha = 0.15f), Color.Transparent),
            center = Offset(0f, size.height * 0.8f), radius = size.width * 1.1f)
        onDrawBehind {
            if (paint != null) {
                paint.update(size, size, Offset.Zero, 0f, 0f, dark, colors.background, colors.primary, colors.secondary)
                drawRect(paint.brush)
            } else {
                drawRect(wash)
                drawRect(pool)
                drawOval(colors.primary.copy(alpha = 0.07f),
                    topLeft = Offset(size.width * 0.25f, -size.width * 0.45f),
                    size = Size(size.width * 1.3f, size.width * 1.9f), style = Stroke(28.dp.toPx()))
            }
        }
    }) {
        CompositionLocalProvider(LocalLiquidBackdrop provides backdrop, content = content)
    }
}

@Composable
fun LiquidSurface(
    modifier: Modifier = Modifier,
    shape: RoundedCornerShape = RoundedCornerShape(28.dp),
    prominent: Boolean = false,
    content: @Composable BoxScope.() -> Unit,
) {
    val dark = LocalAppearance.current.dark
    val colors = MaterialTheme.colorScheme
    val backdrop = LocalLiquidBackdrop.current
    val paint = rememberLiquidPaint()
    var origin by remember { mutableStateOf(Offset.Zero) }
    val rim = Brush.linearGradient(listOf(
        Color.White.copy(alpha = if (dark) 0.38f else 0.95f),
        colors.secondary.copy(alpha = if (dark) 0.16f else 0.22f),
        Color.White.copy(alpha = if (dark) 0.08f else 0.36f),
        Color.White.copy(alpha = if (dark) 0.26f else 0.8f)))
    Box(modifier
        .shadow(if (prominent) 12.dp else 5.dp, shape, clip = false,
            ambientColor = colors.secondary.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.10f))
        .clip(shape)
        .onGloballyPositioned { origin = it.positionInRoot() }
        .drawWithCache {
            val fallback = Brush.linearGradient(if (dark)
                listOf(Color(0xFF2D454F).copy(alpha = 0.96f), colors.surface.copy(alpha = 0.96f))
            else listOf(Color.White.copy(alpha = 0.94f), colors.surface.copy(alpha = 0.88f)))
            val corner = shape.topStart.toPx(size, this)
            onDrawBehind {
                val bounds = backdrop?.bounds
                if (paint != null && bounds != null && !bounds.isEmpty) {
                    paint.update(size, bounds.size, origin - bounds.topLeft, corner,
                        if (prominent) 0.54f else 0.76f, dark, colors.background, colors.primary, colors.secondary)
                    drawRect(paint.brush)
                } else drawRect(fallback)
            }
        }
        .border(1.dp, rim, shape),
        content = content)
}

private interface LiquidPaint {
    val brush: Brush
    fun update(size: Size, viewport: Size, origin: Offset, radius: Float, frost: Float,
        dark: Boolean, base: Color, accent: Color, secondary: Color)
}

@Composable
private fun rememberLiquidPaint(): LiquidPaint? = remember {
    if (Build.VERSION.SDK_INT >= 33) runCatching { Api33LiquidPaint() }.getOrNull() else null
}

@RequiresApi(33)
private class Api33LiquidPaint : LiquidPaint {
    private val shader = RuntimeShader(LIQUID_SHADER)
    override val brush = ShaderBrush(shader)

    override fun update(size: Size, viewport: Size, origin: Offset, radius: Float, frost: Float,
        dark: Boolean, base: Color, accent: Color, secondary: Color) {
        shader.setFloatUniform("extent", size.width, size.height)
        shader.setFloatUniform("viewport", viewport.width.coerceAtLeast(1f), viewport.height.coerceAtLeast(1f))
        shader.setFloatUniform("origin", origin.x, origin.y)
        shader.setFloatUniform("radius", radius)
        shader.setFloatUniform("frost", frost)
        shader.setFloatUniform("night", if (dark) 1f else 0f)
        shader.setColorUniform("base", base.toArgb())
        shader.setColorUniform("accent", accent.toArgb())
        shader.setColorUniform("secondary", secondary.toArgb())
    }
}

// A rounded-rectangle lens samples the same procedural artwork in root space.
// Its fixed lighting only redraws when Compose needs a frame (scroll or input).
private const val LIQUID_SHADER = """
uniform float2 extent;
uniform float2 viewport;
uniform float2 origin;
uniform float radius;
uniform float frost;
uniform float night;
layout(color) uniform half4 base;
layout(color) uniform half4 accent;
layout(color) uniform half4 secondary;

half3 artwork(float2 coord) {
    float2 uv = coord / viewport.x;
    float2 glow = (uv - float2(0.95, 0.28)) * float2(1.4, 1.2);
    half3 c = mix(base.rgb, accent.rgb, half(exp(-dot(glow, glow) * 2.6) * 0.22));
    float2 pool = (uv - float2(-0.2, viewport.y / viewport.x * 0.82));
    c = mix(c, secondary.rgb, half(exp(-dot(pool, pool) * 1.8) * 0.18));
    float ring = abs(length((uv - float2(1.12, 0.28)) / float2(0.84, 1.18)) - 1.0);
    c = mix(c, accent.rgb, half((1.0 - smoothstep(0.0, 0.075, ring)) * 0.13));
    float rim = abs(length((uv - float2(1.12, 0.28)) / float2(0.91, 1.27)) - 1.0);
    c = mix(c, half3(1.0), half((1.0 - smoothstep(0.0, 0.004, rim)) * (0.24 - night * 0.18)));
    return c;
}

half4 main(float2 p) {
    if (frost == 0.0) return half4(artwork(p), 1.0);
    float2 halfSize = extent * 0.5;
    float r = min(radius, min(halfSize.x, halfSize.y));
    float2 centered = p - halfSize;
    float2 q = abs(centered) - halfSize + r;
    float distance = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r);
    float2 outside = max(q, 0.0);
    float2 normal = length(outside) > 0.001
        ? normalize(outside) * sign(centered)
        : (q.x > q.y ? float2(sign(centered.x), 0.0) : float2(0.0, sign(centered.y)));
    float bevel = min(halfSize.x, halfSize.y) * 0.32;
    float edge = 1.0 - smoothstep(0.0, max(bevel, 1.0), distance);
    float2 sampleAt = p + origin - normal * edge * edge * bevel * 0.48;
    half3 tint = mix(half3(1.0), base.rgb, half(night * 0.92));
    half3 c = mix(artwork(sampleAt), tint, half(frost));
    float light = max(dot(normal, normalize(float2(-0.45, -0.85))), 0.0);
    float shine = (1.0 - smoothstep(0.0, 2.4, distance)) * light;
    c = mix(c, half3(1.0), half(shine * (0.58 - night * 0.23)));
    c = mix(c, secondary.rgb, half(edge * edge * 0.045));
    return half4(c, 1.0);
}
"""
