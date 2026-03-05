package com.github.gafiatulin.parakeetflow.core.di

import com.github.gafiatulin.parakeetflow.asr.ParakeetSherpaEngine
import com.github.gafiatulin.parakeetflow.asr.TranscriptionEngine
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class AsrModule {

    @Binds
    @Singleton
    abstract fun bindTranscriptionEngine(
        impl: ParakeetSherpaEngine
    ): TranscriptionEngine
}
