import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models.dart';

@immutable
class DrillSessionCapture {
  const DrillSessionCapture._({
    required this.sessionId,
    required this.configSnapshot,
    required this.startedAt,
    this.workoutShareId,
  });

  final String sessionId;
  final DrillConfig configSnapshot;
  final DateTime startedAt;
  final String? workoutShareId;

  factory DrillSessionCapture.start(
    DrillConfig activeConfig, {
    DateTime? startedAt,
    List<int>? entropy,
    String? workoutShareId,
  }) {
    final capturedAt = (startedAt ?? DateTime.now()).toUtc();
    final randomBytes =
        entropy ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
    if (randomBytes.length < 16 ||
        randomBytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(
        entropy,
        'entropy',
        'Provide at least 16 byte values.',
      );
    }
    final encodedEntropy = base64Url
        .encode(randomBytes.take(16).toList(growable: false))
        .replaceAll('=', '');
    final timeComponent = capturedAt.microsecondsSinceEpoch.toRadixString(36);
    return DrillSessionCapture._(
      sessionId: 'session_${timeComponent}_$encodedEntropy',
      configSnapshot: DrillConfig.immutableSnapshot(activeConfig),
      startedAt: capturedAt,
      workoutShareId: _nonEmpty(workoutShareId),
    );
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
