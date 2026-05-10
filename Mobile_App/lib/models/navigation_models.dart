/// Data models for navigation instructions and events.
library navigation_models;

import 'package:flutter/foundation.dart';

/// Represents a direction instruction type
enum DirectionType {
  turnLeft,
  turnRight,
  sharpLeft,
  sharpRight,
  slightLeft,
  slightRight,
  uTurn,
  continueStraight,
  headForward,
  arrive,
  unknown,
}

/// Represents a heading direction
enum HeadingType {
  north,
  south,
  east,
  west,
  northeast,
  northwest,
  southeast,
  southwest,
  none,
}

/// Structured navigation instruction received from Google Maps
class NavigationInstruction {
  /// Type of turn/direction
  final DirectionType direction;

  /// Cardinal heading if available (North, South, etc.)
  final HeadingType heading;

  /// Distance to travel (e.g., "200 m")
  final String? distance;

  /// Raw instruction text from notification
  final String instruction;

  /// Full text from notification
  final String fullText;

  /// Timestamp when instruction was received
  final DateTime timestamp;

  /// Additional raw data from notification
  final Map<String, dynamic> rawData;

  NavigationInstruction({
    required this.direction,
    this.heading = HeadingType.none,
    this.distance,
    required this.instruction,
    required this.fullText,
    required this.timestamp,
    Map<String, dynamic>? rawData,
  }) : rawData = rawData ?? {};

  /// Get human-readable direction label
  String get directionLabel {
    switch (direction) {
      case DirectionType.turnLeft:
        return 'Turn Left';
      case DirectionType.turnRight:
        return 'Turn Right';
      case DirectionType.sharpLeft:
        return 'Sharp Left';
      case DirectionType.sharpRight:
        return 'Sharp Right';
      case DirectionType.slightLeft:
        return 'Slight Left';
      case DirectionType.slightRight:
        return 'Slight Right';
      case DirectionType.uTurn:
        return 'U-Turn';
      case DirectionType.continueStraight:
        return 'Continue Straight';
      case DirectionType.headForward:
        return 'Head Forward';
      case DirectionType.arrive:
        return 'Destination Reached';
      case DirectionType.unknown:
        return 'Unknown';
    }
  }

  /// Get human-readable heading label
  String get headingLabel {
    switch (heading) {
      case HeadingType.north:
        return 'North';
      case HeadingType.south:
        return 'South';
      case HeadingType.east:
        return 'East';
      case HeadingType.west:
        return 'West';
      case HeadingType.northeast:
        return 'Northeast';
      case HeadingType.northwest:
        return 'Northwest';
      case HeadingType.southeast:
        return 'Southeast';
      case HeadingType.southwest:
        return 'Southwest';
      case HeadingType.none:
        return '';
    }
  }

  /// Format instruction with optional heading and distance
  String get formattedInstruction {
    final parts = <String>[directionLabel];

    if (heading != HeadingType.none) {
      parts.add(headingLabel);
    }

    if (distance != null && distance!.isNotEmpty) {
      parts.add('for ${distance!}');
    }

    return parts.join(' ');
  }

  /// Create from notification event map (from Android)
  factory NavigationInstruction.fromMap(Map<dynamic, dynamic> map) {
    return NavigationInstruction(
      direction: _parseDirectionType(map['direction'] as String?),
      heading: _parseHeadingType(map['heading'] as String?),
      distance: map['distance'] as String?,
      instruction: map['instruction'] as String? ?? '',
      fullText: map['fullText'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      rawData: Map<String, dynamic>.from(map as Map<dynamic, dynamic>),
    );
  }

  /// Convert to map for storage/serialization
  Map<String, dynamic> toMap() => {
        'direction': direction.name,
        'heading': heading.name,
        'distance': distance,
        'instruction': instruction,
        'fullText': fullText,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  @override
  String toString() => 'NavigationInstruction('
      'direction: $directionLabel, '
      'heading: $headingLabel, '
      'distance: $distance, '
      'instruction: "$instruction")';
}

/// Navigation event from the system
class NavigationEvent {
  /// Type of event
  final String type; // 'navigation_update', 'navigation_end', 'error'

  /// Associated instruction if type is 'navigation_update'
  final NavigationInstruction? instruction;

  /// Timestamp
  final DateTime timestamp;

  /// Additional metadata
  final Map<String, dynamic> metadata;

  NavigationEvent({
    required this.type,
    this.instruction,
    required this.timestamp,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  factory NavigationEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String? ?? 'unknown';
    final instruction = type == 'navigation_update'
        ? NavigationInstruction.fromMap(map)
        : null;

    return NavigationEvent(
      type: type,
      instruction: instruction,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      metadata: Map<String, dynamic>.from(map as Map<dynamic, dynamic>),
    );
  }

  @override
  String toString() => 'NavigationEvent(type: $type, '
      'instruction: $instruction, '
      'timestamp: $timestamp)';
}

/// Parse direction type from string
DirectionType _parseDirectionType(String? value) {
  if (value == null) return DirectionType.unknown;
  return DirectionType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => DirectionType.unknown,
  );
}

/// Parse heading type from string
HeadingType _parseHeadingType(String? value) {
  if (value == null || value.isEmpty) return HeadingType.none;
  return HeadingType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => HeadingType.none,
  );
}
