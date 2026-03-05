package com.github.gafiatulin.parakeetflow.feedback

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import com.github.gafiatulin.parakeetflow.R
import com.github.gafiatulin.parakeetflow.core.preferences.PreferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FeedbackManager @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val preferencesDataStore: PreferencesDataStore
) {
    companion object {
        private const val TAG = "FeedbackManager"
    }

    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    private val loadedSounds = mutableSetOf<Int>()

    private val soundPool: SoundPool = SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build().also { pool ->
            pool.setOnLoadCompleteListener { _, sampleId, status ->
                if (status == 0) {
                    loadedSounds.add(sampleId)
                    Log.d(TAG, "Sound loaded: $sampleId")
                } else {
                    Log.e(TAG, "Sound load failed: $sampleId status=$status")
                }
            }
        }

    private val startSoundId: Int = soundPool.load(context, R.raw.recording_start, 1)
    private val stopSoundId: Int = soundPool.load(context, R.raw.recording_stop, 1)

    suspend fun onRecordingStart() {
        val settings = preferencesDataStore.settings.first()
        if (settings.hapticFeedback) vibrateStart()
        if (settings.audioFeedback) playSound(startSoundId)
    }

    suspend fun onRecordingStop() {
        val settings = preferencesDataStore.settings.first()
        if (settings.hapticFeedback) vibrateStop()
        if (settings.audioFeedback) playSound(stopSoundId)
    }

    suspend fun onError() {
        val settings = preferencesDataStore.settings.first()
        if (settings.hapticFeedback) vibrateError()
    }

    private fun playSound(soundId: Int) {
        if (soundId in loadedSounds) {
            soundPool.play(soundId, 1f, 1f, 1, 0, 1f)
        } else {
            Log.w(TAG, "Sound $soundId not loaded yet, loaded=$loadedSounds")
        }
    }

    private fun vibrateStart() {
        try {
            vibrator.vibrate(VibrationEffect.createOneShot(60, 200))
        } catch (e: Exception) {
            Log.w(TAG, "Vibration failed", e)
        }
    }

    private fun vibrateStop() {
        try {
            vibrator.vibrate(
                VibrationEffect.createWaveform(
                    longArrayOf(0, 40, 60, 40),
                    intArrayOf(0, 180, 0, 180),
                    -1
                )
            )
        } catch (e: Exception) {
            Log.w(TAG, "Vibration failed", e)
        }
    }

    private fun vibrateError() {
        try {
            vibrator.vibrate(
                VibrationEffect.createWaveform(
                    longArrayOf(0, 80, 60, 80, 60, 80),
                    intArrayOf(0, 255, 0, 255, 0, 255),
                    -1
                )
            )
        } catch (e: Exception) {
            Log.w(TAG, "Vibration failed", e)
        }
    }
}
