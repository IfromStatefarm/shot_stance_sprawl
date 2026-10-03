import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/drill/models.dart';
import 'package:shot_stance_sprawl/features/drill/workout_presets.dart';
import 'package:shot_stance_sprawl/features/social/social.dart';

void main() {
  group('WorkoutSnapshot', () {
    test('fromPreset creates a deterministic version 2 preset snapshot', () {
      final preset = allWorkoutPresets.firstWhere(
        (candidate) => candidate.timedCalloutDurations.isNotEmpty,
      );
      final timedId = preset.timedCalloutDurations.keys.first;
      final snapshot = WorkoutSnapshot.fromPreset(
        preset,
        timedCalloutDurations: {timedId: 15},
      );
      final map = snapshot.toFirestore();

      expect(snapshot.schemaVersion, WorkoutSnapshot.currentSchemaVersion);
      expect(snapshot.sourceType, WorkoutSnapshotSourceType.preset);
      expect(snapshot.presetId, preset.id);
      expect(snapshot.enabledCalloutIds, preset.calloutIds);
      expect(snapshot.timedCalloutDurations, {timedId: 15});
      expect(map['schemaVersion'], 2);
      expect(map['title'], {'en': preset.titleEn, 'es': preset.titleEs});
      expect(map['sourceType'], 'preset');
      expect(map['durationSeconds'], preset.recommendedDurationSeconds);
      expect(map, isNot(contains('customWorkoutConfiguration')));
      expect(map, isNot(contains('calloutIds')));
      expect(map, isNot(contains('totalDurationSeconds')));
    });

    test('fromDrillConfig captures only portable custom configuration', () {
      const config = DrillConfig(
        totalDurationSeconds: 300,
        minIntervalSeconds: 1,
        maxIntervalSeconds: 2,
        enabledCalloutIds: {'shot', 'sprawl'},
        customAudioPaths: {'shot': r'C:\private\shot.m4a'},
        customAdLibAudioPaths: {'nice': r'C:\private\nice.m4a'},
        calloutOverrideDurations: {'shot': 15, 'unused': 45},
        videoEnabled: true,
        adLibsEnabled: true,
      );

      final snapshot = WorkoutSnapshot.fromDrillConfig(
        config,
        title: 'My chain drill',
      );
      final map = snapshot.toFirestore();
      final restoredConfig = snapshot.toDrillConfig();

      expect(snapshot.sourceType, WorkoutSnapshotSourceType.custom);
      expect(snapshot.presetId, isNull);
      expect(snapshot.difficulty, 8);
      expect(snapshot.timedCalloutDurations, {'shot': 15});
      expect(map['customWorkoutConfiguration'], {'adLibsEnabled': true});
      expect(map.toString(), isNot(contains(r'C:\private')));
      expect(map, isNot(contains('videoEnabled')));
      expect(map, isNot(contains('customAudioPaths')));
      expect(map, isNot(contains('customAdLibAudioPaths')));
      expect(map, isNot(contains('activeWorkoutPresetId')));
      expect(restoredConfig.customAudioPaths, isEmpty);
      expect(restoredConfig.customAdLibAudioPaths, isEmpty);
      expect(restoredConfig.videoEnabled, isFalse);
      expect(restoredConfig.adLibsEnabled, isTrue);
      expect(restoredConfig.enabledCalloutIds, {'shot', 'sprawl'});
    });

    test('current Firestore representation round trips exactly', () {
      final original = WorkoutSnapshot.fromPreset(
        allWorkoutPresets.last,
        timedCalloutDurations: const {},
      );

      expect(
        WorkoutSnapshot.fromFirestore(original.toFirestore()).toFirestore(),
        original.toFirestore(),
      );
    });

    test('migrates Step 4 schema version 1 shares', () {
      final migrated = WorkoutSnapshot.fromFirestore(const {
        'schemaVersion': 1,
        'titleEn': 'Legacy offense',
        'titleEs': 'Ataque anterior',
        'purposeEn': 'Keep old shares runnable',
        'purposeEs': 'Mantener entrenamientos anteriores',
        'category': 'offense',
        'totalDurationSeconds': 240,
        'minIntervalSeconds': 1.5,
        'maxIntervalSeconds': 3,
        'calloutIds': ['stance', 'shot'],
        'calloutOverrideDurations': {'stance': 15},
        'difficulty': 7,
      });

      expect(migrated.schemaVersion, 2);
      expect(migrated.sourceType, WorkoutSnapshotSourceType.preset);
      // Version 1 did not store a preset ID, so migration cannot invent one.
      expect(migrated.presetId, isNull);
      expect(migrated.durationSeconds, 240);
      expect(migrated.enabledCalloutIds, ['stance', 'shot']);
      expect(migrated.timedCalloutDurations, {'stance': 15});
      expect(migrated.toFirestore(), containsPair('schemaVersion', 2));
      expect(migrated.toFirestore(), isNot(contains('titleEn')));
    });

    test('migrates an unversioned custom share and strips private fields', () {
      final migrated = WorkoutSnapshot.fromFirestore(const {
        'workoutTitle': 'Old custom drill',
        'durationSeconds': 180,
        'difficulty': 5,
        'intervalRange': {'minSeconds': 2, 'maxSeconds': 4},
        'enabledCalloutIds': ['stance', 'sprawl'],
        'timedCalloutDurations': {'stance': 20},
        'adLibsEnabled': true,
        'customAudioPaths': {'stance': r'C:\private\stance.wav'},
        'recordedVideoPath': r'C:\private\session.mp4',
        'deviceId': 'private-device',
      });
      final serialized = migrated.toFirestore();

      expect(migrated.schemaVersion, 2);
      expect(migrated.sourceType, WorkoutSnapshotSourceType.custom);
      expect(migrated.customWorkoutConfiguration?.adLibsEnabled, isTrue);
      expect(migrated.enabledCalloutIds, ['stance', 'sprawl']);
      expect(serialized.toString(), isNot(contains(r'C:\private')));
      expect(serialized, isNot(contains('recordedVideoPath')));
      expect(serialized, isNot(contains('deviceId')));
    });

    test('rejects snapshots from an unsupported future schema', () {
      expect(
        () => WorkoutSnapshot.fromFirestore(const {'schemaVersion': 99}),
        throwsFormatException,
      );
    });
  });

  test('account safety defaults enable expected team features', () {
    final settings = AccountSafetySettings.fromMap(const {});
    expect(settings.allowFriendRequests, isTrue);
    expect(settings.allowWorkoutMessages, isTrue);
    expect(settings.toMap(), {
      'allowFriendRequests': true,
      'allowWorkoutMessages': true,
    });
  });

  test('custom workout source keys are stable for the supplied instant', () {
    final at = DateTime.utc(2026, 8, 10, 12);
    expect(
      newCustomWorkoutSourceKey(at),
      'custom:${at.microsecondsSinceEpoch}',
    );
  });

  test('callable workout send result preserves duplicate lifecycle state', () {
    final result = WorkoutShareSendResult.fromCallable(const {
      'shareId': 'stable-share-id',
      'status': 'completed',
      'created': false,
    });

    expect(result.shareId, 'stable-share-id');
    expect(result.status, WorkoutShareStatus.completed);
    expect(result.created, isFalse);
  });

  test('batch workout send results are keyed by trusted recipient IDs', () {
    final result = WorkoutShareBatchSendResult.fromCallable(const {
      'results': [
        {
          'recipientUid': 'friend-a',
          'shareId': 'share-a',
          'status': 'sent',
          'created': true,
        },
        {
          'recipientUid': 'friend-b',
          'shareId': 'share-b',
          'status': 'completed',
          'created': false,
        },
      ],
    });

    expect(result.byRecipient.keys, {'friend-a', 'friend-b'});
    expect(result.byRecipient['friend-a']?.created, isTrue);
    expect(
      result.byRecipient['friend-b']?.status,
      WorkoutShareStatus.completed,
    );
  });

  test('completion rewards parse server-authoritative streak results', () {
    final reward = SocialCompletionReward.fromCallable(const {
      'applied': true,
      'partnerUid': 'friend-a',
      'rewards': {
        'pointsAwarded': 26,
        'friendWorkoutStreak': 4,
        'partnerStreak': 2,
        'crewStreak': 1,
        'partnerQualified': true,
        'crewQualified': true,
        'newBadgeIds': ['social_partner_2'],
      },
    });

    expect(reward.applied, isTrue);
    expect(reward.partnerUid, 'friend-a');
    expect(reward.pointsAwarded, 26);
    expect(reward.partnerQualified, isTrue);
    expect(reward.crewQualified, isTrue);
    expect(reward.newBadgeIds, ['social_partner_2']);
  });

  test('send-back source keys are stable per completed friend session', () {
    expect(
      workoutSourceKeyForSendBack('share-a', 'session-a'),
      'send-back:share-a:session-a',
    );
    expect(
      () => workoutSourceKeyForSendBack('', 'session-a'),
      throwsArgumentError,
    );
  });

  test('recipient UI groups scheduled and started shares as accepted', () {
    expect(
      workoutRecipientStateForStatus(WorkoutShareStatus.sent),
      WorkoutRecipientState.sent,
    );
    expect(
      workoutRecipientStateForStatus(WorkoutShareStatus.scheduled),
      WorkoutRecipientState.accepted,
    );
    expect(
      workoutRecipientStateForStatus(WorkoutShareStatus.started),
      WorkoutRecipientState.accepted,
    );
    expect(
      workoutRecipientStateForStatus(WorkoutShareStatus.completed),
      WorkoutRecipientState.completed,
    );
    expect(
      workoutRecipientStateForStatus(WorkoutShareStatus.declined),
      WorkoutRecipientState.declined,
    );
  });

  test('shared inbox assigns lifecycle states to the requested sections', () {
    expect(
      sectionForWorkoutShare(_share('new', WorkoutShareStatus.sent)),
      SharedWorkoutInboxSection.newWorkouts,
    );
    expect(
      sectionForWorkoutShare(_share('saved', WorkoutShareStatus.accepted)),
      SharedWorkoutInboxSection.newWorkouts,
    );
    expect(
      sectionForWorkoutShare(
        _share('scheduled', WorkoutShareStatus.scheduled),
      ),
      SharedWorkoutInboxSection.scheduled,
    );
    expect(
      sectionForWorkoutShare(
        _share('completed', WorkoutShareStatus.completed),
      ),
      SharedWorkoutInboxSection.completed,
    );
    expect(
      sectionForWorkoutShare(_share('declined', WorkoutShareStatus.declined)),
      isNull,
    );
  });

  test('shared inbox merges live updates without duplicate cards', () {
    final older = _share(
      'same',
      WorkoutShareStatus.sent,
      sentAt: DateTime.utc(2026, 8, 10),
    );
    final updated = _share(
      'same',
      WorkoutShareStatus.accepted,
      sentAt: DateTime.utc(2026, 8, 10),
    );
    final newer = _share(
      'newer',
      WorkoutShareStatus.sent,
      sentAt: DateTime.utc(2026, 8, 11),
    );

    final merged = mergeWorkoutShares([older], [updated, newer]);

    expect(merged.map((share) => share.id), ['newer', 'same']);
    expect(merged.last.status, WorkoutShareStatus.accepted);
  });

  test('scheduled inbox orders the next workout first', () {
    final later = _share(
      'later',
      WorkoutShareStatus.scheduled,
      scheduledFor: DateTime.utc(2026, 8, 12, 18),
    );
    final sooner = _share(
      'sooner',
      WorkoutShareStatus.scheduled,
      scheduledFor: DateTime.utc(2026, 8, 11, 18),
    );

    final sorted = sortWorkoutSharesForSection(
      SharedWorkoutInboxSection.scheduled,
      [later, sooner],
    );

    expect(sorted.map((share) => share.id), ['sooner', 'later']);
  });

  test('movement summary humanizes and bounds shared callouts', () {
    final snapshot = WorkoutSnapshot.fromDrillConfig(
      const DrillConfig(
        enabledCalloutIds: {
          'level_change',
          'shot',
          'down_block',
          'sprawl',
        },
      ),
      title: 'Movement mix',
      titleEs: 'Mezcla',
    );

    expect(
      workoutMovementSummary(snapshot, maxMovements: 2),
      'Level Change • Shot • +2',
    );
  });
}

WorkoutShare _share(
  String id,
  WorkoutShareStatus status, {
  DateTime? sentAt,
  DateTime? scheduledFor,
}) {
  return WorkoutShare(
    id: id,
    senderUid: 'sender',
    recipientUid: 'recipient',
    workoutSourceKey: 'source-$id',
    workoutSnapshot: WorkoutSnapshot.fromDrillConfig(
      const DrillConfig(enabledCalloutIds: {'shot'}),
      title: 'Shared workout',
      titleEs: 'Workout compartido',
    ),
    status: status,
    sentAt: sentAt,
    scheduledFor: scheduledFor,
  );
}
