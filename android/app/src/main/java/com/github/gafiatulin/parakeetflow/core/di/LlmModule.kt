package com.github.gafiatulin.parakeetflow.core.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Hilt module for LLM-related bindings.
 *
 * PostProcessor and PromptBuilder are self-provided via @Singleton @Inject constructor,
 * so no explicit @Provides methods are needed here. This module is kept as a placeholder
 * for future LLM-related bindings (e.g., swappable engine implementations).
 */
@Module
@InstallIn(SingletonComponent::class)
object LlmModule
