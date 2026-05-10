/// Pure Dart text parser for Google Maps turn instructions.
/// No platform dependencies — fully unit-testable.
library;

enum TurnAction {
  turnLeft,
  turnRight,
  straight,
  uTurn,
  arrive,
  flyover,
  ignore,
}

class ParseResult {
  final TurnAction action;
  final int signal;
  final String originalText;

  const ParseResult({
    required this.action,
    required this.signal,
    required this.originalText,
  });

  @override
  String toString() =>
      'ParseResult(action: ${action.name}, signal: $signal, text: "$originalText")';
}

class TurnParser {
  // Keywords that override a detection to IGNORE (false-positive filter)
  static const _exclusionKeywords = ['merge', 'fork', 'keep', 'exit'];

  static const _flyoverKeywords = [
    'flyover',
    'overpass',
    'bridge',
    'ramp',
    'underpass',
    'tunnel',
    'slip road'
  ];

  // Ordered list so u-turn is checked before generic left/right
  static const _actionKeywords = <String, TurnAction>{
    'u-turn': TurnAction.uTurn,
    'u turn': TurnAction.uTurn,
    'arrive': TurnAction.arrive,
    'arrived': TurnAction.arrive,
    'destination': TurnAction.arrive,
    'left': TurnAction.turnLeft,
    'right': TurnAction.turnRight,
    'straight': TurnAction.straight,
    'continue': TurnAction.straight,
    'head': TurnAction.straight,
  };

  static const _signalMap = <TurnAction, int>{
    TurnAction.turnLeft: 1,
    TurnAction.turnRight: 2,
    TurnAction.straight: 0,
    TurnAction.uTurn: 3,
    TurnAction.arrive: 3,
    TurnAction.flyover: 4,
    TurnAction.ignore: 0,
  };

  /// Parse a notification text and return the detected action + signal.
  static ParseResult parse(String text) {
    final lower = text.toLowerCase();

    for (final keyword in _flyoverKeywords) {
      if (lower.contains(keyword)) {
        return ParseResult(
          action: TurnAction.flyover,
          signal: 4,
          originalText: text,
        );
      }
    }

    // Check exclusion keywords first
    for (final exclusion in _exclusionKeywords) {
      if (lower.contains(exclusion)) {
        print('🔍 Parsed: "$text" → Signal: 0 (excluded by "$exclusion")');
        return ParseResult(
          action: TurnAction.ignore,
          signal: 0,
          originalText: text,
        );
      }
    }

    // Check action keywords (u-turn checked before left/right)
    for (final entry in _actionKeywords.entries) {
      if (lower.contains(entry.key)) {
        final action = entry.value;
        final signal = _signalMap[action]!;
        print('🔍 Parsed: "$text" → ${action.name} → Signal: $signal');
        return ParseResult(
          action: action,
          signal: signal,
          originalText: text,
        );
      }
    }

    // No match
    print('🔍 Parsed: "$text" → Signal: 0 (no match)');
    return ParseResult(
      action: TurnAction.ignore,
      signal: 0,
      originalText: text,
    );
  }

  /// Human-readable label for a signal value.
  static String signalLabel(int signal) {
    switch (signal) {
      case 1:
        return 'Turn LEFT';
      case 2:
        return 'Turn RIGHT';
      case 3:
        return 'ALERT (U-turn / Arrive)';
      case 4:
        return 'FLYOVER ALERT';
      default:
        return 'No vibration';
    }
  }
}
