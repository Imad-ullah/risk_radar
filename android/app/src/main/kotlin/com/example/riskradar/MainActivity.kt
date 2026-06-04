package com.example.riskradar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.riskradar/alarm"
    private val SOS_CHANNEL_ID = "sos_alerts_critical"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forceAlarmStreamVolume()
        ensureSosNotificationChannel()
    }

    override fun onResume() {
        super.onResume()
        forceAlarmStreamVolume()
        ensureSosNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "setAlarmVolume" -> {
                        forceAlarmStreamVolume()
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

    private fun forceAlarmStreamVolume() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVolume, 0)
    }

    private fun ensureSosNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val soundUri = Uri.parse("android.resource://$packageName/${R.raw.sos_alarm}")
        val existingChannel = notificationManager.getNotificationChannel(SOS_CHANNEL_ID)
        val canBypassDnd = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            notificationManager.isNotificationPolicyAccessGranted
        } else {
            false
        }
        val shouldRecreate = existingChannel == null ||
            existingChannel?.sound != soundUri ||
            existingChannel?.audioAttributes?.usage != AudioAttributes.USAGE_ALARM ||
            (canBypassDnd && existingChannel?.canBypassDnd() != true)

        if (!shouldRecreate) {
            return
        }

        if (existingChannel != null) {
            notificationManager.deleteNotificationChannel(SOS_CHANNEL_ID)
        }

        val alarmAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            SOS_CHANNEL_ID,
            "SOS Critical Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Critical SOS emergency alerts"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(soundUri, alarmAttributes)
            if (canBypassDnd) {
                setBypassDnd(true)
            }
        }

        notificationManager.createNotificationChannel(channel)
    }
}
