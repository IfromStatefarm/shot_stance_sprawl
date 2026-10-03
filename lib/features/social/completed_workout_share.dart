import '../drill/models.dart';
import '../drill/workout_presets.dart';
import 'workout_snapshot.dart';

WorkoutSnapshot workoutSnapshotForCompletedSession(
  DrillConfig configSnapshot,
) {
  final preset = _presetById(configSnapshot.activeWorkoutPresetId);
  if (preset != null) {
    return WorkoutSnapshot.fromPreset(
      preset,
      config: configSnapshot,
      timedCalloutDurations: configSnapshot.calloutOverrideDurations,
    );
  }
  return WorkoutSnapshot.fromDrillConfig(
    configSnapshot,
    title: 'Completed Custom Workout',
    titleEs: 'Entrenamiento Personalizado Completado',
    purposeEn: 'A custom workout captured when the session began.',
    purposeEs: 'Un entrenamiento personalizado guardado al iniciar la sesion.',
  );
}

String workoutSourceKeyForCompletedSession(String sessionId) {
  final normalized = sessionId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(sessionId, 'sessionId', 'Cannot be empty.');
  }
  return 'completed:$normalized';
}

String workoutSourceKeyForSendBack(String originalShareId, String sessionId) {
  final normalizedShareId = originalShareId.trim();
  final normalizedSessionId = sessionId.trim();
  if (normalizedShareId.isEmpty) {
    throw ArgumentError.value(
      originalShareId,
      'originalShareId',
      'Cannot be empty.',
    );
  }
  if (normalizedSessionId.isEmpty) {
    throw ArgumentError.value(sessionId, 'sessionId', 'Cannot be empty.');
  }
  return 'send-back:$normalizedShareId:$normalizedSessionId';
}

WorkoutPreset? _presetById(String? presetId) {
  if (presetId == null) return null;
  for (final preset in allWorkoutPresets) {
    if (preset.id == presetId) return preset;
  }
  return null;
}
