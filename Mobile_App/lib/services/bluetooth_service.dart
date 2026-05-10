import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE service that scans for, connects to, and writes to an ESP32.
class BleService {
  // Add your characteristic UUID as a constant
  static const String _targetCharUUID = "abcdefab-1234-1234-1234-abcdefabcdef";

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  bool get isConnected => _device != null && _writeCharacteristic != null;
  String? get connectedDeviceName => _device?.platformName;

  /// Stream of connection-state changes for the currently connected device.
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionStateController.stream;

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Scan for BLE devices for [timeout] seconds.
  /// Returns a stream of discovered devices.
  Stream<List<ScanResult>> scanForDevices({int timeout = 5}) {
    FlutterBluePlus.startScan(timeout: Duration(seconds: timeout));
    return FlutterBluePlus.scanResults;
  }

  /// Stop scanning.
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Connect to a specific device by [ScanResult].
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      print('📡 Connecting to ${device.platformName}...');
      await device.connect(license: License.free, autoConnect: false, timeout: const Duration(seconds: 10));
      _device = device;

      // Listen for disconnection
      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print('❌ Connection lost to ${device.platformName}');
          _writeCharacteristic = null;
          _connectionStateController.add(false);
          _attemptReconnect(device);
        }
      });

      // Discover services and find the writable characteristic
      final found = await _discoverWriteCharacteristic(device);
      _connectionStateController.add(found);

      if (found) {
        print(
            '📡 Connected to ${device.platformName}. Ready to send signals.');
        
        // Send exactly one test signal immediately after connection
        await _sendInitialTestSignal();
      } else {
        print(
            '⚠️ Connected but no writable characteristic found on ${device.platformName}');
      }
      return found;
    } catch (e) {
      print('❌ Connection failed: $e');
      _connectionStateController.add(false);
      return false;
    }
  }

  /// Convenience: connect to the first device whose name matches the target.
  Future<bool> connectToTargetDevice(ScanResult result) =>
      connectToDevice(result.device);

  // ---------------------------------------------------------------------------
  // Auto-reconnect
  // ---------------------------------------------------------------------------

  Future<void> _attemptReconnect(BluetoothDevice device) async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      print('🔄 Reconnect attempt $attempt...');
      await Future.delayed(Duration(seconds: 2 * attempt));
      try {
        await device.connect(
            license: License.free, autoConnect: false, timeout: const Duration(seconds: 10));
        final found = await _discoverWriteCharacteristic(device);
        if (found) {
          _connectionStateController.add(true);
          print('✅ Reconnected to ${device.platformName}');
          return;
        }
      } catch (_) {
        // retry
      }
    }
    print('❌ Failed to reconnect after 5 attempts');
  }

  // ---------------------------------------------------------------------------
  // Service / characteristic discovery
  // ---------------------------------------------------------------------------

  Future<bool> _discoverWriteCharacteristic(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final service in services) {
      for (final char in service.characteristics) {
        // Match by UUID instead of just any writable characteristic
        if (char.uuid.toString().toLowerCase() == _targetCharUUID.toLowerCase()) {
          _writeCharacteristic = char;
          print('📡 Found target char: ${char.uuid}');
          return true;
        }
      }
    }
    print('❌ Target characteristic not found');
    return false;
  }

  // ---------------------------------------------------------------------------
  // Sending signals
  // ---------------------------------------------------------------------------

  /// Send a single-byte vibration signal (0–3) to the ESP32.
  Future<bool> sendSignal(int signal) async {
    if (_writeCharacteristic == null) {
      print('❌ Cannot send signal — no writable characteristic');
      return false;
    }
    try {
      await _writeCharacteristic!.write(
        Uint8List.fromList([signal]),
        withoutResponse:
            _writeCharacteristic!.properties.writeWithoutResponse,
      );
      print('📤 Signal sent: $signal');
      return true;
    } catch (e) {
      print('❌ Failed to send signal: $e');
      return false;
    }
  }

  /// Send a string signal to the ESP32 via UTF-8 encoding.
  /// Used for directional signals: "l1", "l2", "l3", etc.
  Future<bool> sendStringSignal(String signal) async {
    if (_writeCharacteristic == null) {
      print('❌ Cannot send string signal — no writable characteristic');
      return false;
    }
    try {
      final bytes = Uint8List.fromList(signal.codeUnits);
      await _writeCharacteristic!.write(
        bytes,
        withoutResponse:
            _writeCharacteristic!.properties.writeWithoutResponse,
      );
      print('📤 String signal sent: "$signal" (${bytes.length} bytes)');
      return true;
    } catch (e) {
      print('❌ Failed to send string signal: $e');
      return false;
    }
  }

  /// Send exactly one test signal immediately after connection is established.
  /// Used to verify the connection works as expected.
  Future<void> _sendInitialTestSignal() async {
    const testSignal = 'A'; // Send random letter 'A'
    try {
      final success = await sendStringSignal(testSignal);
      if (success) {
        print('✅ Initial test signal sent successfully: "$testSignal"');
      } else {
        print('⚠️ Initial test signal failed to send');
      }
    } catch (e) {
      print('❌ Error sending initial test signal: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Disconnect and release resources.
  Future<void> disconnect() async {
    _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _writeCharacteristic = null;
    _connectionStateController.add(false);
    print('📡 Disconnected');
  }

  void dispose() {
    _connectionSub?.cancel();
    _connectionStateController.close();
  }
}
