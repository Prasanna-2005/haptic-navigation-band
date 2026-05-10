import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'bluetooth_service.dart';
import '../models/navigation_models.dart';

/// Service that handles directional Bluetooth signaling based on navigation
/// instructions with strict one-time-trigger constraints.
///
/// Signal → Arm mapping:
///   L1/L2/L3 → Left Arm only  (left turns)
///   R1/R2/R3 → Right Arm only (right turns)
///   F1/F2/F3 → Both Arms      (flyovers)
///   U        → Both Arms      (u-turns)
///
/// Distance resolution strategy:
///   1. Direct metres  (e.g. "90 m", "1.2 km") — parsed directly.
///   2. ETA time string (e.g. "19:25")          — remaining seconds × GPS speed.
///   3. Missing / unparseable                   — returns 'N', no signal sent.
///
/// Each signal is sent only once per turn instruction.
class NavigationBluetoothService {
  final BleService _bleService;

  // ── Turn state ────────────────────────────────────────────────────────────
  String? _currentDirection;       // "left", "right", "uturn", "flyover"
  String? _lastInstructionText;    // Detects new turns with same direction
  bool _hasSentL1Signal = false;   // far  : < 500 m
  bool _hasSentL2Signal = false;   // medium: < 250 m
  bool _hasSentL3Signal = false;   // near  : < 100 m
  bool _hasSentFlyoverSignal = false;

  // ── GPS speed tracking ────────────────────────────────────────────────────
  /// Current speed in m/s from geolocator; null until first fix.
  double? _currentSpeedMs;
  StreamSubscription<Position>? _positionSub;

  final AudioPlayer _audioPlayer = AudioPlayer();

  NavigationBluetoothService({required BleService bleService})
      : _bleService = bleService {
    _startSpeedTracking();
  }

  // ── GPS speed stream ──────────────────────────────────────────────────────

  /// Subscribe to the device position stream and keep [_currentSpeedMs] fresh.
  void _startSpeedTracking() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // receive every update
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        // speed is in m/s; negative values mean "unavailable" on some devices
        if (position.speed >= 0) {
          _currentSpeedMs = position.speed;
        }
      },
      onError: (e) {
        debugPrint('⚠️ NavBT GPS stream error: $e');
      },
    );
  }

  // ── Main entry point ──────────────────────────────────────────────────────

  /// Process a navigation instruction and send the appropriate BLE signal.
  Future<String> processNavigation(NavigationInstruction instruction) async {

    final fullText = instruction.fullText.toLowerCase();
    final isFlyover = fullText.contains('flyover') ||
        fullText.contains('overpass') ||
        fullText.contains('bridge') ||
        fullText.contains('ramp') ||
        fullText.contains('underpass') ||
        fullText.contains('tunnel') ||
        fullText.contains('slip road');

    final direction =
        isFlyover ? 'flyover' : _getDirectionString(instruction.direction);

    // ── Non-turn instructions ───────────────────────────────────────────────
    // Straight / head-forward / arrive → no signal.
    // Also reset state so the NEXT turn (even same direction) fires fresh.
    if (direction == null) {
      if (_currentDirection != null) {
        debugPrint(
          'ℹ️ NavBT: Non-turn — resetting state (was: $_currentDirection)',
        );
        _resetTurnFlags();
      }
      await _sendBluetoothSignal('-1');
      return 'N';
    }

    // ── Resolve distance ────────────────────────────────────────────────────
    final int? distance = await _resolveDistance(instruction.distance);

    if (distance == null) {
      debugPrint(
        '⚠️ NavBT: Cannot resolve distance '
        '(direction: $direction, raw: "${instruction.distance}")',
      );
      await _sendBluetoothSignal('-1');
      return 'N';
    }

    // ── New-turn detection ──────────────────────────────────────────────────
    final instrText = instruction.fullText.toLowerCase();
    final isNewTurn = direction != _currentDirection ||
        (_lastInstructionText != null && instrText != _lastInstructionText);

    if (isNewTurn) {
      debugPrint(
        '🔄 NavBT: New turn detected '
        '(${_currentDirection ?? "none"} → $direction, '
        'text changed: ${_lastInstructionText != instrText})',
      );
      _currentDirection = direction;
      _lastInstructionText = instrText;
      _resetTurnFlags();
    }

    // ── Dispatch ────────────────────────────────────────────────────────────
    switch (direction) {
      case 'left':
        return await _processLeftTurn(distance);
      case 'right':
        return await _processRightTurn(distance);
      case 'uturn':
        return await _processUTurn(distance);
      case 'flyover':
        return await _processFlyover(distance);
      default:
        debugPrint('⚠️ NavBT: Unknown direction: $direction');
        return 'N';
    }
  }

  // ── Distance resolution ───────────────────────────────────────────────────

  /// Resolve the raw distance string from Google Maps to metres (int).
  ///
  /// Handles two formats:
  ///   • Metres / km  : "90 m", "1.2 km", "500m"  → parsed directly.
  ///   • ETA clock    : "19:25", "7:05 PM"         → (ETA - now) × GPS speed.
  ///
  /// Returns null if the distance cannot be reliably determined.
  Future<int?> _resolveDistance(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return null;

    // 1. Try as a plain distance string first (fastest path).
    final direct = _parseMetresDirect(raw);
    if (direct != null) return direct;

    // 2. Try as an ETA time string.
    final etaSeconds = _parseEtaSeconds(raw);
    if (etaSeconds != null) {
      return _estimateMetresFromEta(etaSeconds);
    }

    return null;
  }

  /// Parse "90 m" / "500 m" / "1.2 km" → metres as int.
  ///
  /// Returns null if the string looks like a time (contains ":") or is
  /// otherwise unparseable.
  static int? _parseMetresDirect(String raw) {
    final s = raw.trim().toLowerCase();

    // Reject ETA-style strings immediately to avoid mis-parsing "19:25" → 1925
    if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(s)) return null;

    try {
      if (s.contains('km')) {
        // "1.2 km" → 1200
        final numStr = s.replaceAll(RegExp(r'[^\d.]'), '');
        if (numStr.isEmpty) return null;
        return (double.parse(numStr) * 1000).round();
      } else {
        // "90 m", "500m" → digits only
        final numStr = s.replaceAll(RegExp(r'[^\d]'), '');
        if (numStr.isEmpty) return null;
        return int.parse(numStr);
      }
    } catch (_) {
      return null;
    }
  }

  /// Parse an ETA clock string into seconds remaining from now.
  ///
  /// Handles 24-hour ("19:25") and 12-hour ("7:25 PM") formats.
  /// Returns null if the string doesn't match a known time pattern.
  static int? _parseEtaSeconds(String raw) {
    final s = raw.trim();

    // Match:  "19:25"  /  "7:25"  /  "7:25 PM"  /  "7:25 AM"
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?:\s*(am|pm))?',
      caseSensitive: false,
    ).firstMatch(s);

    if (match == null) return null;

    int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    final String? ampm = match.group(3)?.toLowerCase();

    // Convert to 24-hour if AM/PM suffix is present
    if (ampm == 'pm' && hour < 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;

    final now = DateTime.now();
    var eta = DateTime(now.year, now.month, now.day, hour, minute);

    // If the ETA is in the past (e.g., midnight wrap-around) add a day
    if (eta.isBefore(now)) {
      eta = eta.add(const Duration(days: 1));
    }

    final secondsRemaining = eta.difference(now).inSeconds;

    debugPrint(
      '🕐 NavBT: ETA parse — raw="$s", ETA=$eta, '
      'now=$now, secondsRemaining=$secondsRemaining',
    );

    // Sanity check: ETA more than 2 hours away is probably wrong
    if (secondsRemaining <= 0 || secondsRemaining > 7200) return null;

    return secondsRemaining;
  }

  /// Estimate distance in metres from [secondsRemaining] and current GPS speed.
  ///
  /// Falls back to a conservative 30 km/h estimate when GPS is unavailable.
  int? _estimateMetresFromEta(int secondsRemaining) {
    const double fallbackSpeedMs = 30.0 / 3.6; // 30 km/h → m/s

    final double speedMs = (_currentSpeedMs != null && _currentSpeedMs! > 0.5)
        ? _currentSpeedMs!
        : fallbackSpeedMs;

    final int estimatedMetres = (speedMs * secondsRemaining).round();

    debugPrint(
      '📐 NavBT: ETA→distance — '
      '${secondsRemaining}s × ${speedMs.toStringAsFixed(1)} m/s '
      '= ${estimatedMetres}m '
      '(GPS ${_currentSpeedMs == null ? "unavailable, using fallback" : "available"})',
    );

    // If estimated distance is absurdly large, something is off — skip signal.
    if (estimatedMetres > 50000) return null;

    return estimatedMetres;
  }

  // ── Turn processors ───────────────────────────────────────────────────────

  Future<String> _processLeftTurn(int distance) async {
    debugPrint(
      '⬅️ Left ${distance}m '
      '(l1:$_hasSentL1Signal l2:$_hasSentL2Signal l3:$_hasSentL3Signal)',
    );
    if (distance < 500 && !_hasSentL1Signal) {
      await _sendBluetoothSignal('l1');
      _hasSentL1Signal = true;
      return 'l1';
    }
    if (distance < 250 && !_hasSentL2Signal) {
      await _sendBluetoothSignal('l2');
      _hasSentL2Signal = true;
      return 'l2';
    }
    if (distance < 100 && !_hasSentL3Signal) {
      await _sendBluetoothSignal('l3');
      _hasSentL3Signal = true;
      return 'l3';
    }
    return 'N';
  }

  Future<String> _processRightTurn(int distance) async {
    debugPrint(
      '➡️ Right ${distance}m '
      '(r1:$_hasSentL1Signal r2:$_hasSentL2Signal r3:$_hasSentL3Signal)',
    );
    if (distance < 500 && !_hasSentL1Signal) {
      await _sendBluetoothSignal('r1');
      _hasSentL1Signal = true;
      return 'r1';
    }
    if (distance < 250 && !_hasSentL2Signal) {
      await _sendBluetoothSignal('r2');
      _hasSentL2Signal = true;
      return 'r2';
    }
    if (distance < 100 && !_hasSentL3Signal) {
      await _sendBluetoothSignal('r3');
      _hasSentL3Signal = true;
      return 'r3';
    }
    return 'N';
  }

  Future<String> _processUTurn(int distance) async {
    debugPrint('↩️ U-turn ${distance}m (sent:$_hasSentL1Signal)');
    if (distance < 250 && !_hasSentL1Signal) {
      await _sendBluetoothSignal('u');
      _hasSentL1Signal = true;
      return 'u';
    }
    return 'N';
  }

  Future<String> _processFlyover(int distance) async {
    debugPrint(
      '🛫 Flyover ${distance}m '
      '(f1:$_hasSentL1Signal f2:$_hasSentL2Signal f3:$_hasSentL3Signal)',
    );

    final prefs = await SharedPreferences.getInstance();
    final useHardware = prefs.getBool('flyover_use_hardware') ?? true;

    if (!useHardware && !_hasSentFlyoverSignal) {
      if (distance < 1000) {
        _hasSentFlyoverSignal = true;
        await _audioPlayer.play(AssetSource('audio/alert.ogg'));
        debugPrint('🔔 NavBT: Played audio alert for flyover.');
        return 'audio';
      }
      return 'N';
    }

    if (distance < 1000 && !_hasSentL1Signal) {
      await _sendBluetoothSignal('f1');
      _hasSentL1Signal = true;
      return 'f1';
    }
    if (distance < 500 && !_hasSentL2Signal) {
      await _sendBluetoothSignal('f2');
      _hasSentL2Signal = true;
      return 'f2';
    }
    if (distance < 250 && !_hasSentL3Signal) {
      await _sendBluetoothSignal('f3');
      _hasSentL3Signal = true;
      return 'f3';
    }
    return 'N';
  }

  // ── BLE send ──────────────────────────────────────────────────────────────

  Future<void> _sendBluetoothSignal(String signal) async {
    if (!_bleService.isConnected) {
      debugPrint('❌ NavBT: Cannot send "$signal" — device not connected');
      return;
    }
    try {
      final success = await _bleService.sendStringSignal(signal);
      if (success) {
        debugPrint('📤 NavBT: Signal sent: "$signal"');
      } else {
        debugPrint('❌ NavBT: Failed to send "$signal" (BLE error)');
      }
    } catch (e) {
      debugPrint('❌ NavBT: Exception sending "$signal": $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _resetTurnFlags() {
    _hasSentL1Signal = false;
    _hasSentL2Signal = false;
    _hasSentL3Signal = false;
    _hasSentFlyoverSignal = false;
  }

  static String? _getDirectionString(DirectionType direction) {
    switch (direction) {
      case DirectionType.turnLeft:
      case DirectionType.sharpLeft:
      case DirectionType.slightLeft:
        return 'left';
      case DirectionType.turnRight:
      case DirectionType.sharpRight:
      case DirectionType.slightRight:
        return 'right';
      case DirectionType.uTurn:
        return 'uturn';
      case DirectionType.arrive:
      case DirectionType.continueStraight:
      case DirectionType.headForward:
      case DirectionType.unknown:
        return null;
    }
  }

  // ── State / lifecycle ─────────────────────────────────────────────────────

  Map<String, dynamic> getState() => {
        'currentDirection': _currentDirection,
        'hasSentL1Signal': _hasSentL1Signal,
        'hasSentL2Signal': _hasSentL2Signal,
        'hasSentL3Signal': _hasSentL3Signal,
        'currentSpeedKmh': _currentSpeedMs != null
            ? (_currentSpeedMs! * 3.6).toStringAsFixed(1)
            : 'unknown',
        'isConnected': _bleService.isConnected,
        'deviceName': _bleService.connectedDeviceName,
      };

  void resetState() {
    debugPrint('🔄 NavBT: Resetting state');
    _currentDirection = null;
    _lastInstructionText = null;
    _resetTurnFlags();
  }

  void dispose() {
    _positionSub?.cancel();
    _audioPlayer.dispose();
    resetState();
  }
}
