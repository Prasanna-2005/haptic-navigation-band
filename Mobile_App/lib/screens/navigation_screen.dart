import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/navigation_models.dart';
import '../services/maps_accessibility_service.dart';
import '../services/bluetooth_service.dart';
import '../services/navigation_bluetooth_service.dart';
import '../screens/setup_screen.dart';

/// Screen to display real-time navigation instructions from Google Maps.
class NavigationScreen extends StatefulWidget {
  final BleService bleService;

  const NavigationScreen({
    super.key,
    required this.bleService,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _LogEntry {
  final NavigationInstruction instruction;
  String? signalStr;

  _LogEntry(this.instruction, [this.signalStr]);
}

class _NavigationScreenState extends State<NavigationScreen> {
  late MapsAccessibilityService _navService;
  late BleService _bleService;
  late NavigationBluetoothService _navBluetoothService;
  NavigationInstruction? _currentInstruction;
  List<_LogEntry> _instructionHistory = [];
  bool _isNavigating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
  }

  Future<void> _initializeNavigation() async {
    _navService = MapsAccessibilityService();
    _bleService = widget.bleService;
    _navBluetoothService = NavigationBluetoothService(bleService: _bleService);

    final enabled = await MapsAccessibilityService.isNotificationListenerEnabled();

    if (!enabled && mounted) {
      setState(() {
        _errorMessage = 'Notification access is required. Please enable it in system settings.';
      });
    } else {
      _navService.initialize();
      _navService.navigationStream.listen(
        (event) {
          if (mounted) {
            setState(() {
              if (event.type == 'navigation_update' && event.instruction != null) {
                _currentInstruction = event.instruction;
                final logEntry = _LogEntry(event.instruction!);
                _instructionHistory.insert(0, logEntry);
                if (_instructionHistory.length > 100) {
                  _instructionHistory.removeLast();
                }
                _isNavigating = true;
                _errorMessage = null;

                _navBluetoothService.processNavigation(event.instruction!).then((signal) {
                  if (mounted) {
                    setState(() {
                      logEntry.signalStr = signal;
                    });
                  }
                }).catchError((e) {
                  debugPrint('Warning: Bluetooth signal processing error: $e');
                  if (mounted) {
                    setState(() {
                      logEntry.signalStr = 'E'; // E for Error
                    });
                  }
                });
              } else if (event.type == 'navigation_end') {
                _isNavigating = false;
                _navBluetoothService.resetState();
                _navigationEnded();
              }
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Error: $error';
              _isNavigating = false;
            });
          }
        },
      );

      setState(() {
        _errorMessage = null;
      });
    }
  }

  void _navigationEnded() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Navigation Ended'),
        content: const Text('You have reached your destination.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _navService.dispose();
    _navBluetoothService.dispose();
    // NOTE: Do NOT dispose _bleService here.
    // The BT connection should persist across ride sessions so the user
    // doesn't have to re-pair every time navigation ends.
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('End Navigation?'),
        content: const Text('Are you sure you want to stop navigation? Hardware vibration will stop, and you will be returned to the home screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('End Journey', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == true) {
      _navBluetoothService.resetState();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
    return false; // Prevent default pop, we navigated manually
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _confirmExit(),
            tooltip: 'End Navigation',
          ),
          title: const Text('Smart Nav', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Stack(
        children: [
          // Background Elements
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.primary.withOpacity(0.2), blurRadius: 100),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.2), blurRadius: 100),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _buildBody(theme),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildBody(ThemeData theme) {
    if (_errorMessage != null) {
      return _buildErrorWidget(theme);
    }
    if (!_isNavigating) {
      return _buildWaitingWidget(theme);
    }
    if (_currentInstruction == null) {
      return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInstructionCard(theme),
          const SizedBox(height: 16),
          _buildStatusSection(theme),
          const SizedBox(height: 16),
          _buildHistorySection(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildGlassContainer(ThemeData theme, {required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: theme.cardTheme.color?.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _buildGlassContainer(
          theme,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: theme.colorScheme.error.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              ),
              const SizedBox(height: 24),
              Text(
                'Something went wrong',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await MapsAccessibilityService.requestNotificationListenerSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.1), foregroundColor: Colors.white),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _initializeNavigation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingWidget(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 40)],
              ),
              child: Icon(Icons.near_me_outlined, size: 64, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 32),
            const Text(
              'Awaiting Navigation...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              'Set a destination in Google Maps and begin your journey.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard(ThemeData theme) {
    final instruction = _currentInstruction!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3), // Border thickness
        child: Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(29),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              _getDirectionIcon(instruction.direction),
              const SizedBox(height: 24),
              Text(
                instruction.fullText,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(ThemeData theme) {
    final instruction = _currentInstruction!;
    return _buildGlassContainer(
      theme,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(child: _buildStatusItem(theme, 'Distance', instruction.distance ?? '-', Icons.map_outlined)),
          Container(width: 1, height: 50, color: Colors.white.withOpacity(0.1)),
          Expanded(child: _buildStatusItem(theme, 'Action', instruction.instruction.isEmpty ? 'Proceed' : instruction.instruction, Icons.turn_right_rounded)),
        ],
      ),
    );
  }

  Widget _buildStatusItem(ThemeData theme, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    if (_instructionHistory.isEmpty) return const SizedBox.shrink();

    return _buildGlassContainer(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Journey Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: Text('${_instructionHistory.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              )
            ],
          ),
          const SizedBox(height: 16),
          ..._instructionHistory.take(100).map((instr) => _buildHistoryTile(theme, instr)),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(ThemeData theme, _LogEntry entry) {
    final instr = entry.instruction;
    final sig = entry.signalStr;
    final displaySig = sig == null ? '...' : sig;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
            child: const Icon(Icons.history, size: 16, color: Colors.white54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${instr.fullText} ($displaySig)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(_formatTime(instr.timestamp), style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _getDirectionIcon(DirectionType direction) {
    IconData icon;
    Color color = Theme.of(context).colorScheme.primary;
    switch (direction) {
      case DirectionType.turnLeft:
      case DirectionType.sharpLeft:
      case DirectionType.slightLeft:
        icon = Icons.turn_left_rounded;
      case DirectionType.turnRight:
      case DirectionType.sharpRight:
      case DirectionType.slightRight:
        icon = Icons.turn_right_rounded;
      case DirectionType.uTurn:
        icon = Icons.u_turn_right_rounded;
      case DirectionType.continueStraight:
      case DirectionType.headForward:
        icon = Icons.straight_rounded;
      case DirectionType.arrive:
        icon = Icons.location_on_rounded;
        color = Theme.of(context).colorScheme.secondary;
      default:
        icon = Icons.navigation_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 30)],
      ),
      child: Icon(icon, size: 60, color: color),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    return '${difference.inHours}h ago';
  }
}
