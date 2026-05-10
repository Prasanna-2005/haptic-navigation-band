package com.ridernav.rider_nav;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import io.flutter.plugin.common.MethodChannel;

public class MapsAccessibilityService extends AccessibilityService {
    private static final String TAG = "MapsAccessibilityService";
    private static final String CHANNEL = "com.ridernav.rider_nav/maps";
    private static MethodChannel methodChannel;

    public static void setMethodChannel(MethodChannel channel) {
        methodChannel = channel;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getPackageName() == null || !event.getPackageName().toString().equals("com.google.android.apps.maps")) {
            return;
        }

        AccessibilityNodeInfo rootNode = getRootInActiveWindow();
        if (rootNode == null) return;

        String instruction = findNavigationInstruction(rootNode);
        if (instruction != null && !instruction.isEmpty() && methodChannel != null) {
            Log.d(TAG, "Found instruction: " + instruction);
            methodChannel.invokeMethod("onNavigationInstruction", instruction);
        }
    }

    private String findNavigationInstruction(AccessibilityNodeInfo node) {
        if (node == null) return null;

        // Check if this node has text that looks like a navigation instruction
        CharSequence text = node.getText();
        if (text != null) {
            String textStr = text.toString().toLowerCase();
            // Look for common navigation keywords
            if ((textStr.contains("turn") || textStr.contains("continue") || textStr.contains("arrive") ||
                 textStr.contains("destination") || textStr.contains("exit") || textStr.contains("merge")) &&
                textStr.length() > 10 && textStr.length() < 200) {
                return text.toString();
            }
        }

        // Recursively check children
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            String result = findNavigationInstruction(child);
            if (result != null) return result;
        }

        return null;
    }

    @Override
    public void onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted");
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        Log.d(TAG, "Accessibility service connected");

        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED | AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        info.notificationTimeout = 100;
        setServiceInfo(info);
    }
}