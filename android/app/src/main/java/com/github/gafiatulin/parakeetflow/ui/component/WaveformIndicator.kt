package com.github.gafiatulin.parakeetflow.ui.component

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun WaveformIndicator(
    isActive: Boolean,
    color: Color,
    modifier: Modifier = Modifier,
    barCount: Int = 5
) {
    val infiniteTransition = rememberInfiniteTransition(label = "waveform")
    val animations = (0 until barCount).map { index ->
        infiniteTransition.animateFloat(
            initialValue = 0.3f,
            targetValue = 1.0f,
            animationSpec = infiniteRepeatable(
                animation = tween(
                    durationMillis = 600,
                    delayMillis = index * 100,
                    easing = FastOutSlowInEasing
                ),
                repeatMode = RepeatMode.Reverse
            ),
            label = "bar_$index"
        )
    }

    Canvas(modifier = modifier.size(width = (barCount * 8).dp, height = 24.dp)) {
        val barWidth = size.width / (barCount * 2f)
        val maxHeight = size.height

        for (i in 0 until barCount) {
            val heightFraction = if (isActive) animations[i].value else 0.3f
            val barHeight = maxHeight * heightFraction
            val x = i * barWidth * 2 + barWidth / 2
            val y = (maxHeight - barHeight) / 2

            drawRect(
                color = color,
                topLeft = Offset(x, y),
                size = Size(barWidth, barHeight)
            )
        }
    }
}
