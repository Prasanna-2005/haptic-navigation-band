package com.ridernav.rider_nav

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Android NotificationListenerService that monitors Google Maps notifications
 * and sends parsed navigation instructions to Flutter via EventChannel.
 */
class NotificationListenerServiceImpl : NotificationListenerService() {

    companion object {
        private const val TAG = "NavListener"
        private const val MAPS_PACKAGE = "com.google.android.apps.maps"
        private const val EVENT_CHANNEL_NAME = "com.ridernav.rider_nav/navigation_events"
        private var eventSink: EventChannel.EventSink? = null

        fun setFlutterEngine(engine: FlutterEngine) {
            setupEventChannel(engine)
        }

        private fun setupEventChannel(engine: FlutterEngine) {
            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        Log.d(TAG, "EventChannel listener registered")
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                        Log.d(TAG, "EventChannel listener cancelled")
                    }
                })
        }

        fun sendNavigationEvent(notification: Map<String, Any>) {
            eventSink?.success(notification)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)

        if (sbn == null) return
        if (sbn.packageName != MAPS_PACKAGE) return

        try {
            val notification = sbn.notification ?: return
            val extras = notification.extras ?: return

            val title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""
            val subtext = extras.getCharSequence(android.app.Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
            val bigText = extras.getCharSequence("android.bigText")?.toString() ?: ""

            // Combine all text for comprehensive parsing
            val fullText = listOfNotNull(title, text, subtext, bigText)
                .filter { it.isNotEmpty() }
                .joinToString(" | ")

            if (fullText.isEmpty()) return

            Log.d(TAG, "Maps notification: $fullText")

            // Parse the navigation instruction
            val parsedInstruction = parseNavigationInstruction(title, text, subtext, bigText)

            // Send to Flutter
            val navigationEvent: Map<String, Any> = mapOf(
                "type" to "navigation_update" as Any,
                "title" to (title as Any),
                "text" to (text as Any),
                "subtext" to (subtext as Any),
                "fullText" to (fullText as Any),
                "instruction" to (parsedInstruction["instruction"] ?: "" as Any),
                "direction" to (parsedInstruction["direction"] ?: "" as Any),
                "distance" to (parsedInstruction["distance"] ?: "" as Any),
                "heading" to (parsedInstruction["heading"] ?: "" as Any),
                "timestamp" to (System.currentTimeMillis() as Any)
            )

            sendNavigationEvent(navigationEvent)

        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)

        if (sbn == null) return
        if (sbn.packageName != MAPS_PACKAGE) return

        Log.d(TAG, "Navigation notification removed")
        val event: Map<String, Any> = mapOf(
            "type" to "navigation_end" as Any,
            "timestamp" to (System.currentTimeMillis() as Any)
        )
        sendNavigationEvent(event)
    }

    /**
     * Parse Google Maps notification text to extract structured navigation data
     */
    private fun parseNavigationInstruction(
        title: String,
        text: String,
        subtext: String,
        bigText: String
    ): Map<String, String> {
        val result = mutableMapOf(
            "instruction" to "",
            "direction" to "",
            "distance" to "",
            "heading" to ""
        )

        val allText = "$title $text $subtext $bigText".lowercase()

        // Extract instruction (Turn left, right, etc.)
        result["instruction"] = when {
            allText.contains("turn left") -> "Turn Left"
            allText.contains("turn right") -> "Turn Right"
            allText.contains("sharp left") -> "Sharp Left"
            allText.contains("sharp right") -> "Sharp Right"
            allText.contains("slight left") -> "Slight Left"
            allText.contains("slight right") -> "Slight Right"
            allText.contains("u-turn") || allText.contains("u turn") -> "U-Turn"
            allText.contains("continue") || allText.contains("straight") -> "Continue Straight"
            allText.contains("head") -> "Head Forward"
            allText.contains(Regex("head\\s+(north|south|east|west)")) -> extractHeading(allText)
            allText.contains("arrive") || allText.contains("destination") -> "Destination Reached"
            else -> text.ifBlank { title }
        }

        // Extract heading (North, South, East, West)
        result["heading"] = when {
            allText.contains(" north") -> "North"
            allText.contains(" south") -> "South"
            allText.contains(" east") -> "East"
            allText.contains(" west") -> "West"
            allText.contains(" northeast") || allText.contains(" north-east") -> "Northeast"
            allText.contains(" northwest") || allText.contains(" north-west") -> "Northwest"
            allText.contains(" southeast") || allText.contains(" south-east") -> "Southeast"
            allText.contains(" southwest") || allText.contains(" south-west") -> "Southwest"
            else -> ""
        }

        // Extract distance (e.g., "200 m", "0.5 km")
        val distanceRegex = Regex("""(\d+\.?\d*)\s*(m|km|ft|mi)""")
        val match = distanceRegex.find(allText)
        if (match != null) {
            result["distance"] = match.value
        }

        // Extract direction type as enum name for Dart parsing
        result["direction"] = when {
            result["instruction"]!!.contains("Sharp Left") -> "sharpLeft"
            result["instruction"]!!.contains("Slight Left") -> "slightLeft"
            result["instruction"]!!.contains("Turn Left") -> "turnLeft"
            result["instruction"]!!.contains("Sharp Right") -> "sharpRight"
            result["instruction"]!!.contains("Slight Right") -> "slightRight"
            result["instruction"]!!.contains("Turn Right") -> "turnRight"
            result["instruction"]!!.contains("U-Turn") -> "uTurn"
            result["instruction"]!!.contains("Straight") || result["instruction"]!!.contains("Continue") -> "continueStraight"
            result["instruction"]!!.contains("Head") -> "headForward"
            result["instruction"]!!.contains("Arrive") || result["instruction"]!!.contains("Destination") -> "arrive"
            else -> ""
        }

        return result
    }

    private fun extractHeading(text: String): String {
        return when {
            text.contains(Regex("head\\s+north")) -> "Head North"
            text.contains(Regex("head\\s+south")) -> "Head South"
            text.contains(Regex("head\\s+east")) -> "Head East"
            text.contains(Regex("head\\s+west")) -> "Head West"
            else -> "Head Forward"
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationListenerService connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "NotificationListenerService disconnected")
    }
}
