package com.github.gafiatulin.parakeetflow

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.github.gafiatulin.parakeetflow.ui.screen.*
import com.github.gafiatulin.parakeetflow.ui.theme.ParakeetFlowTheme
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collectLatest

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private val navigationEvents = MutableSharedFlow<String>(extraBufferCapacity = 1)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNavigationIntent(intent)
        enableEdgeToEdge()
        setContent {
            ParakeetFlowTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val navController = rememberNavController()

                    LaunchedEffect(Unit) {
                        navigationEvents.collectLatest { destination ->
                            navController.navigate(destination) {
                                launchSingleTop = true
                            }
                        }
                    }

                    NavHost(navController = navController, startDestination = "settings") {
                        composable("settings") {
                            SettingsScreen(
                                onNavigateToHistory = { navController.navigate("history") },
                                onNavigateToPermissions = { navController.navigate("permissions") },
                                onNavigateToOnboarding = { navController.navigate("onboarding") }
                            )
                        }
                        composable("history") {
                            HistoryScreen(onBack = { navController.popBackStack() })
                        }
                        composable("permissions") {
                            PermissionsScreen(onBack = { navController.popBackStack() })
                        }
                        composable("onboarding") {
                            OnboardingScreen(
                                onComplete = { navController.popBackStack() }
                            )
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNavigationIntent(intent)
    }

    private fun handleNavigationIntent(intent: Intent?) {
        val destination = intent?.getStringExtra("navigate_to") ?: return
        navigationEvents.tryEmit(destination)
    }
}
