import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'workout_snapshot.dart';

enum FriendshipStatus { pending, accepted, blocked }

enum WorkoutShareStatus {
  sent,
  accepted,
  scheduled,
  started,
  completed,
  declined,
}

const workoutShareRecipientLimit = 20;

@immutable
class WorkoutShareSendResult {
  const WorkoutShareSendResult({
    required this.shareId,
    required this.status,
    required this.created,
  });

  final String shareId;
  final WorkoutShareStatus status;
  final bool created;

  factory WorkoutShareSendResult.fromCallable(Object? value) {
    final data = _asMap(value);
    return WorkoutShareSendResult(
      shareId: data['shareId'] as String? ?? '',
      status: _enumByName(
        WorkoutShareStatus.values,
        data['status'],
        WorkoutShareStatus.sent,
      ),
      created: data['created'] as bool? ?? true,
    );
  }
}

@immutable
class WorkoutShareBatchSendResult {
  const WorkoutShareBatchSendResult({required this.byRecipient});

  final Map<String, WorkoutShareSendResult> byRecipient;

  factory WorkoutShareBatchSendResult.fromCallable(Object? value) {
    final data = _asMap(value);
    final rawResults = data['results'];
    if (rawResults is! Iterable) {
      return const WorkoutShareBatchSendResult(byRecipient: {});
    }
    final results = <String, WorkoutShareSendResult>{};
    for (final rawResult in rawResults) {
      final resultData = _asMap(rawResult);
      final recipientUid = resultData['recipientUid'] as String? ?? '';
      if (recipientUid.isEmpty) continue;
      results[recipientUid] = WorkoutShareSendResult.fromCallable(resultData);
    }
    return WorkoutShareBatchSendResult(byRecipient: Map.unmodifiable(results));
  }
}

enum SocialEventType {
  workoutSent('workout_sent'),
  workoutAccepted('workout_accepted'),
  workoutCompleted('workout_completed'),
  workoutDeclined('workout_declined'),
  reaction('reaction');

  const SocialEventType(this.firestoreValue);
  final String firestoreValue;
}

@immutable
class AccountSafetySettings {
  const AccountSafetySettings({
    this.allowFriendRequests = true,
    this.allowWorkoutMessages = true,
  });

  final bool allowFriendRequests;
  final bool allowWorkoutMessages;

  factory AccountSafetySettings.fromMap(Object? value) {
    final map = _asMap(value);
    return AccountSafetySettings(
      allowFriendRequests: map['allowFriendRequests'] as bool? ?? true,
      allowWorkoutMessages: map['allowWorkoutMessages'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'allowFriendRequests': allowFriendRequests,
        'allowWorkoutMessages': allowWorkoutMessages,
      };
}

@immutable
class SocialUserProfile {
  const SocialUserProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.username,
    this.language = 'en',
    this.discoverable = true,
    this.accountSafety = const AccountSafetySettings(),
    this.unreadSharedWorkoutCount = 0,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? username;
  final String language;
  final bool discoverable;
  final AccountSafetySettings accountSafety;
  final int unreadSharedWorkoutCount;

  factory SocialUserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SocialUserProfile(
      uid: snapshot.id,
      displayName: data['displayName'] as String? ?? 'Snap & Go athlete',
      photoUrl: data['photoUrl'] as String?,
      username: data['username'] as String?,
      language: data['language'] as String? ?? 'en',
      discoverable: data['discoverable'] as bool? ?? true,
      accountSafety: AccountSafetySettings.fromMap(data['accountSafety']),
      unreadSharedWorkoutCount:
          (data['unreadSharedWorkoutCount'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class Friendship {
  const Friendship({
    required this.id,
    required this.userIds,
    required this.requestedBy,
    required this.status,
    this.blockedBy,
    this.createdAt,
    this.acceptedAt,
    this.updatedAt,
  });

  final String id;
  final List<String> userIds;
  final String requestedBy;
  final FriendshipStatus status;
  final String? blockedBy;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? updatedAt;

  factory Friendship.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Friendship(
      id: snapshot.id,
      userIds: _stringList(data['userIds']),
      requestedBy: data['requestedBy'] as String? ?? '',
      status: _enumByName(
        FriendshipStatus.values,
        data['status'],
        FriendshipStatus.pending,
      ),
      blockedBy: data['blockedBy'] as String?,
      createdAt: _date(data['createdAt']),
      acceptedAt: _date(data['acceptedAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  String? otherUserId(String uid) {
    for (final userId in userIds) {
      if (userId != uid) return userId;
    }
    return null;
  }
}

@immutable
class WorkoutResultSummary {
  const WorkoutResultSummary({
    required this.durationSeconds,
    required this.calloutsCompleted,
    this.calloutCounts = const {},
  });

  final int durationSeconds;
  final int calloutsCompleted;
  final Map<String, int> calloutCounts;

  factory WorkoutResultSummary.fromMap(Object? value) {
    final map = _asMap(value);
    return WorkoutResultSummary(
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      calloutsCompleted: (map['calloutsCompleted'] as num?)?.toInt() ?? 0,
      calloutCounts: _intMap(map['calloutCounts']),
    );
  }

  Map<String, dynamic> toMap() => {
        'durationSeconds': durationSeconds,
        'calloutsCompleted': calloutsCompleted,
        'calloutCounts': calloutCounts,
      };
}

@immutable
class WorkoutShare {
  const WorkoutShare({
    required this.id,
    required this.senderUid,
    required this.recipientUid,
    required this.workoutSourceKey,
    required this.workoutSnapshot,
    required this.status,
    this.senderMessage,
    this.sentAt,
    this.acceptedAt,
    this.scheduledFor,
    this.startedAt,
    this.completedAt,
    this.declinedAt,
    this.recipientReadAt,
    this.recipientResultSummary,
  });

  final String id;
  final String senderUid;
  final String recipientUid;
  final String workoutSourceKey;
  final WorkoutSnapshot workoutSnapshot;
  final String? senderMessage;
  final WorkoutShareStatus status;
  final DateTime? sentAt;
  final DateTime? acceptedAt;
  final DateTime? scheduledFor;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? declinedAt;
  final DateTime? recipientReadAt;
  final WorkoutResultSummary? recipientResultSummary;

  factory WorkoutShare.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final result = data['recipientResultSummary'];
    return WorkoutShare(
      id: snapshot.id,
      senderUid: data['senderUid'] as String? ?? '',
      recipientUid: data['recipientUid'] as String? ?? '',
      workoutSourceKey: data['workoutSourceKey'] as String? ?? '',
      workoutSnapshot: WorkoutSnapshot.fromFirestore(data['workoutSnapshot']),
      senderMessage: data['senderMessage'] as String?,
      status: _enumByName(
        WorkoutShareStatus.values,
        data['status'],
        WorkoutShareStatus.sent,
      ),
      sentAt: _date(data['sentAt']),
      acceptedAt: _date(data['acceptedAt']),
      // Read the Step 11 prototype field so already-shared workouts remain
      // usable while all new writes use the final scheduledFor contract.
      scheduledFor: _date(data['scheduledFor'] ?? data['scheduledAt']),
      startedAt: _date(data['startedAt']),
      completedAt: _date(data['completedAt']),
      declinedAt: _date(data['declinedAt']),
      recipientReadAt: _date(data['recipientReadAt']),
      recipientResultSummary:
          result is Map ? WorkoutResultSummary.fromMap(result) : null,
    );
  }

  WorkoutShare copyWith({
    WorkoutShareStatus? status,
    Object? scheduledFor = _workoutShareUnset,
    Object? startedAt = _workoutShareUnset,
    Object? completedAt = _workoutShareUnset,
    Object? declinedAt = _workoutShareUnset,
    Object? recipientReadAt = _workoutShareUnset,
    WorkoutResultSummary? recipientResultSummary,
  }) {
    return WorkoutShare(
      id: id,
      senderUid: senderUid,
      recipientUid: recipientUid,
      workoutSourceKey: workoutSourceKey,
      workoutSnapshot: workoutSnapshot,
      senderMessage: senderMessage,
      status: status ?? this.status,
      sentAt: sentAt,
      acceptedAt: acceptedAt,
      scheduledFor: identical(scheduledFor, _workoutShareUnset)
          ? this.scheduledFor
          : scheduledFor as DateTime?,
      startedAt: identical(startedAt, _workoutShareUnset)
          ? this.startedAt
          : startedAt as DateTime?,
      completedAt: identical(completedAt, _workoutShareUnset)
          ? this.completedAt
          : completedAt as DateTime?,
      declinedAt: identical(declinedAt, _workoutShareUnset)
          ? this.declinedAt
          : declinedAt as DateTime?,
      recipientReadAt: identical(recipientReadAt, _workoutShareUnset)
          ? this.recipientReadAt
          : recipientReadAt as DateTime?,
      recipientResultSummary:
          recipientResultSummary ?? this.recipientResultSummary,
    );
  }
}

const _workoutShareUnset = Object();

@immutable
class SocialEvent {
  const SocialEvent({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.userIds,
    this.targetUid,
    this.workoutShareId,
    this.reaction,
    this.createdAt,
  });

  final String id;
  final SocialEventType type;
  final String actorUid;
  final String? targetUid;
  final List<String> userIds;
  final String? workoutShareId;
  final String? reaction;
  final DateTime? createdAt;

  factory SocialEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SocialEvent(
      id: snapshot.id,
      type: SocialEventType.values.firstWhere(
        (type) => type.firestoreValue == data['type'],
        orElse: () => SocialEventType.workoutSent,
      ),
      actorUid: data['actorUid'] as String? ?? '',
      targetUid: data['targetUid'] as String?,
      userIds: _stringList(data['userIds']),
      workoutShareId: data['workoutShareId'] as String?,
      reaction: data['reaction'] as String?,
      createdAt: _date(data['createdAt']),
    );
  }
}

@immutable
class SocialStats {
  const SocialStats({
    required this.uid,
    this.relayStreak = 0,
    this.friendWorkoutStreak = 0,
    this.partnerStreaks = const {},
    this.crewStreak = 0,
    this.totalSharedWorkouts = 0,
    this.totalQualifiedRelays = 0,
    this.totalCompletedFriendWorkouts = 0,
    this.totalPartnerWeeks = 0,
    this.totalCrewWeeks = 0,
    this.socialProgressPoints = 0,
    this.socialBadges = const [],
    this.updatedAt,
  });

  final String uid;
  final int relayStreak;
  final int friendWorkoutStreak;
  final Map<String, int> partnerStreaks;
  final int crewStreak;
  final int totalSharedWorkouts;
  final int totalQualifiedRelays;
  final int totalCompletedFriendWorkouts;
  final int totalPartnerWeeks;
  final int totalCrewWeeks;
  final int socialProgressPoints;
  final List<String> socialBadges;
  final DateTime? updatedAt;

  int get bestPartnerStreak => partnerStreaks.values.fold<int>(
        0,
        (best, value) => value > best ? value : best,
      );

  factory SocialStats.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SocialStats(
      uid: snapshot.id,
      relayStreak: (data['relayStreak'] as num?)?.toInt() ?? 0,
      friendWorkoutStreak: (data['friendWorkoutStreak'] as num?)?.toInt() ?? 0,
      partnerStreaks: _intMap(data['partnerStreaks']),
      crewStreak: (data['crewStreak'] as num?)?.toInt() ?? 0,
      totalSharedWorkouts: (data['totalSharedWorkouts'] as num?)?.toInt() ?? 0,
      totalQualifiedRelays:
          (data['totalQualifiedRelays'] as num?)?.toInt() ?? 0,
      totalCompletedFriendWorkouts:
          (data['totalCompletedFriendWorkouts'] as num?)?.toInt() ?? 0,
      totalPartnerWeeks: (data['totalPartnerWeeks'] as num?)?.toInt() ?? 0,
      totalCrewWeeks: (data['totalCrewWeeks'] as num?)?.toInt() ?? 0,
      socialProgressPoints:
          (data['socialProgressPoints'] as num?)?.toInt() ?? 0,
      socialBadges: _stringList(data['socialBadges']),
      updatedAt: _date(data['updatedAt']),
    );
  }
}

@immutable
class SocialCompletionReward {
  const SocialCompletionReward({
    required this.applied,
    required this.partnerUid,
    this.pointsAwarded = 0,
    this.friendWorkoutStreak = 0,
    this.partnerStreak = 0,
    this.crewStreak = 0,
    this.partnerQualified = false,
    this.crewQualified = false,
    this.newBadgeIds = const [],
  });

  final bool applied;
  final String partnerUid;
  final int pointsAwarded;
  final int friendWorkoutStreak;
  final int partnerStreak;
  final int crewStreak;
  final bool partnerQualified;
  final bool crewQualified;
  final List<String> newBadgeIds;

  factory SocialCompletionReward.fromCallable(Object? value) {
    final data = _asMap(value);
    final rewards = _asMap(data['rewards']);
    return SocialCompletionReward(
      applied: data['applied'] == true,
      partnerUid: data['partnerUid'] as String? ?? '',
      pointsAwarded: (rewards['pointsAwarded'] as num?)?.toInt() ?? 0,
      friendWorkoutStreak:
          (rewards['friendWorkoutStreak'] as num?)?.toInt() ?? 0,
      partnerStreak: (rewards['partnerStreak'] as num?)?.toInt() ?? 0,
      crewStreak: (rewards['crewStreak'] as num?)?.toInt() ?? 0,
      partnerQualified: rewards['partnerQualified'] == true,
      crewQualified: rewards['crewQualified'] == true,
      newBadgeIds: _stringList(rewards['newBadgeIds']),
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<String> _stringList(Object? value) => value is Iterable
    ? value.whereType<String>().toList(growable: false)
    : const [];

Map<String, int> _intMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
  );
}

DateTime? _date(Object? value) => switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime dateTime => dateTime,
      String text => DateTime.tryParse(text),
      _ => null,
    };

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  return fallback;
}
