package com.ridernav.rider_nav

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Alternative AccessibilityService to capture Google Maps navigation notifications.
 * This is a backup method in case notification listener doesn't work on certain devices.
 */
class MapsAccessibilityServiceImpl : AccessibilityService() {

    companion object {
        private const val TAG = "MapsAccessibility"
        private const val MAPS_PACKAGE = "com.google.android.apps.maps"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.packageName != MAPS_PACKAGE) return

        // Log accessibility events for debugging
        Log.d(TAG, "AccessibilityEvent: type=${event.eventType}, " +
            "text=${event.text}, contentDescription=${event.contentDescription}")

        // Extract text from event
        val eventText = event.text.joinToString(" ") { it.toString() }
        val contentDesc = event.contentDescription?.toString() ?: ""

        if (eventText.isEmpty() && contentDesc.isEmpty()) return

        Log.d(TAG, "Maps accessibility: $eventText | $contentDesc")

        // Parse navigation instruction
        val allText = "$eventText $contentDesc"
        val parsedInstruction = parseNavigationInstruction(allText)

        // Send to Flutter
        val navigationEvent: Map<String, Any> = mapOf(
            "type" to "navigation_update" as Any,
            "text" to (eventText as Any),
            "contentDescription" to (contentDesc as Any),
            "instruction" to (parsedInstruction["instruction"] ?: "" as Any),
            "direction" to (parsedInstruction["direction"] ?: "" as Any),
            "distance" to (parsedInstruction["distance"] ?: "" as Any),
            "heading" to (parsedInstruction["heading"] ?: "" as Any),
            "timestamp" to (System.currentTimeMillis() as Any)
        )

        NotificationListenerServiceImpl.sendNavigationEvent(navigationEvent)
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted")
    }

    /**
     * Parse navigation instruction from event text
     */
    private fun parseNavigationInstruction(text: String): Map<String, String> {
        val result = mutableMapOf(
            "instruction" to "",
            "direction" to "",
            "distance" to "",
            "heading" to ""
        )

        val allText = text.lowercase()

        // Extract instruction
        result["instruction"] = when {
            allText.contains("turn left") -> "Turn Left"
            allText.contains("turn right") -> "Turn Right"
            allText.contains("sharp left") -> "Sharp Left"
            allText.contains("sharp right") -> "Sharp Right"
            allText.contains("slight left") -> "Slight Left"
            allText.contains("slight right") -> "Slight Right"
            allText.contains("u-turn") || allText.contains("u turn") -> "U-Turn"
            allText.contains("continue") || allText.contains("straight") -> "Continue Straight"
            allText.contains("arrive") || allText.contains("destination") -> "Destination Reached"
            else -> ""
        }

        // Extract heading
        result["heading"] = when {
            allText.contains(" north") -> "North"
            allText.contains(" south") -> "South"
            allText.contains(" east") -> "East"
            allText.contains(" west") -> "West"
            else -> ""
        }

        // Extract distance
        val distanceRegex = Regex("""(\d+\.?\d*)\s*(m|km|ft|mi)""")
        val match = distanceRegex.find(allText)
        if (match != null) {
            result["distance"] = match.value
        }

        // Extract direction type
        result["direction"] = when {
            result["instruction"]!!.contains("Left") -> "left"
            result["instruction"]!!.contains("Right") -> "right"
            result["instruction"]!!.contains("Straight") || result["instruction"]!!.contains("Continue") -> "straight"
            result["instruction"]!!.contains("U-Turn") -> "uturn"
            else -> ""
        }

        return result
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "MapsAccessibilityService connected")
    }
}
