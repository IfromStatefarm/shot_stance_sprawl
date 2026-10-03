import 'package:flutter/foundation.dart';

enum DrillAudioDiagnosticType {
  assetMissing,
  preparationStarted,
  preparationCompleted,
  preparationFailed,
  playbackQueued,
  playbackStarted,
  playbackCompleted,
  playbackCancelled,
  playbackFailed,
  decoderRetry,
  stopRequested,
}

@immutable
class DrillAudioDiagnosticEvent {
  final DrillAudioDiagnosticType type;
  final String cue;
  final DateTime occurredAt;
  final Duration? elapsed;
  final int? attempt;
  final Object? error;
  final String? detail;

  DrillAudioDiagnosticEvent({
    required this.type,
    required this.cue,
    DateTime? occurredAt,
    this.elapsed,
    this.attempt,
    this.error,
    this.detail,
  }) : occurredAt = occurredAt ?? DateTime.now();

  @override
  String toString() {
    final fields = <String>[
      '[audio][${type.name}]',
      'cue=$cue',
      if (attempt != null) 'attempt=$attempt',
      if (elapsed != null) 'elapsedMs=${elapsed!.inMilliseconds}',
      if (detail != null) 'detail=$detail',
      if (error != null) 'error=$error',
    ];
    return fields.join(' ');
  }
}

typedef DrillAudioDiagnosticSink = void Function(
  DrillAudioDiagnosticEvent event,
);

void debugDrillAudioDiagnosticSink(DrillAudioDiagnosticEvent event) {
  if (kDebugMode) debugPrint(event.toString());
}
