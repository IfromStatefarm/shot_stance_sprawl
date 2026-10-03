import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/workout_reminder_notifications.dart';
import '../data/shared_workout_inbox_repository.dart';
import '../models/shared_workout_inbox_models.dart';
import '../social_models.dart';
import '../social_providers.dart';

final sharedWorkoutInboxRepositoryProvider =
    Provider<SharedWorkoutInboxRepository>((ref) {
  return SharedWorkoutInboxRepository(ref.watch(socialRepositoryProvider));
});

final sharedWorkoutInboxControllerProvider = NotifierProvider.autoDispose<
    SharedWorkoutInboxController, SharedWorkoutInboxState>(
  SharedWorkoutInboxController.new,
);

class SharedWorkoutInboxController
    extends AutoDisposeNotifier<SharedWorkoutInboxState> {
  late SharedWorkoutInboxRepository _repository;
  late WorkoutReminderNotifications _reminderNotifications;
  StreamSubscription<SharedWorkoutLiveUpdate>? _recentSubscription;
  final Map<SharedWorkoutInboxSection, SharedWorkoutInboxCursor?> _cursors = {};
  List<WorkoutShare> _recentUnread = const [];

  @override
  SharedWorkoutInboxState build() {
    _repository = ref.watch(sharedWorkoutInboxRepositoryProvider);
    _reminderNotifications = ref.watch(workoutReminderNotificationsProvider);
    _recentSubscription = _repository.watchRecentUnread().listen(
          _applyLiveUpdate,
          onError: _handleLiveError,
        );
    ref.onDispose(() => unawaited(_recentSubscription?.cancel()));
    Future<void>.microtask(refresh);
    return SharedWorkoutInboxState.initial();
  }

  Future<void> refresh() async {
    _cursors.clear();
    final nextSections = <SharedWorkoutInboxSection, SharedWorkoutSectionState>{
      for (final section in SharedWorkoutInboxSection.values)
        section: state.section(section).copyWith(
              isLoading: true,
              isLoadingMore: false,
              hasMore: true,
              error: null,
            ),
    };
    state = state.copyWith(sections: Map.unmodifiable(nextSections));
    await Future.wait(
      SharedWorkoutInboxSection.values.map(
        (section) => _loadSection(section, reset: true),
      ),
    );
  }

  Future<void> retry(SharedWorkoutInboxSection section) =>
      _loadSection(section, reset: state.section(section).shares.isEmpty);

  Future<void> loadMore(SharedWorkoutInboxSection section) async {
    final current = state.section(section);
    if (current.isLoading || current.isLoadingMore || !current.hasMore) return;
    _setSection(section, current.copyWith(isLoadingMore: true, error: null));
    await _loadSection(section, reset: false);
  }

  Future<WorkoutShare> loadShare(String shareId) async {
    final share = await _repository.loadShare(shareId);
    _replaceShare(share);
    await _ensureSenderProfiles([share]);
    return share;
  }

  Future<void> _loadSection(
    SharedWorkoutInboxSection section, {
    required bool reset,
  }) async {
    final prior = state.section(section);
    try {
      final page = await _repository.loadPage(
        section,
        after: reset ? null : _cursors[section],
      );
      _cursors[section] = page.nextCursor;
      final liveShares = _recentUnread.where(section.includes);
      final shares = sortWorkoutSharesForSection(
        section,
        mergeWorkoutShares(
          reset ? liveShares : state.section(section).shares,
          page.shares.where(section.includes),
        ).where(section.includes),
      );
      _setSection(
        section,
        prior.copyWith(
          shares: shares,
          isLoading: false,
          isLoadingMore: false,
          hasMore: page.shares.length >= sharedWorkoutInboxPageSize,
          error: null,
        ),
      );
      state = state.copyWith(isOffline: page.isFromCache);
      await _ensureSenderProfiles(page.shares);
    } catch (error) {
      final latest = state.section(section);
      _setSection(
        section,
        latest.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: error,
        ),
      );
      if (_isOfflineError(error)) state = state.copyWith(isOffline: true);
    }
  }

  void _applyLiveUpdate(SharedWorkoutLiveUpdate update) {
    _recentUnread = List.unmodifiable(update.shares);
    var sections =
        Map<SharedWorkoutInboxSection, SharedWorkoutSectionState>.from(
      state.sections,
    );
    for (final share in update.shares) {
      for (final section in SharedWorkoutInboxSection.values) {
        final current = sections[section] ?? const SharedWorkoutSectionState();
        final withoutShare =
            current.shares.where((item) => item.id != share.id);
        sections[section] = current.copyWith(
          shares: section.includes(share)
              ? sortWorkoutSharesForSection(
                  section,
                  mergeWorkoutShares(withoutShare, [share]),
                )
              : List.unmodifiable(withoutShare),
        );
      }
    }
    state = state.copyWith(
      sections: Map.unmodifiable(sections),
      isOffline: update.isFromCache,
      liveError: null,
    );
    unawaited(_ensureSenderProfiles(update.shares));
  }

  void _handleLiveError(Object error, StackTrace stackTrace) {
    state = state.copyWith(
      liveError: error,
      isOffline: state.isOffline || _isOfflineError(error),
    );
  }

  Future<void> _ensureSenderProfiles(Iterable<WorkoutShare> shares) async {
    final missingUids = shares
        .expand((share) => [share.senderUid, share.recipientUid])
        .where(
            (uid) => uid.isNotEmpty && !state.senderProfiles.containsKey(uid))
        .toSet();
    if (missingUids.isEmpty) return;
    try {
      final profiles = await _repository.loadSenderProfiles(missingUids);
      if (profiles.isEmpty) return;
      state = state.copyWith(
        senderProfiles: Map.unmodifiable({
          ...state.senderProfiles,
          for (final profile in profiles) profile.uid: profile,
        }),
      );
    } catch (_) {
      // A safe "friend" fallback remains visible if profiles are unavailable.
    }
  }

  Future<void> markRead(WorkoutShare share) async {
    if (share.recipientReadAt != null) return;
    try {
      await _repository.markRead(share.id);
      _patchExistingShare(
        share.id,
        (current) => current.copyWith(recipientReadAt: DateTime.now()),
      );
    } catch (error) {
      if (_isOfflineError(error)) state = state.copyWith(isOffline: true);
    }
  }

  Future<void> acceptAndSchedule(WorkoutShare share, DateTime scheduledFor) {
    return _runAction(share.id, () async {
      await _repository.acceptAndSchedule(share.id, scheduledFor);
      _patchShare(
        share,
        (current) => current.copyWith(
          status: WorkoutShareStatus.scheduled,
          scheduledFor: scheduledFor,
        ),
      );
    });
  }

  Future<void> removeSchedule(WorkoutShare share) {
    return _runAction(share.id, () async {
      await _repository.removeSchedule(share.id);
      await _reminderNotifications.cancelFriendWorkout(share.id);
      _patchShare(
        share,
        (current) => current.copyWith(
          status: WorkoutShareStatus.accepted,
          scheduledFor: null,
        ),
      );
    });
  }

  Future<void> saveForLater(WorkoutShare share) {
    return _runAction(share.id, () async {
      await _repository.saveForLater(share.id);
      await _reminderNotifications.cancelFriendWorkout(share.id);
      _patchShare(
        share,
        (current) => current.copyWith(
          status: WorkoutShareStatus.accepted,
          scheduledFor: null,
          startedAt: null,
        ),
      );
    });
  }

  Future<void> decline(WorkoutShare share) {
    return _runAction(share.id, () async {
      await _repository.decline(share.id);
      await _reminderNotifications.cancelFriendWorkout(share.id);
      _patchShare(
        share,
        (current) => current.copyWith(
          status: WorkoutShareStatus.declined,
          declinedAt: DateTime.now(),
          recipientReadAt: current.recipientReadAt ?? DateTime.now(),
        ),
      );
    });
  }

  Future<void> sendFistBump(WorkoutShare share) {
    return _runAction(share.id, () => _repository.sendFistBump(share.id));
  }

  Future<void> _runAction(
    String shareId,
    Future<void> Function() action,
  ) async {
    state = state.copyWith(
      busyShareIds: Set.unmodifiable({...state.busyShareIds, shareId}),
    );
    try {
      await action();
    } catch (error) {
      if (_isOfflineError(error)) state = state.copyWith(isOffline: true);
      rethrow;
    } finally {
      state = state.copyWith(
        busyShareIds: Set.unmodifiable(
          state.busyShareIds.where((id) => id != shareId),
        ),
      );
    }
  }

  void _replaceShare(WorkoutShare share) {
    final target = sectionForWorkoutShare(share);
    final sections = <SharedWorkoutInboxSection, SharedWorkoutSectionState>{};
    for (final section in SharedWorkoutInboxSection.values) {
      final current = state.section(section);
      final withoutShare = current.shares.where((item) => item.id != share.id);
      sections[section] = current.copyWith(
        shares: target == section
            ? sortWorkoutSharesForSection(
                section,
                mergeWorkoutShares(withoutShare, [share]),
              )
            : List.unmodifiable(withoutShare),
      );
    }
    state = state.copyWith(sections: Map.unmodifiable(sections));
  }

  void _patchShare(
    WorkoutShare fallback,
    WorkoutShare Function(WorkoutShare current) update,
  ) {
    final current = _findShare(fallback.id) ?? fallback;
    _replaceShare(update(current));
  }

  void _patchExistingShare(
    String shareId,
    WorkoutShare Function(WorkoutShare current) update,
  ) {
    final current = _findShare(shareId);
    if (current != null) _replaceShare(update(current));
  }

  WorkoutShare? _findShare(String shareId) {
    for (final section in SharedWorkoutInboxSection.values) {
      for (final share in state.section(section).shares) {
        if (share.id == shareId) return share;
      }
    }
    return null;
  }

  void _setSection(
    SharedWorkoutInboxSection section,
    SharedWorkoutSectionState value,
  ) {
    state = state.copyWith(
      sections: Map.unmodifiable({...state.sections, section: value}),
    );
  }
}

bool _isOfflineError(Object error) {
  return error is FirebaseException &&
      (error.code == 'unavailable' || error.code == 'network-request-failed');
}
