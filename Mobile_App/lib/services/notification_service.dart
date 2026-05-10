import 'dart:async';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

/// Wraps [NotificationListenerService] to capture Google Maps notifications.
class NotificationService {
  static const _googleMapsPackage = 'com.google.android.apps.maps';

  StreamSubscription<ServiceNotificationEvent>? _subscription;

  /// Callback invoked when a Google Maps notification is received.
  /// Parameters: (title, body)
  void Function(String title, String body)? onNotification;

  // ---------------------------------------------------------------------------
  // Permission helpers
  // ---------------------------------------------------------------------------

  /// Whether the user has granted notification-listener permission.
  Future<bool> get isPermissionGranted =>
      NotificationListenerService.isPermissionGranted();

  /// Opens the Android notification listener settings page so the user can
  /// grant permission to this app.
  Future<void> requestPermission() =>
      NotificationListenerService.requestPermission();

  // ---------------------------------------------------------------------------
  // Listening
  // ---------------------------------------------------------------------------

  /// Start listening for notifications. Only Google Maps notifications are
  /// forwarded to [onNotification].
  void startListening() {
    _subscription?.cancel();
    _subscription = NotificationListenerService.notificationsStream.listen(
      _handleNotification,
    );
    print('👂 NotificationService: listening started');
  }

  /// Stop listening.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    print('🛑 NotificationService: listening stopped');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _handleNotification(ServiceNotificationEvent event) {
    final packageName = event.packageName ?? '';
    final title = event.title ?? '';
    final body = event.content ?? '';

    // Debug: log every notification
    print('📬 Notification from $packageName: title="$title" body="$body"');

    // Only process Google Maps
    if (packageName != _googleMapsPackage) return;

    print('📬 Google Maps notification: title="$title" body="$body"');

    // Forward the relevant text — title often has the turn instruction,
    // body sometimes has extra detail. Combine both for the parser.
    final combined = '$title $body'.trim();
    if (combined.isNotEmpty) {
      onNotification?.call(title, combined);
    }
  }
}
