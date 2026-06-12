import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/drill/ad_libs.dart';
import 'package:shot_stance_sprawl/features/drill/drill_engine.dart';
import 'package:shot_stance_sprawl/features/drill/models.dart';
import 'package:shot_stance_sprawl/features/drill/recording_policy.dart';

void main() {
  group('RecordingPolicy', () {
    test('caps free recorded drills at 60 seconds', () {
      const config = DrillConfig(
        totalDurationSeconds: 15 * 60,
        videoEnabled: true,
      );

      expect(
        RecordingPolicy.effectiveTotalDurationSeconds(
          config: config,
          isPro: false,
        ),
        RecordingPolicy.freeRecordingLimitSeconds,
      );
    });

    test('does not cap free drills when recording is off', () {
      const config = DrillConfig(
        totalDurationSeconds: 15 * 60,
        videoEnabled: false,
      );

      expect(
        RecordingPolicy.effectiveTotalDurationSeconds(
          config: config,
          isPro: false,
        ),
        15 * 60,
      );
    });

    test('caps pro recorded drills at 10 minutes', () {
      const config = DrillConfig(
        totalDurationSeconds: 15 * 60,
        videoEnabled: true,
      );

      expect(
        RecordingPolicy.effectiveTotalDurationSeconds(
          config: config,
          isPro: true,
        ),
        RecordingPolicy.proRecordingLimitSeconds,
      );
    });

    test('keeps shorter recorded drills unchanged', () {
      const config = DrillConfig(
        totalDurationSeconds: 45,
        videoEnabled: true,
      );

      expect(
        RecordingPolicy.effectiveTotalDurationSeconds(
          config: config,
          isPro: false,
        ),
        45,
      );
    });

    test('returns a capped effective config for free recorded drills', () {
      const config = DrillConfig(
        totalDurationSeconds: 15 * 60,
        videoEnabled: true,
      );

      final effectiveConfig = RecordingPolicy.effectiveConfig(
        config: config,
        isPro: false,
      );

      expect(effectiveConfig.totalDurationSeconds, 60);
      expect(effectiveConfig.videoEnabled, isTrue);
    });
  });

  group('DrillState.copyWith', () {
    test('can clear nullable video and hold state', () {
      const callout = Callout(
        id: 'old_callout',
        nameEn: 'Old Callout',
        nameEs: 'Old Callout',
        type: 'Duration',
      );
      final state = DrillState(
        lastCallout: callout,
        holdRemaining: const Duration(seconds: 5),
        videoPath: 'old-video.mp4',
      );

      final cleared = state.copyWith(
        lastCallout: null,
        holdRemaining: null,
        videoPath: null,
      );

      expect(cleared.lastCallout, isNull);
      expect(cleared.holdRemaining, isNull);
      expect(cleared.videoPath, isNull);
    });
  });

  group('Ad libs', () {
    test('only the first slot is unlocked for free users', () {
      expect(
        AdLibSlots.unlocked(isPro: false).map((slot) => slot.id),
        ['ad_lib_1'],
      );
      expect(AdLibSlots.unlocked(isPro: true), hasLength(5));
    });

    test('DrillConfig preserves ad lib settings', () {
      const config = DrillConfig(
        adLibsEnabled: true,
        customAdLibAudioPaths: {'ad_lib_1': 'custom.m4a'},
      );

      final restored = DrillConfig.fromJson(config.toJson());

      expect(restored.adLibsEnabled, isTrue);
      expect(restored.customAdLibAudioPaths['ad_lib_1'], 'custom.m4a');
    });

    test('custom ad lib audio is only active for pro users', () {
      const config = DrillConfig(
        customAdLibAudioPaths: {'ad_lib_1': 'custom.m4a'},
      );
      final slot = AdLibSlots.all.first;

      expect(slot.isUnlocked(isPro: false), isTrue);
      expect(slot.customPath(config, isPro: false), isNull);
      expect(slot.activePath(config, isPro: false), slot.defaultAssetPath);
      expect(slot.customPath(config, isPro: true), 'custom.m4a');
    });
  });

  group('Callout config migration', () {
    test('legacy Hand Fight selections become one timed Hand Fight callout', () {
      final migrated = DrillConfig.fromMap(const <String, dynamic>{
        'enabledCalloutIds': <String>['shot', 'hand_fight_30'],
        'customAudioPaths': <String, String>{'hand_fight_30': 'coach.m4a'},
        'calloutOverrideDurations': <String, int>{'hand_fight_30': 30},
      });

      expect(migrated.enabledCalloutIds, contains('hand_fight'));
      expect(migrated.enabledCalloutIds, isNot(contains('hand_fight_30')));
      expect(migrated.calloutOverrideDurations['hand_fight'], 30);
      expect(migrated.customAudioPaths['hand_fight'], 'coach.m4a');
    });
  });

  group('TrainingProgress', () {
    test('tracks callouts, stance minutes, daily reps, and streaks', () {
      final progress = const TrainingProgress()
          .addSession(
            callouts: const {'shot': 10, 'stance': 2},
            stanceSeconds: 30,
            at: DateTime(2026, 6, 5),
          )
          .addSession(
            callouts: const {'sprawl': 8},
            stanceSeconds: 0,
            at: DateTime(2026, 6, 6),
          )
          .addSession(
            callouts: const {'fake': 4, 'stance': 2},
            stanceSeconds: 45,
            at: DateTime(2026, 6, 7),
          );

      expect(progress.calloutCount('shot'), 10);
      expect(progress.calloutCount('sprawl'), 8);
      expect(progress.calloutCount('fake'), 4);
      expect(progress.stanceMinutes, 1);
      expect(progress.repsForDate(DateTime(2026, 6, 7)), 6);
      expect(progress.currentStreak(today: DateTime(2026, 6, 7)), 3);
    });

    test('counts completed sessions toward streak even with no callouts', () {
      final progress = const TrainingProgress()
          .addSession(
            callouts: const {'shot': 4},
            stanceSeconds: 0,
            at: DateTime(2026, 6, 7),
          )
          .addSession(
            callouts: const {},
            stanceSeconds: 0,
            at: DateTime(2026, 6, 8),
          );

      expect(progress.repsForDate(DateTime(2026, 6, 8)), 0);
      expect(progress.sessionsForDate(DateTime(2026, 6, 8)), 1);
      expect(progress.currentStreak(today: DateTime(2026, 6, 8)), 2);
    });

    test('serializes the state date and goal totals', () {
      final restored = TrainingProgress.fromJson(
        TrainingProgress(
          calloutCounts: const {'shot': 55},
          repsByDate: const {'2026-06-07': 50},
          sessionsByDate: const {'2026-06-07': 1},
          stateDate: DateTime(2026, 9, 5),
        ).toJson(),
      );

      expect(restored.calloutCount('shot'), 55);
      expect(restored.repsForDate(DateTime(2026, 6, 7)), 50);
      expect(restored.sessionsForDate(DateTime(2026, 6, 7)), 1);
      expect(
        restored.daysUntilState(today: DateTime(2026, 6, 7)),
        90,
      );
    });
  });
}
