import 'dart:async';
import 'package:flutter/services.dart';
import '../models/navigation_models.dart';

/// Service to receive real-time navigation instructions from Google Maps
/// via the Android NotificationListenerService.
class MapsAccessibilityService {
  static const MethodChannel _methodChannel = MethodChannel('com.ridernav.rider_nav/maps');
  static const EventChannel _eventChannel = EventChannel('com.ridernav.rider_nav/navigation_events');

  /// Stream of navigation events
  late Stream<NavigationEvent> _navigationStream;

  /// Last received instruction
  NavigationInstruction? _lastInstruction;

  StreamSubscription<NavigationEvent>? _navStreamSub;

  /// Stream controller for navigation updates
  final _navigationController = StreamController<NavigationEvent>.broadcast();

  /// Check if notification listener is enabled
  static Future<bool> isNotificationListenerEnabled() async {
    try {
      final enabled = await _methodChannel.invokeMethod<bool>('checkNotificationListenerEnabled');
      return enabled ?? false;
    } catch (e) {
      print('Error checking notification listener: $e');
      return false;
    }
  }

  /// Request user to enable notification listener
  static Future<void> requestNotificationListenerSettings() async {
    try {
      await _methodChannel.invokeMethod('requestNotificationListenerSettings');
    } catch (e) {
      print('Error requesting notification listener settings: $e');
    }
  }

  /// Get stream of navigation events
  Stream<NavigationEvent> get navigationStream {
    return _navigationStream;
  }

  /// Get last received instruction
  NavigationInstruction? get lastInstruction => _lastInstruction;

  /// Initialize the service and start listening for events
  void initialize() {
    // Create stream from EventChannel
    _navigationStream = _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => NavigationEvent.fromMap(event as Map<dynamic, dynamic>))
        .handleError((error) {
          print('Error in navigation event stream: $error');
        });

    // Listen to stream and forward to controller
    _navStreamSub = _navigationStream.listen(
      (event) {
        print('📍 Navigation event received: $event');
        if (event.instruction != null) {
          _lastInstruction = event.instruction;
        }
        _navigationController.add(event);
      },
      onError: (error) {
        print('❌ Navigation stream error: $error');
        _navigationController.addError(error);
      },
    );
  }

  /// Stop listening for events
  void dispose() {
    _navStreamSub?.cancel();
    _navigationController.close();
  }

  /// Callback invoked when a navigation instruction is received.
  /// This is for legacy compatibility.
  void Function(String instruction)? onInstruction;

  /// Start listening for accessibility events.
  void startListening() {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
    initialize();
  }

  /// Stop listening.
  void stopListening() {
    _methodChannel.setMethodCallHandler(null);
    dispose();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNavigationInstruction') {
      final String instruction = call.arguments as String;
      onInstruction?.call(instruction);
    } else if (call.method == 'onNavigationData') {
      final Map<dynamic, dynamic> data = call.arguments as Map<dynamic, dynamic>;
      final event = NavigationEvent.fromMap(data);
      _navigationController.add(event);
    }
  }
}
