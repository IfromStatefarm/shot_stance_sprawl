import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../account/account_models.dart';
import 'social_models.dart';
import 'workout_snapshot.dart';

class SocialRepository {
  SocialRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  String get _uid {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw const AccountException('Sign in first.');
    return uid;
  }

  Stream<SocialUserProfile> watchMyProfile() {
    final uid = _uid;
    return firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map(SocialUserProfile.fromFirestore);
  }

  Future<List<SocialUserProfile>> loadProfiles(Iterable<String> userIds) async {
    final uniqueIds = userIds.toSet().take(100).toList(growable: false);
    if (uniqueIds.isEmpty) return const [];
    final documents = await Future.wait(
      uniqueIds.map(
        (uid) => firestore.collection('safeProfiles').doc(uid).get(),
      ),
    );
    return documents
        .where((document) => document.exists)
        .map(SocialUserProfile.fromFirestore)
        .toList(growable: false);
  }

  Future<void> syncFriendAccess() =>
      _callVoid('syncFriendAccess', const <String, dynamic>{});

  Future<void> updateProfileSettings({
    required String language,
    required bool discoverable,
    required AccountSafetySettings accountSafety,
  }) async {
    final uid = _uid;
    final batch = firestore.batch();
    batch.update(firestore.collection('users').doc(uid), {
      'language': language,
      'discoverable': discoverable,
      'accountSafety': accountSafety.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      firestore.collection('safeProfiles').doc(uid),
      {'language': language},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Stream<List<Friendship>> watchFriendships() {
    final uid = _uid;
    return firestore
        .collection('friendships')
        .where('userIds', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final friendships =
          snapshot.docs.map(Friendship.fromFirestore).toList(growable: false);
      friendships
          .sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0)).compareTo(
                a.updatedAt ?? a.createdAt ?? DateTime(0),
              ));
      return friendships;
    });
  }

  Future<String> sendFriendRequest({String? username, String? recipientUid}) {
    return _callWithStatus('sendFriendRequest', {
      if (username != null) 'username': username,
      if (recipientUid != null) 'recipientUid': recipientUid,
    });
  }

  Future<void> acceptFriendRequest(String friendshipId) =>
      _callVoid('acceptFriendRequest', {'friendshipId': friendshipId});

  Future<void> blockUser(String otherUid) =>
      _callVoid('blockUser', {'otherUid': otherUid});

  Future<void> reportUser({
    required String otherUid,
    required String reason,
  }) =>
      _callVoid('reportUser', {
        'otherUid': otherUid,
        'reason': reason,
      });

  Stream<List<WorkoutShare>> watchInbox({int limit = 50}) {
    return firestore
        .collection('workoutShares')
        .where('recipientUid', isEqualTo: _uid)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(WorkoutShare.fromFirestore)
            .toList(growable: false));
  }

  Stream<List<WorkoutShare>> watchSentShares({int limit = 50}) {
    return firestore
        .collection('workoutShares')
        .where('senderUid', isEqualTo: _uid)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(WorkoutShare.fromFirestore)
            .toList(growable: false));
  }

  Stream<List<WorkoutShare>> watchSentSharesForSource(
    String workoutSourceKey, {
    int limit = 100,
  }) {
    return firestore
        .collection('workoutShares')
        .where('senderUid', isEqualTo: _uid)
        .where('workoutSourceKey', isEqualTo: workoutSourceKey)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(WorkoutShare.fromFirestore)
            .toList(growable: false));
  }

  Stream<List<SocialEvent>> watchSocialEvents({int limit = 50}) {
    return firestore
        .collection('socialEvents')
        .where('userIds', arrayContains: _uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(SocialEvent.fromFirestore)
            .toList(growable: false));
  }

  Stream<SocialStats> watchSocialStats() {
    final uid = _uid;
    return firestore
        .collection('socialStats')
        .doc(uid)
        .snapshots()
        .map(SocialStats.fromFirestore);
  }

  Future<WorkoutShare> loadWorkoutShare(String shareId) async {
    final snapshot =
        await firestore.collection('workoutShares').doc(shareId).get();
    if (!snapshot.exists) {
      throw const AccountException('That shared workout is unavailable.');
    }
    final share = WorkoutShare.fromFirestore(snapshot);
    if (share.senderUid != _uid && share.recipientUid != _uid) {
      throw const AccountException('That shared workout is unavailable.');
    }
    return share;
  }

  Future<WorkoutShareSendResult> shareWorkout({
    required String recipientUid,
    required String workoutSourceKey,
    required WorkoutSnapshot workoutSnapshot,
    String? message,
  }) async {
    final normalizedRecipientUid = recipientUid.trim();
    final batch = await shareWorkoutWithRecipients(
      recipientUids: [normalizedRecipientUid],
      workoutSourceKey: workoutSourceKey,
      workoutSnapshot: workoutSnapshot,
      message: message,
    );
    final result = batch.byRecipient[normalizedRecipientUid];
    if (result != null) return result;
    throw const AccountException('Firebase did not return a workout share.');
  }

  Future<WorkoutShareBatchSendResult> shareWorkoutWithRecipients({
    required Iterable<String> recipientUids,
    required String workoutSourceKey,
    required WorkoutSnapshot workoutSnapshot,
    String? message,
  }) async {
    final recipients = recipientUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (recipients.isEmpty) {
      throw const AccountException('Choose at least one teammate.');
    }
    if (recipients.length > workoutShareRecipientLimit) {
      throw const AccountException(
        'Choose no more than $workoutShareRecipientLimit teammates at once.',
      );
    }
    final result = await functions.httpsCallable('sendWorkout').call({
      'recipientUids': recipients,
      'workoutSourceKey': workoutSourceKey,
      'workoutSnapshot': workoutSnapshot.toFirestore(),
      if (message?.trim().isNotEmpty == true) 'senderMessage': message!.trim(),
    });
    final sendResult = WorkoutShareBatchSendResult.fromCallable(result.data);
    if (sendResult.byRecipient.length == recipients.length) return sendResult;
    throw const AccountException(
      'Firebase did not return every workout share.',
    );
  }

  Future<void> acceptWorkoutShare(String shareId) =>
      _callVoid('acceptWorkoutShare', {'shareId': shareId});

  Future<void> scheduleWorkoutShare(String shareId, DateTime scheduledFor) =>
      _callVoid('scheduleWorkoutShare', {
        'shareId': shareId,
        'scheduledForMillis': scheduledFor.toUtc().millisecondsSinceEpoch,
      });

  Future<void> startWorkoutShare(String shareId) =>
      _callVoid('startWorkoutShare', {'shareId': shareId});

  Future<void> saveWorkoutShare(String shareId) =>
      _callVoid('saveWorkoutShare', {'shareId': shareId});

  Future<void> removeWorkoutSchedule(String shareId) =>
      _callVoid('removeWorkoutSchedule', {'shareId': shareId});

  Future<void> declineWorkoutShare(String shareId) =>
      _callVoid('declineWorkoutShare', {'shareId': shareId});

  Future<SocialCompletionReward> completeWorkoutShare(
    String shareId,
    WorkoutResultSummary result,
  ) async {
    final response =
        await functions.httpsCallable('completeWorkoutShare').call({
      'shareId': shareId,
      'resultSummary': result.toMap(),
    });
    return SocialCompletionReward.fromCallable(response.data);
  }

  Future<void> reactToWorkoutShare(String shareId, String reaction) =>
      _callVoid('reactToWorkoutShare', {
        'shareId': shareId,
        'reaction': reaction,
      });

  Future<void> markWorkoutSharesRead(Iterable<String> shareIds) =>
      _callVoid('markWorkoutSharesRead', {
        'shareIds': shareIds.toSet().take(100).toList(growable: false),
      });

  Future<String> _callWithStatus(
    String callableName,
    Map<String, dynamic> data,
  ) async {
    final result = await functions.httpsCallable(callableName).call(data);
    final value = result.data;
    if (value is Map && value['status'] is String) {
      return value['status'] as String;
    }
    return 'ok';
  }

  Future<void> _callVoid(
    String callableName,
    Map<String, dynamic> data,
  ) async {
    await functions.httpsCallable(callableName).call<void>(data);
  }
}
