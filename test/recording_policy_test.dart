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
}
