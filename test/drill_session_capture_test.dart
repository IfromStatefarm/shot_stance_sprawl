import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/drill/drill.dart';
import 'package:shot_stance_sprawl/features/social/social.dart';

void main() {
  group('DrillSessionCapture', () {
    test('deeply freezes the active config when the session starts', () {
      final enabledIds = <String>{'shot'};
      final audioPaths = <String, String>{'shot': r'C:\private\shot.wav'};
      final adLibPaths = <String, String>{'hype': r'C:\private\hype.wav'};
      final timedDurations = <String, int>{'shot': 15};
      final activeConfig = DrillConfig(
        totalDurationSeconds: 300,
        minIntervalSeconds: 1,
        maxIntervalSeconds: 2,
        enabledCalloutIds: enabledIds,
        customAudioPaths: audioPaths,
        customAdLibAudioPaths: adLibPaths,
        calloutOverrideDurations: timedDurations,
        videoEnabled: true,
        adLibsEnabled: true,
      );

      final capture = DrillSessionCapture.start(
        activeConfig,
        startedAt: DateTime.utc(2026, 8, 10, 12),
        entropy: List<int>.generate(16, (index) => index),
        workoutShareId: '  share-123  ',
      );
      enabledIds.add('sprawl');
      audioPaths['sprawl'] = r'C:\private\sprawl.wav';
      adLibPaths.clear();
      timedDurations['shot'] = 60;

      expect(capture.configSnapshot.enabledCalloutIds, {'shot'});
      expect(capture.configSnapshot.customAudioPaths.keys, {'shot'});
      expect(capture.configSnapshot.customAdLibAudioPaths.keys, {'hype'});
      expect(capture.configSnapshot.calloutOverrideDurations, {'shot': 15});
      expect(capture.workoutShareId, 'share-123');
      expect(
        () => capture.configSnapshot.enabledCalloutIds.add('fake'),
        throwsUnsupportedError,
      );
      expect(
        () => capture.configSnapshot.calloutOverrideDurations['shot'] = 30,
        throwsUnsupportedError,
      );
    });

    test('creates unique, portable session identifiers', () {
      final first = DrillSessionCapture.start(
        const DrillConfig(),
        startedAt: DateTime.utc(2026, 8, 10, 12),
        entropy: List<int>.filled(16, 1),
      );
      final second = DrillSessionCapture.start(
        const DrillConfig(),
        startedAt: DateTime.utc(2026, 8, 10, 12),
        entropy: List<int>.filled(16, 2),
      );

      expect(first.sessionId, startsWith('session_'));
      expect(first.sessionId, isNot(second.sessionId));
      expect(first.startedAt.isUtc, isTrue);
      expect(
        workoutSourceKeyForCompletedSession(first.sessionId),
        'completed:${first.sessionId}',
      );
    });
  });

  group('completed workout sharing', () {
    test('uses the captured custom config and strips private session data', () {
      final mutableIds = <String>{'shot', 'sprawl'};
      final capture = DrillSessionCapture.start(
        DrillConfig(
          totalDurationSeconds: 240,
          minIntervalSeconds: 1,
          maxIntervalSeconds: 2,
          enabledCalloutIds: mutableIds,
          customAudioPaths: const {'shot': r'C:\private\shot.wav'},
          customAdLibAudioPaths: const {'hype': r'C:\private\hype.wav'},
          calloutOverrideDurations: const {'shot': 15},
          videoEnabled: true,
          adLibsEnabled: true,
        ),
        entropy: List<int>.filled(16, 3),
      );
      mutableIds
        ..clear()
        ..add('fake');

      final snapshot = workoutSnapshotForCompletedSession(
        capture.configSnapshot,
      );
      final serialized = snapshot.toFirestore();

      expect(snapshot.sourceType, WorkoutSnapshotSourceType.custom);
      expect(snapshot.enabledCalloutIds, {'shot', 'sprawl'});
      expect(snapshot.durationSeconds, 240);
      expect(snapshot.timedCalloutDurations, {'shot': 15});
      expect(snapshot.customWorkoutConfiguration?.adLibsEnabled, isTrue);
      expect(serialized.toString(), isNot(contains(r'C:\private')));
      expect(serialized, isNot(contains('videoEnabled')));
      expect(serialized, isNot(contains('customAudioPaths')));
    });

    test('preserves preset identity while using completed timing', () {
      final preset = allWorkoutPresets.first;
      final snapshot = workoutSnapshotForCompletedSession(
        DrillConfig(
          totalDurationSeconds: 420,
          minIntervalSeconds: 1.5,
          maxIntervalSeconds: 3,
          enabledCalloutIds: preset.calloutIds.toSet(),
          activeWorkoutPresetId: preset.id,
        ),
      );

      expect(snapshot.sourceType, WorkoutSnapshotSourceType.preset);
      expect(snapshot.presetId, preset.id);
      expect(snapshot.titleEn, preset.titleEn);
      expect(snapshot.durationSeconds, 420);
      expect(snapshot.minIntervalSeconds, 1.5);
      expect(snapshot.maxIntervalSeconds, 3);
    });
  });
}
