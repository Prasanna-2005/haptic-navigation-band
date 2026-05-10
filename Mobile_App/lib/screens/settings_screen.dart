import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/bluetooth_service.dart';

class SettingsScreen extends StatefulWidget {
  final BleService? bleService;

  const SettingsScreen({super.key, this.bleService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useHardware = true;
  bool _isLoading = true;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _useHardware = prefs.getBool('flyover_use_hardware') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flyover_use_hardware', value);
    setState(() {
      _useHardware = value;
    });
  }

  Future<void> _playDemo() async {
    await _audioPlayer.play(AssetSource('audio/alert.ogg'));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background Gradient Glows
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
            child: _isLoading 
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        // Dummy User Header
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                              child: Icon(Icons.person, size: 30, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, Rider',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    foreground: Paint()
                                      ..shader = LinearGradient(
                                        colors: [theme.colorScheme.primary, Colors.white],
                                      ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Configure your journey details', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),

                        const Text('Navigation Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 16),

                        // Flyover Option Glass Card
                        _buildGlassCard(
                          theme,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.secondary.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.flight_takeoff_rounded, color: theme.colorScheme.secondary, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Flyover Instructions', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Choose how you want to be notified when approaching a flyover or underpass.',
                                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                ),
                                child: Column(
                                  children: [
                                    RadioListTile<bool>(
                                      title: const Text('Vibration', style: TextStyle(color: Colors.white, fontSize: 14)),
                                      value: true,
                                      groupValue: _useHardware,
                                      activeColor: theme.colorScheme.primary,
                                      onChanged: (val) => _toggleSetting(val!),
                                    ),
                                    Divider(color: Colors.white.withOpacity(0.05), height: 1),
                                    RadioListTile<bool>(
                                      title: const Text('Play Mobile Notification Sound', style: TextStyle(color: Colors.white, fontSize: 14)),
                                      value: false,
                                      groupValue: _useHardware,
                                      activeColor: theme.colorScheme.primary,
                                      onChanged: (val) => _toggleSetting(val!),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_useHardware) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _playDemo,
                                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                                  label: const Text('Play Sample Alert'),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    backgroundColor: theme.colorScheme.secondary.withOpacity(0.2),
                                    foregroundColor: theme.colorScheme.secondary,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        const Text('Vibration Test', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 16),
                        
                        _buildGlassCard(
                          theme,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.vibration, color: theme.colorScheme.primary, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Test Haptic Signals', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Send test signals directly to the connected ESP32 hardware to verify vibration functionality. Ensure app is connected.',
                                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              
                              widget.bleService?.isConnected == true
                               ? Column(
                                   children: [
                                     Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                       children: [
                                         _buildTestButton('l1', 'l1', theme),
                                         _buildTestButton('l2', 'l2', theme),
                                         _buildTestButton('l3', 'l3', theme),
                                       ],
                                     ),
                                     const SizedBox(height: 12),
                                     Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                       children: [
                                         _buildTestButton('r1', 'r1', theme),
                                         _buildTestButton('r2', 'r2', theme),
                                         _buildTestButton('r3', 'r3', theme),
                                       ],
                                     ),
                                     const SizedBox(height: 12),
                                     Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                       children: [
                                         _buildTestButton('f1', 'f1', theme),
                                         _buildTestButton('f2', 'f2', theme),
                                         _buildTestButton('f3', 'f3', theme),
                                       ],
                                     ),
                                     const SizedBox(height: 12),
                                     Row(
                                       mainAxisAlignment: MainAxisAlignment.center,
                                       children: [
                                         _buildTestButton('u', 'u', theme),
                                       ],
                                     ),
                                   ],
                                 )
                               : Container(
                                   padding: const EdgeInsets.all(16),
                                   decoration: BoxDecoration(
                                     color: Colors.white.withOpacity(0.05),
                                     borderRadius: BorderRadius.circular(16),
                                   ),
                                   child: const Center(
                                     child: Text(
                                       'Device not connected. Connect from Setup screen to test vibrations.',
                                       style: TextStyle(color: Colors.white70, fontSize: 13),
                                       textAlign: TextAlign.center,
                                     ),
                                   ),
                                 ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(String label, String signal, ThemeData theme) {
    return ElevatedButton(
      onPressed: () async {
        if (widget.bleService != null) {
          await widget.bleService!.sendStringSignal(signal);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Test Signal Sent: $signal', style: const TextStyle(fontWeight: FontWeight.bold)),
                duration: const Duration(milliseconds: 500),
                backgroundColor: theme.colorScheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.1),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(80, 48),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGlassCard(ThemeData theme, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardTheme.color?.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}
