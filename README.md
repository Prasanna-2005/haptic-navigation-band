# Smart Nav - Project Documentation

## Overview
**Smart Nav** is a **proof-of-concept navigation experimentation app** that simulates navigation instructions via Android Notification Listener Service and communicates with ESP32 microcontrollers via Bluetooth. The app captures turn-by-turn instructions from Google Maps notifications and provides **real-time vibration feedback** patterns to guide directional navigation for accessibility.

> ⚠️ **Status:** SCRAPPING/TESTING PROJECT — No direct Google Maps API integration. Uses platform-specific notification parsing for development and prototyping.

**Version:** 1.0.0  
**Platform:** Flutter (Cross-platform iOS & Android - Android primary)  
**SDK:** Dart 3.11.1+

---

## Key Features

### 🗺️ Real-Time Navigation
- **Notification Listener Service** intercepts Google Maps notifications
- Parses turn instructions from notification text (not API)
- Live turn-by-turn instruction extraction from system notifications
- Navigation instruction history tracking
- Error handling and state recovery

### 📱 Bluetooth Integration
- ESP32 device connectivity for haptic feedback control
- Real-time vibration signal transmission
- Device discovery and pairing
- Connection state management
- Test signal verification

### 🔊 Vibration & Haptic Feedback
- **Multi-signal vibration patterns** (0-4 signal codes)
- Distance-layer based signaling (Far/Medium/Near)
- Direction-specific patterns (Left/Right/U-Turn/Flyover)
- Audio playback for notifications
- Persistent settings storage (Shared Preferences)

### 🎨 Modern UI/UX
- Dark-themed cyberpunk design
- Material 3 design system
- Responsive screen layouts
- Google Fonts (Outfit typeface)

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter |
| **Language** | Dart |
| **Architecture** | MVVM (Model-View-ViewModel) |
| **Bluetooth** | flutter_blue_plus (2.2.1) |
| **Notifications** | notification_listener_service (0.3.5) |
| **Audio** | audioplayers (6.6.0) |
| **Permissions** | permission_handler (12.0.1) |
| **Storage** | shared_preferences (2.5.5) |
| **Fonts** | google_fonts (8.0.2) |

---

## Project Structure

```
lib/
├── main.dart                          # App entry point & theme configuration
├── models/
│   └── navigation_models.dart        # Data models for navigation
├── screens/
│   ├── setup_screen.dart             # Initial setup/onboarding
│   ├── navigation_screen.dart        # Main navigation display
│   ├── ready_screen.dart             # Pre-navigation readiness check
│   └── settings_screen.dart          # App settings & preferences
└── services/
    ├── bluetooth_service.dart        # BLE device management
    ├── navigation_bluetooth_service.dart # Navigation-specific BLE logic
    ├── maps_accessibility_service.dart  # Google Maps integration
    ├── notification_service.dart     # System notification handling
    └── turn_parser.dart              # Navigation instruction parsing

android/                              # Android-specific configuration
web/                                  # Web platform assets
test/                                 # Unit & widget tests
```

---

## Core Components

### 1. **Screens**
- **SetupScreen**: Initial device pairing and app configuration
- **NavigationScreen**: Displays real-time navigation info and instructions
- **ReadyScreen**: Confirms device connectivity before navigation starts
- **SettingsScreen**: User preferences and app configuration

### 2. **Services**

#### BluetoothService
- Device discovery and connection
- Real-time data transmission to ESP32
- Connection state management

#### NavigationBluetoothService
- Bridges navigation data with Bluetooth transmission
- Formats and sends instructions to devices

#### MapsAccessibilityService
- Retrieves navigation data from Google Maps
- Parses turn-by-turn instructions
- Handles route updates

#### TurnParser
- Processes navigation instructions
- Extracts distance, direction, and action data

### 3. **Models**
- `NavigationInstruction`: Represents a single navigation turn
- Related data structures for route and direction information

---

## Vibration & Haptic Feedback System

### Signal Architecture

The Smart Nav system uses a **discrete signal-based communication protocol** to control ESP32 haptic motors. Each signal corresponds to a specific navigation instruction.

#### Signal Code Mapping

| Signal | Value | Action | ESP32 Behavior | Use Case |
|--------|-------|--------|-----------------|----------|
| **No Vibration** | 0 | Straight/Continue | Motors off | Going straight, no turn |
| **Turn LEFT** | 1 | Left Turn | Left motor pulse | Turn left instruction detected |
| **Turn RIGHT** | 2 | Right Turn | Right motor pulse | Turn right instruction detected |
| **ALERT** | 3 | U-Turn / Arrive | Both motors rapid pulse | Critical actions (destination, reverse direction) |
| **FLYOVER** | 4 | Overpass/Bridge | Special pattern (3x pulse) | Navigate elevated structures safely |

### Distance-Layer Signaling Strategy

The system sends directional signals based on distance to the upcoming turn, implementing a **three-layer proximity system**:

```
Turn Instruction at 2km ahead
        ↓
    Layer 1: Far (> 500m)
    ├─ Signal sent: "L1" or "R1"
    ├─ Purpose: Advance warning
    └─ Flags: _hasSentL1Signal = true
        ↓
    Layer 2: Medium (100-250m)
    ├─ Signal sent: "L2" or "R2"
    ├─ Purpose: Prepare for turn
    └─ Flags: _hasSentL2Signal = true
        ↓
    Layer 3: Near (< 100m)
    ├─ Signal sent: "L3" or "R3"
    ├─ Purpose: Immediate action required
    └─ Flags: _hasSentL3Signal = true
        ↓
    Turn Completed → Flags Reset
```

### Vibration Pattern Examples

#### Pattern 1: LEFT TURN (Signal 1)
```
Timeline: 0ms ─────────────────────────────── 500ms
Action:   LEFT ▌▌▌ (vibrate) ▌▌▌ (vibrate)  STOP
Duration: 100ms on, 100ms off, 100ms on
Effect:   Distinctive left-side pulsation
```

#### Pattern 2: RIGHT TURN (Signal 2)
```
Timeline: 0ms ─────────────────────────────── 500ms
Action:   RIGHT ▌▌▌ (vibrate) ▌▌▌ (vibrate)  STOP
Duration: 100ms on, 100ms off, 100ms on
Effect:   Distinctive right-side pulsation
```

#### Pattern 3: ALERT - U-TURN / ARRIVE (Signal 3)
```
Timeline: 0ms ─────────────────────────────────────────── 800ms
Action:   BOTH ▌▌ ▌▌ ▌▌ ▌▌ ▌▌ (rapid pulse)  STOP
Duration: 50ms on, 50ms off (repeated 5x)
Effect:   Urgent, rapid bilateral vibration
```

#### Pattern 4: FLYOVER / OVERPASS (Signal 4)
```
Timeline: 0ms ──────────────────────────────────── 600ms
Action:   BOTH ▌▌▌ (3x long pulse)  STOP
Duration: 150ms on, 200ms off, 150ms on, 200ms off, 150ms on
Effect:   Three distinct double-pulses for structural awareness
```

### Direction-based Vibration Mapping

```dart
// Turn Parser maps text instructions to signals
"Turn left" or "Bear left slightly"     → Signal 1 (Turn LEFT)
"Turn right" or "Bear right slightly"   → Signal 2 (Turn RIGHT)
"Go straight" or "Continue ahead"       → Signal 0 (No vibration)
"U-turn" or "Make a U-turn"            → Signal 3 (ALERT)
"You have arrived"                      → Signal 3 (ALERT)
"Flyover" or "Take the overpass"       → Signal 4 (FLYOVER)
"Merge" or "Fork" or "Exit"           → Signal 0 (Excluded)
```

### Signal Sending Flow

```
Navigation Instruction Received
        ↓
Parse text via TurnParser
        ├─ Extract: action (left/right/u-turn/arrive/flyover)
        └─ Map to: signal (0-4)
        ↓
NavigationBluetoothService processes instruction
        ├─ Parse distance from instruction text (e.g., "250 m")
        ├─ Determine layer (L1 if > 500m, L2 if 100-250m, L3 if < 100m)
        └─ One-time trigger: Check if signal already sent for this turn
        ↓
Format as string: "L1", "L2", "L3", "R1", "R2", "R3", etc.
        ↓
BLE Service sends via Bluetooth
        ├─ UTF-8 encode signal string
        ├─ Write to ESP32 characteristic
        └─ Receive acknowledgment
        ↓
ESP32 Motor Controller
        ├─ Decode signal command
        ├─ Activate left/right/both motors
        ├─ Execute vibration pattern
        └─ Send back confirmation byte
        ↓
User feels haptic guidance
```

### One-Time-Trigger Constraint

Each signal per turn is sent **exactly once** to prevent duplicate vibrations:

```dart
// State tracking flags
bool _hasSentL1Signal = false;   // Far layer (> 500m)
bool _hasSentL2Signal = false;   // Medium layer (100-250m)
bool _hasSentL3Signal = false;   // Near layer (< 100m)
String? _currentDirection;       // "left" or "right"

// Reset logic: When new turn detected (direction changes)
if (direction != _currentDirection) {
    _currentDirection = direction;
    _hasSentL1Signal = false;    // ← Reset all flags
    _hasSentL2Signal = false;
    _hasSentL3Signal = false;
}

// Send constraint: Only send if flag is false
if (!_hasSentL1Signal && distance > 500) {
    await _sendBluetoothSignal("L1");
    _hasSentL1Signal = true;     // ← Lock this layer
}
```

### Parsing & Signal Detection

The **TurnParser** service uses keyword matching to detect navigation actions:

```dart
// Keyword-based detection
static const _flyoverKeywords = ['flyover', 'overpass', 'bridge'];
static const _actionKeywords = {
    'u-turn': TurnAction.uTurn,
    'u turn': TurnAction.uTurn,
    'arrive': TurnAction.arrive,
    'left': TurnAction.turnLeft,
    'right': TurnAction.turnRight,
    'straight': TurnAction.straight,
};

// Exclusion keywords (filtered out)
static const _exclusionKeywords = ['merge', 'fork', 'keep', 'exit'];

// Example parsing
"Turn right onto Main Street" 
    → Contains 'right'
    → Signal 2 (Turn RIGHT)
    → L1, L2, or L3 based on distance
```

### Bluetooth Signal Transmission

```dart
// String signal format: "{direction}{layer}"
// Examples: "L1", "R2", "L3" (for directional layers)
//           "-1"             (for skipping)
//           "A"              (for test signal)

Future<bool> sendStringSignal(String signal) async {
    final bytes = Uint8List.fromList(signal.codeUnits);  // UTF-8 encode
    return await _writeCharacteristic!.write(
        bytes,
        withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
    );
}

// Single example: Sending "L2" (Left turn, medium distance)
await bleService.sendStringSignal("L2");
// Bytes transmitted: [0x4C, 0x32] (ASCII codes for 'L', '2')
// ESP32 receives and activates: Left motor, medium intensity pulse
```

### Testing Vibration Patterns

The app includes unit tests for signal parsing:

```dart
// Turn Parser Tests
test('Parse "Turn left" → Signal 1', () {
    final result = TurnParser.parse("Turn left onto Oak Street");
    expect(result.signal, 1);
    expect(result.action, TurnAction.turnLeft);
});

test('Parse flyover → Signal 4', () {
    final result = TurnParser.parse("Take the flyover ahead");
    expect(result.signal, 4);
    expect(result.action, TurnAction.flyover);
});

test('Signal label mapping', () {
    expect(TurnParser.signalLabel(1), 'Turn LEFT');
    expect(TurnParser.signalLabel(2), 'Turn RIGHT');
    expect(TurnParser.signalLabel(3), 'ALERT (U-turn / Arrive)');
    expect(TurnParser.signalLabel(4), 'FLYOVER ALERT');
});
```

### User Settings: Vibration Control

Users can manage vibration preferences in **SettingsScreen**:

```dart
// Toggle vibration on/off
SharedPreferences prefs = await SharedPreferences.getInstance();
prefs.setBool('vibrationEnabled', true);
prefs.setInt('vibrationIntensity', 75);  // 0-100%
prefs.setInt('vibrationDuration', 500);  // milliseconds

// Retrieve settings
bool vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
int intensity = prefs.getInt('vibrationIntensity') ?? 75;
```

---

## Notification Listener Service (Android)

### How It Works

Instead of direct Google Maps API calls, Smart Nav uses **Android's NotificationListenerService** to intercept navigation notifications:

#### Android Platform Channel Architecture

```
Android NotificationListenerService
    ↓
Listens to: com.google.android.apps.maps (Google Maps package)
    ├─ Notification Title: "Navigation"
    ├─ Notification Text: "Turn right onto 5th Avenue"
    └─ Extract & parse text
    ↓
MethodChannel: "com.ridernav.rider_nav/maps"
    ├─ Check if listener is enabled
    └─ Request system settings if disabled
    ↓
EventChannel: "com.ridernav.rider_nav/navigation_events"
    ├─ Stream navigation events to Flutter
    └─ Emit as NavigationEvent objects
    ↓
Flutter MapsAccessibilityService receives stream
    ├─ Parse instruction text
    ├─ Extract distance, direction, road name
    └─ Create NavigationInstruction model
    ↓
NavigationBluetoothService acts on instruction
    ├─ Send vibration signal to ESP32
    └─ Update UI
```

#### EventChannel Stream Format

```dart
// Raw event from Android platform
{
    "timestamp": 1650000000,
    "text": "Turn right onto Main Street, 250 m",
    "title": "Navigation",
    "package": "com.google.android.apps.maps"
}

// Parsed into NavigationEvent
class NavigationEvent {
    final NavigationInstruction? instruction;
    final DateTime timestamp;
    final String rawText;
    
    NavigationEvent.fromMap(Map<dynamic, dynamic> map) {
        instruction = _parseInstruction(map['text']);
        timestamp = DateTime.now();
        rawText = map['text'];
    }
}
```

### Permission Requirements (Android)

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" />

<!-- In SetupScreen: User must manually enable -->
Settings > Notifications > Special App Access > Notification Access
    ↓
Enable: Smart Nav
```

---

## Design System

#### BLE Stack Overview
```
┌─────────────────────────────────────────────────────┐
│         Smart Nav Application (Flutter)             │
└────────────────┬────────────────────────────────────┘
                 │
         ┌───────▼────────┐
         │ flutter_blue_  │  GATT Protocol
         │     plus       │  (Generic Attribute)
         └───────┬────────┘
                 │
         ┌───────▼──────────────┐
         │   BLE Radio Stack    │  Core BLE Link Layer
         │   (HCI Interface)    │  Encryption & Pairing
         └───────┬──────────────┘
                 │
         ┌───────▼────────┐
         │    ESP32       │  Bluetooth 5.0 LE
         │  Microcontroller│  
         └────────────────┘
```

#### Connection Flow
1. **Device Discovery**: Scan for GATT services and characteristics
2. **Pairing**: Establish encrypted connection (PIN-based or Just Works)
3. **Service Resolution**: Locate navigation-specific UUIDs
4. **Characteristic Mapping**: Identify read/write/notify properties
5. **Real-time Communication**: Bidirectional data streaming

#### Data Packet Format
```dart
// Navigation Instruction Packet sent to ESP32
{
  "type": "TURN_INSTRUCTION",
  "distance": 250.5,              // meters
  "unit": "METERS",
  "direction": "TURN_RIGHT",      // Enum: TURN_LEFT, TURN_RIGHT, GO_STRAIGHT, etc.
  "roadName": "Main Street",
  "maneuverType": 4,              // Google Maps maneuver enum
  "junctionType": 2,              // Roundabout, fork, etc.
  "timestamp": 1650000000,        // Unix timestamp
  "confidence": 0.95              // 0.0-1.0 confidence score
}
```

#### Bluetooth Connection Management
- **MTU Negotiation**: Automatic negotiation of Maximum Transmission Unit (default 20 bytes)
- **Retry Logic**: Exponential backoff (1s, 2s, 4s, 8s) for failed connections
- **Connection Timeout**: 30-second timeout for unresponsive devices
- **Multi-packet Handling**: Large instructions split across multiple BLE packets
- **CRC Validation**: Checksum verification for data integrity

#### Error Recovery
```
Connection Lost
    ↓
Try Reconnect (immediate)
    ├─ Success → Resume
    └─ Fail (5 retries)
         ↓
    Signal Loss Detection
         ↓
    Notify User & Clear State
         ↓
    Reset to Ready Screen
```

---

### 2. Data Flow Architecture (Event-Driven)

#### Navigation Pipeline
```
Google Maps API
    ↓
MapsAccessibilityService.getNavigationUpdates()
    ├─ Parse raw instruction data
    ├─ Extract: distance, direction, road name
    └─ Emit: NavigationInstruction event
    
    ↓
NavigationScreen (listens to service Stream)
    ├─ Update UI with current instruction
    ├─ Add to instruction history
    └─ Trigger tone/haptic feedback
    
    ↓
NavigationBluetoothService (listens to instruction updates)
    ├─ Format instruction for ESP32
    ├─ Serialize to JSON/Binary
    └─ Send via BLE
    
    ↓
ESP32 Microcontroller
    ├─ Parse incoming data
    ├─ Control haptic motors/LEDs
    └─ Send acknowledgment back
```

#### Stream-based State Management
```dart
// Observable Streams in Services
class MapsAccessibilityService {
  Stream<NavigationInstruction> get instructionStream => _instructionController.stream;
  Stream<ConnectionState> get connectionStream => _connectionController.stream;
  Stream<RouteProgress> get progressStream => _progressController.stream;
}

// Listeners in UI layer
navigationService.instructionStream.listen((instruction) {
  setState(() => _currentInstruction = instruction);
  _playAudioCue(instruction.direction);
});
```

---

### 3. State Management

#### Widget State Hierarchy
```
SmartNavApp (root theme provider)
    └── SetupScreen (device pairing state)
         └── NavigationScreen (active navigation state)
              ├── BLE connection state
              ├── Current instruction state
              ├── Route progress state
              └── Error/notification state
```

#### State Variables & Their Lifecycle
| State | Type | Scope | Persistence |
|-------|------|-------|-------------|
| Current Instruction | NavigationInstruction | Screen | Session only |
| Instruction History | List<NavigationInstruction> | Screen | Session + SharedPrefs |
| BLE Connection | BluetoothConnection | Service | Until disconnect |
| Device Address | String | Service | SharedPrefs (saved device) |
| User Settings | Map<String, dynamic> | App | SharedPrefs (persistent) |
| Navigation Active | bool | Screen | Session only |
| Error State | String? | Screen | Session only |

---

### 4. Google Maps Integration

#### Accessibility Service API Usage
```dart
// Initializing the accessibility service
final mapsService = MapsAccessibilityService();
await mapsService.initialize(apiKey: googleMapsApiKey);

// Requesting navigation data
Future<NavigationData> startNavigation(
  LatLng origin,
  LatLng destination,
  TravelMode travelMode,
) async {
  // Makes HTTP request to Google Maps Directions API
  // Returns: polylines, waypoints, and structured turn-by-turn instructions
}

// Real-time location updates trigger instruction changes
onLocationUpdate(LatLng currentLocation) {
  if (distanceToNextWaypoint < 50) {
    emitNextInstruction();
  }
}
```

#### Turn Parsing Logic
```dart
// Raw Google Maps Instruction:
{
  "text": "Turn right onto Main Street",
  "maneuver": "turn-right",
  "distance": { "text": "250 m", "value": 250.5 },
  "duration": { "text": "3 mins", "value": 180 }
}

// Parsed NavigationInstruction object:
NavigationInstruction(
  distance: 250.5,
  direction: Direction.turnRight,
  roadName: "Main Street",
  estimatedTime: Duration(seconds: 180),
  type: ManeuverType.turnRight,
)
```

---

### 5. Navigation Data Structures

#### Core Models
```dart
class NavigationInstruction {
  final String id;                    // Unique identifier
  final double distance;              // Meters
  final Direction direction;          // Enum
  final String roadName;              // Street name
  final ManeuverType maneuverType;   // Turn type
  final Duration estimatedTime;       // ETA
  final LatLng waypoint;             // GPS coordinates
  final DateTime timestamp;           // When instruction was issued
  final double confidence;            // 0.0-1.0
  
  bool get isCritical => distance < 50 && distance > 0;
  bool get isUpcoming => distance >= 50 && distance < 500;
}

enum Direction {
  goStraight,
  turnLeft,
  turnRight,
  turnLeftSlight,
  turnRightSlight,
  uTurn,
  exit,
  ramp,
}

enum ManeuverType {
  turn,
  ramp,
  merge,
  fork,
  roundabout,
  exit,
  depart,
  arrive,
}
```

#### Route Progress Tracking
```dart
class RouteProgress {
  final int totalSteps;
  final int completedSteps;
  final double totalDistance;
  final double remainingDistance;
  final Duration remainingTime;
  final double progressPercentage;
  
  RouteProgress({...});
  
  double get completion => completedSteps / totalSteps;
}
```

---

### 6. Error Handling & Resilience

#### Exception Hierarchy
```dart
abstract class SmartNavException implements Exception {
  String get message;
}

class BluetoothException extends SmartNavException {
  // Device not found, connection refused, timeout
}

class LocationException extends SmartNavException {
  // GPS unavailable, permission denied
}

class NavigationException extends SmartNavException {
  // Route calculation failed, invalid coordinates
}

class StorageException extends SmartNavException {
  // Failed to read/write preferences
}
```

#### Error Recovery Strategies
```
Bluetooth Connection Lost
├─ Attempt automatic reconnect (3 retries with exponential backoff)
├─ If failed: Show "Device Disconnected" error
└─ User action: Manually reconnect from ready screen

GPS Signal Lost
├─ Use last known location (cached for 30 seconds)
├─ Show "Low Signal" warning
└─ Resume when signal restored

Route Calculation Error
├─ Retry with same coordinates
├─ If failed: Try alternate routing service
└─ Fallback: Use manual navigation mode

Null/Invalid Data
├─ Validate before parsing
├─ Log error details
└─ Emit safe default or null instruction
```

#### Logging & Debugging
```dart
// Debug-level logging for development
debugPrint('BLE: Connecting to ESP32 (${device.remoteId})');
debugPrint('NAV: Parsed instruction - Turn ${instruction.direction}');

// Error logging for crash reporting
try {
  await bleService.connect(device);
} catch (e, stackTrace) {
  logError('BLE Connection Failed', e, stackTrace);
  reportToCrashlytics(e, stackTrace);
}
```

---

### 7. Performance Considerations

#### Memory Optimization
- **Instruction History**: Limited to last 50 instructions in memory
- **Image Caching**: Google Fonts cached after first load
- **BLE Buffers**: 256KB allocation for incoming data streams
- **Stream Listeners**: Properly disposed in `dispose()` to prevent memory leaks

#### Battery & Network
- **BLE Advertising**: Scan duration limited to 30 seconds
- **GPS Polling**: Update interval 5-10 seconds (configurable)
- **API Calls**: Cached for 60 seconds to reduce redundant requests
- **Background Tasks**: Notification listener runs as low-priority service

#### UI Responsiveness
- **Async Operations**: All network/BLE operations run on isolate threads
- **Frame Rate**: Maintained 60 FPS using efficient re-renders
- **Animation**: GPU-accelerated transitions with `ImplicitlyAnimatedWidget`

---

### 8. Threading & Concurrency

#### Dart Concurrency Model
```dart
// Navigation updates run on separate event loop
Future<void> _streamNavigationUpdates() async {
  // This runs without blocking UI thread
  await for (var instruction in navigationStream) {
    // Update state triggers rebuild
    setState(() => _currentInstruction = instruction);
  }
}

// Isolate-heavy operations (BLE, GPS)
Future<List<BluetoothDevice>> _scanDevices() async {
  return compute(_performScan, _);  // Run on isolate thread pool
}

// Stream subscriptions (non-blocking)
StreamSubscription subscription = bleService.connectionStream.listen(
  (state) { /* handle state change */ },
  onError: (error) { /* handle error */ },
  onDone: () { /* cleanup */ },
);
```

#### Race Condition Prevention
- **Instruction Updates**: Only latest instruction processed (old ones discarded)
- **Connection State**: Atomic operations prevent concurrent connect/disconnect
- **Settings Persistence**: SharedPreferences handles concurrent read/write safely

---

## Design System

### Color Palette
| Purpose | Color | Hex |
|---------|-------|-----|
| Primary | Cyber Cyan | #00E5FF |
| Secondary | Neon Purple | #B026FF |
| Surface | Glass Card Base | #131A2A |
| Background | Deep Space | #070B14 |
| Error | Laser Red | #FF2A55 |
| Text | Light Gray | #E2E8F0 |

### Typography
- Font Family: Outfit (Google Fonts)
- Responsive text scaling
- Material 3 text hierarchy

---

## Getting Started

### Prerequisites
- Flutter SDK (3.11.1 or later)
- Android SDK / iOS SDK
- Xcode (for iOS) / Android Studio (for Android)

### Installation

1. **Clone & Setup**
   ```bash
   flutter pub get
   ```

2. **Android-Specific Setup**
   - Install Android SDK 30+
   - Enable Bluetooth permissions in `AndroidManifest.xml`
   - Ensure `build.gradle` includes Kotlin plugin

3. **Run the App**
   ```bash
   flutter run
   ```

4. **First-Time Setup**
   - App will prompt to enable Notification Listener Service
   - Go to: Settings > Notifications > Special App Access > Notification Access
   - Toggle ON: "Smart Nav"
   - Grant Bluetooth permissions when prompted

5. **Pair ESP32 Device**
   - Open Smart Nav
   - Go to Setup Screen
   - Scan for available Bluetooth devices
   - Select your ESP32 and pair (default PIN: usually "1234" or "0000")
   - Connection test signal will be sent to verify link

6. **Test Navigation**
   - Open Google Maps and start navigation
   - Smart Nav will automatically capture turn instructions
   - Feel vibration patterns on paired ESP32 device

7. **Build Production**
   ```bash
   flutter build apk        # Android
   flutter build ios        # iOS (limited)
   ```

### Permissions Required
- **Bluetooth**: Connect & Scan (Android 6+)
- **Notification Access**: Special system permission (Android 5+)
- **Location** (optional): For manual GPS verification

---

## Testing

The project includes unit tests and widget tests:

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/navigation_bluetooth_service_test.dart
```

### Test Files
- `widget_test.dart` - UI widget tests
- `navigation_bluetooth_service_test.dart` - Service logic tests
- `turn_parser_test.dart` - Navigation parsing tests

---

## Configuration

### theme.dart
The app uses a custom dark theme with cyberpunk aesthetics:
- Custom color scheme
- Card styling with glassmorphism effects
- Material 3 components

### shared_preferences
Persistent storage for:
- User settings
- Bluetooth device preferences
- Navigation history
- UI preferences

---

## Build & Deployment

### Android Build
- Gradle-based build system (Kotlin DSL)
- Target SDK: Latest
- Native plugin compilation via JNI

### iOS Build
- Swift/Objective-C integration
- CocoaPods dependency management

---

## Documentation Files

Detailed implementation docs available in `MDS/`:
- `IMPLEMENTATION_SUMMARY.md` - Technical implementation details
- `BLUETOOTH_IMPLEMENTATION.md` - BLE protocol specifications
- `NAVIGATION_GUIDE.md` - Navigation flow documentation
- `PRACTICAL_EXAMPLE.md` - Usage examples

---

## Dependencies Overview

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_blue_plus | 2.2.1 | Bluetooth LE communication |
| permission_handler | 12.0.1 | Runtime permission management |
| google_fonts | 8.0.2 | Typography styling |
| shared_preferences | 2.5.5 | Local data persistence |
| audioplayers | 6.6.0 | Audio playback |
| notification_listener_service | 0.3.5 | System notification access |

---

## Future Enhancements

- [ ] Offline map support
- [ ] Multiple device pairing
- [ ] Analytics tracking
- [ ] Cloud sync for preferences
- [ ] Voice command integration
- [ ] Route favoriting system

---

## Support & Maintenance

For bugs, feature requests, or technical questions, refer to the detailed documentation in the `MDS/` folder.

---

**Last Updated:** April 2026  
**Status:** Active Development
