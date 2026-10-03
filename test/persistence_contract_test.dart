import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/data/repositories.dart';
import 'package:shot_stance_sprawl/features/drill/providers.dart';
import 'package:shot_stance_sprawl/features/onboarding/onboarding.dart';

void main() {
  group('Persistence contract', () {
    test('drill settings and profile keep their saved preference keys',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sharedPrefsProvider.future);

      await container.read(languageProvider.notifier).setLanguage('es');
      await container
          .read(calloutButtonStyleProvider.notifier)
          .setStyle(CalloutButtonStyle.classic);

      final config = container.read(drillConfigProvider.notifier);
      config.setTotalDurationSeconds(180);
      config.setIntervalRange(minSeconds: 1, maxSeconds: 2);
      config.setAdLibsEnabled(true);
      config.setVoicePack('coach_es');
      config.updateCalloutAudio('shot', 'coach_shot.m4a');
      config.updateAdLibAudio('ad_lib_1', 'coach_ad_lib.m4a');

      final profile = container.read(userProfileProvider.notifier);
      await profile.updateWeight(171.5);
      await profile.updateTeam('East Room');
      await profile.updateAge(16);
      await profile.updateProfileImage('profile.jpg');
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language_code'), 'es');
      expect(prefs.getString('callout_button_style'), 'classic');
      expect(prefs.getDouble('user_weight'), 171.5);
      expect(prefs.getString('user_team'), 'East Room');
      expect(prefs.getInt('user_age'), 16);
      expect(prefs.getString('user_profile_image'), 'profile.jpg');

      final rawConfig = prefs.getString('drill_config_v1');
      expect(rawConfig, isNotNull);
      final savedConfig = jsonDecode(rawConfig!) as Map<String, dynamic>;
      expect(savedConfig['totalDurationSeconds'], 180);
      expect(savedConfig['minIntervalSeconds'], 1.0);
      expect(savedConfig['maxIntervalSeconds'], 2.0);
      expect(savedConfig['adLibsEnabled'], isTrue);
      expect(savedConfig['voicePackId'], 'coach_es');
      expect(savedConfig['customAudioPaths'], {'shot': 'coach_shot.m4a'});
      expect(
        savedConfig['customAdLibAudioPaths'],
        {'ad_lib_1': 'coach_ad_lib.m4a'},
      );
      expect(savedConfig.keys, contains('enabledCalloutIds'));
      expect(savedConfig.keys, contains('calloutOverrideDurations'));
      expect(savedConfig.keys, contains('videoEnabled'));
      expect(savedConfig.keys, contains('activeWorkoutPresetId'));
    });

    test('custom callouts keep their saved key and JSON shape', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalCalloutRepository(prefs);

      await repository.saveCustomCallouts(const [
        Callout(
          id: 'shot',
          nameEn: 'Shot',
          nameEs: 'Tiro',
          type: 'Movement',
        ),
        Callout(
          id: 'custom_duck_under',
          nameEn: 'Duck Under',
          nameEs: 'Duck Under',
          type: 'Duration',
          defaultDurationSeconds: 15,
          audioUrl: 'duck_under.m4a',
          isCustom: true,
        ),
      ]);

      final raw = prefs.getString('custom_callouts_v1');
      expect(raw, isNotNull);
      final saved = jsonDecode(raw!) as List<dynamic>;
      expect(saved, hasLength(1));
      expect(
        saved.single,
        containsPair('id', 'custom_duck_under'),
      );
      expect(saved.single, containsPair('nameEn', 'Duck Under'));
      expect(saved.single, containsPair('nameEs', 'Duck Under'));
      expect(saved.single, containsPair('type', 'Duration'));
      expect(saved.single, containsPair('defaultDurationSeconds', 15));
      expect(saved.single, containsPair('audioUrl', 'duck_under.m4a'));
      expect(saved.single, containsPair('isCustom', true));
    });

    test('onboarding keeps its saved key and JSON shape', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final completedAt = DateTime(2026, 6, 12, 9);
      final lastWorkoutCompletedAt = DateTime(2026, 6, 13, 19, 30);
      await container.read(onboardingProvider.notifier).complete(
            OnboardingProfile(
              role: OnboardingRole.parent,
              goal: OnboardingGoal.season,
              focus: OnboardingFocus.handfight,
              pushLevel: OnboardingPushLevel.build,
              workoutRemindersEnabled: true,
              completedAt: completedAt,
              lastWorkoutCompletedAt: lastWorkoutCompletedAt,
            ),
          );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('onboarding_profile_v1');
      expect(raw, isNotNull);
      final saved = jsonDecode(raw!) as Map<String, dynamic>;
      expect(saved['role'], 'parent');
      expect(saved['goal'], 'season');
      expect(saved['focus'], 'handfight');
      expect(saved['pushLevel'], 'build');
      expect(saved['workoutRemindersEnabled'], isTrue);
      expect(saved['completedAt'], completedAt.toIso8601String());
      expect(
        saved['lastWorkoutCompletedAt'],
        lastWorkoutCompletedAt.toIso8601String(),
      );
    });

    test('progress providers keep their saved keys and JSON shape', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(trainingProgressProvider.notifier).addSession(
        callouts: const {'shot': 12, 'stance': 1},
        stanceSeconds: 15,
        at: DateTime(2026, 6, 12),
      );
      await container
          .read(badgeProgressProvider.notifier)
          .recordCustomCalloutCreated(1);

      final prefs = await SharedPreferences.getInstance();
      final rawTraining = prefs.getString('training_progress_v1');
      expect(rawTraining, isNotNull);
      final training = jsonDecode(rawTraining!) as Map<String, dynamic>;
      expect(training['calloutCounts'], {'shot': 12, 'stance': 1});
      expect(training['stanceSeconds'], 15);
      expect(training['repsByDate'], {'2026-06-12': 13});
      expect(training['sessionsByDate'], {'2026-06-12': 1});
      expect(training.keys, contains('stateDate'));

      final rawBadges = prefs.getString('badge_progress_v1');
      expect(rawBadges, isNotNull);
      final badges = jsonDecode(rawBadges!) as Map<String, dynamic>;
      expect(badges.keys, containsAll([
        'progressById',
        'stats',
        'recentUnlockedBadgeIds',
        'lastWorkoutResult',
      ]));
      expect(badges['progressById'], isA<Map<String, dynamic>>());
      expect(badges['stats'], isA<Map<String, dynamic>>());
    });
  });

  group('Store contract', () {
    test('Coach Mode product id stays stable', () {
      expect(proProductIds, {'snap_go_pro_monthly'});
    });
  });
}
