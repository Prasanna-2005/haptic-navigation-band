import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/maps_accessibility_service.dart';
import '../services/bluetooth_service.dart';
import '../services/turn_parser.dart';

/// Screen shown after setup — displays real-time notification/parsing/sending
/// status while the user navigates in Google Maps. (Diagnostic View)
class ReadyScreen extends StatefulWidget {
  final BleService bleService;

  const ReadyScreen({
    super.key,
    required this.bleService,
  });

  @override
  State<ReadyScreen> createState() => _ReadyScreenState();
}

class _ReadyScreenState extends State<ReadyScreen> {
  final List<_LogEntry> _logs = [];
  final MapsAccessibilityService _mapsService = MapsAccessibilityService();
  bool _bleConnected = false;
  StreamSubscription<bool>? _bleSub;
  String _status = 'Ready';
  String _currentInstruction = 'Waiting for navigation...';

  @override
  void initState() {
    super.initState();
    _startBLEListening();
    _startMapsListening();
  }

  void _startBLEListening() {
    _bleSub = widget.bleService.connectionStream.listen((connected) {
      if (mounted) setState(() => _bleConnected = connected);
    });
    setState(() => _bleConnected = widget.bleService.isConnected);
  }

  void _startMapsListening() {
    _mapsService.onInstruction = _onInstruction;
    _mapsService.startListening();
  }

  Future<void> _connectBLE() async {
    showDialog(
      context: context,
      builder: (context) => _BLEConnectDialog(bleService: widget.bleService),
    ).then((_) {
      setState(() => _bleConnected = widget.bleService.isConnected);
    });
  }

  Future<void> _onInstruction(String instruction) async {
    _addLog('Accessibility: $instruction', LogType.notification);
    _setStatus('Parsing...');
    _setCurrentInstruction(instruction);

    final result = TurnParser.parse(instruction);

    _addLog(
      '${result.action.name} → Signal: ${result.signal} (${TurnParser.signalLabel(result.signal)})',
      LogType.parsed,
    );

    if (result.action == TurnAction.ignore) {
      _setStatus('Waiting for navigation...');
      return;
    }

    _setStatus('Sending signal ${result.signal}...');

    if (!widget.bleService.isConnected) {
      _addLog('Cannot send — ESP32 not connected', LogType.error);
      _setStatus('Waiting for navigation...');
      return;
    }

    final sent = await widget.bleService.sendSignal(result.signal);
    if (sent) {
      _addLog('Signal sent: ${result.signal}', LogType.sent);
    } else {
      _addLog('Failed to send signal', LogType.error);
    }

    _setStatus('Waiting for navigation...');
  }

  void _addLog(String message, LogType type) {
    if (mounted) {
      setState(() {
        _logs.insert(0, _LogEntry(message: message, type: type, time: DateTime.now()));
        if (_logs.length > 100) _logs.removeLast(); 
      });
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  void _setCurrentInstruction(String instruction) {
    if (mounted) setState(() => _currentInstruction = instruction);
  }

  @override
  void dispose() {
    _mapsService.stopListening();
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Nav Diagnostic'),
        actions: [
          if (_bleConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Disconnect',
              onPressed: () async => await widget.bleService.disconnect(),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(theme),
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardTheme.color?.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Current Instruction:', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_currentInstruction, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        Divider(color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_status.contains('Waiting') || _status.contains('Ready'))
                              const _PulsingDot()
                            else
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
                            const SizedBox(width: 16),
                            Expanded(child: Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 14))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_bleConnected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ElevatedButton.icon(
                  onPressed: _connectBLE,
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Connect ESP32 Hardware'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Align(alignment: Alignment.centerLeft, child: Text('Event Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
            Expanded(
              child: _logs.isEmpty
                  ? Center(child: Text('No events yet.\nStart navigating.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.3))))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) => _buildLogTile(theme, _logs[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          _statusChip(
            theme: theme,
            icon: Icons.bluetooth_connected,
            label: 'ESP32 Status',
            ok: _bleConnected,
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required bool ok,
  }) {
    final color = ok ? const Color(0xFF00C853) : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLogTile(ThemeData theme, _LogEntry log) {
    Color color;
    IconData icon;
    switch (log.type) {
      case LogType.notification:
        color = theme.colorScheme.primary;
        icon = Icons.notifications_none;
        break;
      case LogType.parsed:
        color = theme.colorScheme.secondary;
        icon = Icons.memory;
        break;
      case LogType.sent:
        color = const Color(0xFF00C853);
        icon = Icons.send;
        break;
      case LogType.error:
        color = theme.colorScheme.error;
        icon = Icons.error_outline;
        break;
    }

    final time = '${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          border: Border(left: BorderSide(color: color, width: 3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color.withOpacity(0.8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.message, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(time, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum LogType { notification, parsed, sent, error }

class _LogEntry {
  final String message;
  final LogType type;
  final DateTime time;
  const _LogEntry({required this.message, required this.type, required this.time});
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(const Color(0xFF00C853).withOpacity(0.5), const Color(0xFF00C853), _ctrl.value),
          boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(_ctrl.value * 0.6), blurRadius: 10, spreadRadius: 2)],
        ),
      ),
    );
  }
}

class _BLEConnectDialog extends StatefulWidget {
  final BleService bleService;
  const _BLEConnectDialog({required this.bleService});
  @override
  State<_BLEConnectDialog> createState() => _BLEConnectDialogState();
}

class _BLEConnectDialogState extends State<_BLEConnectDialog> {
  bool _scanning = false;
  List<ScanResult> _scanResults = [];
  String? _connectingTo;
  StreamSubscription? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    setState(() { _scanning = true; _scanResults = []; });
    _scanSub?.cancel();
    _scanSub = widget.bleService.scanForDevices(timeout: 6).listen((results) {
      if (mounted) setState(() => _scanResults = results.where((r) => r.device.platformName.isNotEmpty).toList());
    });
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connectToDevice(ScanResult result) async {
    setState(() => _connectingTo = result.device.platformName);
    await widget.bleService.stopScan();
    final success = await widget.bleService.connectToDevice(result.device);
    if (mounted) {
      setState(() { _connectingTo = null; _scanning = false; });
      if (success) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Connect ESP32', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _scanning ? null : _startScan,
              icon: _scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bluetooth_searching, size: 18),
              label: Text(_scanning ? 'Scanning...' : 'Scan'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            if (_scanResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 16),
                height: 200,
                decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.05)), borderRadius: BorderRadius.circular(12)),
                child: ListView.separated(
                  itemCount: _scanResults.length,
                  separatorBuilder: (_, _) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                  itemBuilder: (context, index) {
                    final r = _scanResults[index];
                    final name = r.device.platformName;
                    final isConnecting = _connectingTo == name;
                    return ListTile(
                      leading: Icon(Icons.bluetooth, color: name.contains('Nav') ? theme.colorScheme.primary : Colors.white38),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: isConnecting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(onPressed: () => _connectToDevice(r), child: const Text('Connect')),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}
