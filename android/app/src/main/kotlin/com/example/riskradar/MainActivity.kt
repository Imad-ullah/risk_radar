package com.example.riskradar

import android.media.AudioManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.riskradar/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "setAlarmVolume" -> {
                        // Force alarm stream to max volume — bypasses silent/vibrate
                        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_ALARM,
                            maxVolume,
                            0
                        )
                        result.success(true)
                    }
                    "restoreVolume" -> {
                        // Nothing needed — system restores on its own
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}