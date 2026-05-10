import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_service.dart' as ble_svc;
import '../services/maps_accessibility_service.dart';
import 'navigation_screen.dart';
import 'settings_screen.dart';

/// Setup screen — configure notification listener and optional BLE connection
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final ble_svc.BleService _bleService = ble_svc.BleService();

  bool _bleConnected = false;
  bool _scanning = false;
  List<ScanResult> _scanResults = [];
  String? _connectingTo;
  StreamSubscription? _scanSub;
  
  // Notification listener status
  bool _notificationListenerEnabled = false;
  bool _checkingNotificationListener = true;

  @override
  void initState() {
    super.initState();
    _checkNotificationListenerStatus();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _checkNotificationListenerStatus() async {
    final enabled = await MapsAccessibilityService.isNotificationListenerEnabled();
    if (mounted) {
      setState(() {
        _notificationListenerEnabled = enabled;
        _checkingNotificationListener = false;
      });
    }
  }

  Future<void> _requestNotificationListener() async {
    await MapsAccessibilityService.requestNotificationListenerSettings();
    // Check again after a short delay
    await Future.delayed(const Duration(seconds: 2));
    _checkNotificationListenerStatus();
  }

  Future<void> _startScan() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    setState(() {
      _scanning = true;
      _scanResults = [];
    });

    _scanSub?.cancel();
    _scanSub = _bleService.scanForDevices(timeout: 6).listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });
      }
    });

    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connectToDevice(ScanResult result) async {
    setState(() => _connectingTo = result.device.platformName);
    await _bleService.stopScan();

    final success = await _bleService.connectToDevice(result.device);
    if (mounted) {
      setState(() {
        _bleConnected = success;
        _connectingTo = null;
        _scanning = false;
      });
    }
  }

  void _proceed() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
            NavigationScreen(bleService: _bleService),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SettingsScreen(bleService: _bleService)),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient / Glows
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 100),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.3), blurRadius: 100),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // Header
                  Text(
                    'Smart Nav',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                        ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Elevate your navigation experience',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Notification Listener Setup
                  _buildGlassCard(
                    child: _buildNotificationListenerContent(theme),
                  ),
                  const SizedBox(height: 20),

                  // Optional BLE connection
                  _buildGlassCard(
                    child: _buildOptionalContent(theme),
                  ),

                  // Scan results list
                  if (_scanResults.isNotEmpty && !_bleConnected)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(top: 16),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color?.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _scanResults.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.05),
                              ),
                              itemBuilder: (context, index) {
                                final r = _scanResults[index];
                                final name = r.device.platformName;
                                final isConnecting = _connectingTo == name;
                                final isTarget = name.toLowerCase().contains('smart') || name.toLowerCase().contains('rider');
                                return ListTile(
                                  leading: Icon(
                                    Icons.bluetooth,
                                    color: isTarget ? theme.colorScheme.primary : Colors.white38,
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      color: isTarget ? theme.colorScheme.primary : Colors.white70,
                                      fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'RSSI: ${r.rssi} dBm',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                  trailing: isConnecting
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.primary,
                                          ),
                                        )
                                      : ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white.withOpacity(0.05),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: () => _connectToDevice(r),
                                          child: const Text('Connect'),
                                        ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_scanResults.isEmpty && !_bleConnected) const Spacer(),

                  // Proceed button
                  const SizedBox(height: 24),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _notificationListenerEnabled
                          ? [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.4), blurRadius: 20)]
                          : [],
                    ),
                    child: ElevatedButton(
                      onPressed: _notificationListenerEnabled && !_checkingNotificationListener
                          ? _proceed
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.scaffoldBackgroundColor,
                        disabledBackgroundColor: theme.cardTheme.color,
                        disabledForegroundColor: Colors.white24,
                      ),
                      child: const Text('Start Navigation'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color?.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildNotificationListenerContent(ThemeData theme) {
    if (_checkingNotificationListener) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Maps Notifications',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
              const SizedBox(width: 12),
              Text('Checking permissions...', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ],
          ),
        ],
      );
    }

    final color = _notificationListenerEnabled ? const Color(0xFF00C853) : theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _notificationListenerEnabled ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Maps Notifications', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    _notificationListenerEnabled ? 'Permissions granted' : 'Action required',
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!_notificationListenerEnabled) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _requestNotificationListener,
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Enable Access'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOptionalContent(ThemeData theme) {
    final title = 'Connect to ESP32';
    final subtitle = _bleConnected
        ? 'Connected to ${_bleService.connectedDeviceName}'
        : 'Connect smart hardware for haptic alerts';
    final color = _bleConnected ? const Color(0xFF00C853) : Colors.white70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _bleConnected ? color.withOpacity(0.15) : theme.colorScheme.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth,
                color: _bleConnected ? color : theme.colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        if (!_bleConnected) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _scanning ? null : _startScan,
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.bluetooth_searching, size: 18),
            label: Text(_scanning ? 'Scanning...' : 'Scan Devices'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.white.withOpacity(0.08),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ],
    );
  }
}
