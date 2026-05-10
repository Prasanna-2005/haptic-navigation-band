package com.ridernav.rider_nav

import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.ridernav.rider_nav/maps"
    private val EVENT_CHANNEL = "com.ridernav.rider_nav/navigation_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up MethodChannel for Flutter permission checks
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkNotificationListenerEnabled" -> {
                    result.success(isNotificationListenerEnabled())
                }
                "requestNotificationListenerSettings" -> {
                    openNotificationListenerSettings()
                    result.success(true)
                }
                "checkPermissions" -> {
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up EventChannel for real-time navigation updates
        // Primary: NotificationListenerService captures Google Maps notifications
        NotificationListenerServiceImpl.setFlutterEngine(flutterEngine)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(pkgName)
    }

    private fun openNotificationListenerSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }
}

