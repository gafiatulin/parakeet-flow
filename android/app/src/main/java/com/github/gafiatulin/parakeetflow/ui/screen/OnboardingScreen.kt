package com.github.gafiatulin.parakeetflow.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

@Composable
fun OnboardingScreen(onComplete: () -> Unit) {
    val pages = listOf(
        OnboardingPage(
            Icons.Default.Mic,
            "Voice Dictation",
            "Speak naturally and ParakeetFlow transcribes your words using on-device AI."
        ),
        OnboardingPage(
            Icons.Default.AutoAwesome,
            "Smart Cleanup",
            "AI post-processing fixes grammar, removes filler words, and adds punctuation."
        ),
        OnboardingPage(
            Icons.Default.Apps,
            "Works Everywhere",
            "Dictate into any app via the floating bubble overlay."
        ),
        OnboardingPage(
            Icons.Default.Lock,
            "Fully Private",
            "All processing happens on your device. Nothing leaves your phone."
        )
    )
    val pagerState = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.weight(1f)
        ) { page ->
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    pages[page].icon,
                    contentDescription = null,
                    modifier = Modifier.size(80.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(24.dp))
                Text(
                    pages[page].title,
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    pages[page].description,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Page indicators
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(pages.size) { index ->
                    val selected = pagerState.currentPage == index
                    Surface(
                        modifier = Modifier.size(if (selected) 10.dp else 8.dp),
                        shape = MaterialTheme.shapes.small,
                        color = if (selected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.outlineVariant
                    ) {}
                }
            }

            if (pagerState.currentPage == pages.size - 1) {
                Button(onClick = onComplete) { Text("Get Started") }
            } else {
                TextButton(onClick = {
                    scope.launch {
                        pagerState.animateScrollToPage(pagerState.currentPage + 1)
                    }
                }) { Text("Next") }
            }
        }
    }
}

private data class OnboardingPage(
    val icon: ImageVector,
    val title: String,
    val description: String
)
