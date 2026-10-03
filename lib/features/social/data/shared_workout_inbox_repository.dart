import 'package:cloud_firestore/cloud_firestore.dart';

import '../../account/account_models.dart';
import '../models/shared_workout_inbox_models.dart';
import '../social_models.dart';
import '../social_repository.dart';

class SharedWorkoutInboxCursor {
  const SharedWorkoutInboxCursor(this.document);

  final DocumentSnapshot<Map<String, dynamic>> document;
}

class SharedWorkoutInboxPage {
  const SharedWorkoutInboxPage({
    required this.shares,
    required this.isFromCache,
    this.nextCursor,
  });

  final List<WorkoutShare> shares;
  final SharedWorkoutInboxCursor? nextCursor;
  final bool isFromCache;
}

class SharedWorkoutLiveUpdate {
  const SharedWorkoutLiveUpdate({
    required this.shares,
    required this.isFromCache,
  });

  final List<WorkoutShare> shares;
  final bool isFromCache;
}

class SharedWorkoutInboxRepository {
  const SharedWorkoutInboxRepository(this._socialRepository);

  final SocialRepository _socialRepository;

  String get _uid {
    final uid = _socialRepository.auth.currentUser?.uid;
    if (uid == null) throw const AccountException('Sign in first.');
    return uid;
  }

  FirebaseFirestore get _firestore => _socialRepository.firestore;

  Future<SharedWorkoutInboxPage> loadPage(
    SharedWorkoutInboxSection section, {
    SharedWorkoutInboxCursor? after,
    int limit = sharedWorkoutInboxPageSize,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('workoutShares')
        .where('recipientUid', isEqualTo: _uid);
    final statusNames = section.statuses.map((status) => status.name).toList();
    query = statusNames.length == 1
        ? query.where('status', isEqualTo: statusNames.single)
        : query.where('status', whereIn: statusNames);
    query = query.orderBy(section.orderField, descending: section.descending);
    if (after != null) query = query.startAfterDocument(after.document);
    final snapshot = await query.limit(limit).get();
    return SharedWorkoutInboxPage(
      shares:
          snapshot.docs.map(WorkoutShare.fromFirestore).toList(growable: false),
      nextCursor: snapshot.docs.isEmpty
          ? after
          : SharedWorkoutInboxCursor(snapshot.docs.last),
      isFromCache: snapshot.metadata.isFromCache,
    );
  }

  Stream<SharedWorkoutLiveUpdate> watchRecentUnread({
    int limit = sharedWorkoutInboxPageSize,
  }) {
    return _firestore
        .collection('workoutShares')
        .where('recipientUid', isEqualTo: _uid)
        .where('recipientReadAt', isNull: true)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => SharedWorkoutLiveUpdate(
            shares: snapshot.docs
                .map(WorkoutShare.fromFirestore)
                .toList(growable: false),
            isFromCache: snapshot.metadata.isFromCache,
          ),
        );
  }

  Future<List<SocialUserProfile>> loadSenderProfiles(
    Iterable<String> senderUids,
  ) {
    return _socialRepository.loadProfiles(senderUids);
  }

  Future<WorkoutShare> loadShare(String shareId) async {
    final snapshot =
        await _firestore.collection('workoutShares').doc(shareId).get();
    if (!snapshot.exists) {
      throw const AccountException('That shared workout is unavailable.');
    }
    final share = WorkoutShare.fromFirestore(snapshot);
    if (share.senderUid != _uid && share.recipientUid != _uid) {
      throw const AccountException('That shared workout is unavailable.');
    }
    return share;
  }

  Future<void> markRead(String shareId) =>
      _socialRepository.markWorkoutSharesRead([shareId]);

  Future<void> acceptAndSchedule(String shareId, DateTime scheduledFor) =>
      _socialRepository.scheduleWorkoutShare(shareId, scheduledFor);

  Future<void> removeSchedule(String shareId) =>
      _socialRepository.removeWorkoutSchedule(shareId);

  Future<void> saveForLater(String shareId) =>
      _socialRepository.saveWorkoutShare(shareId);

  Future<void> decline(String shareId) =>
      _socialRepository.declineWorkoutShare(shareId);

  Future<void> sendFistBump(String shareId) =>
      _socialRepository.reactToWorkoutShare(shareId, 'fist_bump');
}
