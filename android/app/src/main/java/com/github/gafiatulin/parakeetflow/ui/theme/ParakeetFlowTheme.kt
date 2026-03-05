package com.github.gafiatulin.parakeetflow.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = ParakeetGreen,
    secondary = ParakeetGreenLight,
    tertiary = ProcessingAmber,
    error = RecordingRed,
    surface = SurfaceDark,
    onSurface = OnSurfaceDark
)

private val LightColorScheme = lightColorScheme(
    primary = ParakeetGreen,
    secondary = ParakeetGreenDark,
    tertiary = ProcessingAmber,
    error = RecordingRed,
    surface = SurfaceLight,
    onSurface = OnSurfaceLight
)

@Composable
fun ParakeetFlowTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}
