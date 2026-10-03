import 'package:flutter/foundation.dart';

import '../social_models.dart';
import '../workout_snapshot.dart';

const sharedWorkoutInboxPageSize = 20;

enum SharedWorkoutInboxSection { newWorkouts, scheduled, completed }

extension SharedWorkoutInboxSectionStatus on SharedWorkoutInboxSection {
  List<WorkoutShareStatus> get statuses => switch (this) {
        SharedWorkoutInboxSection.newWorkouts => const [
            WorkoutShareStatus.sent,
            WorkoutShareStatus.accepted,
            WorkoutShareStatus.started,
          ],
        SharedWorkoutInboxSection.scheduled => const [
            WorkoutShareStatus.scheduled,
          ],
        SharedWorkoutInboxSection.completed => const [
            WorkoutShareStatus.completed,
          ],
      };

  bool includes(WorkoutShare share) => statuses.contains(share.status);

  String get orderField => switch (this) {
        SharedWorkoutInboxSection.newWorkouts => 'sentAt',
        SharedWorkoutInboxSection.scheduled => 'scheduledFor',
        SharedWorkoutInboxSection.completed => 'completedAt',
      };

  bool get descending => this != SharedWorkoutInboxSection.scheduled;
}

SharedWorkoutInboxSection? sectionForWorkoutShare(WorkoutShare share) {
  for (final section in SharedWorkoutInboxSection.values) {
    if (section.includes(share)) return section;
  }
  return null;
}

@immutable
class SharedWorkoutSectionState {
  const SharedWorkoutSectionState({
    this.shares = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<WorkoutShare> shares;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  SharedWorkoutSectionState copyWith({
    List<WorkoutShare>? shares,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error = _unset,
  }) {
    return SharedWorkoutSectionState(
      shares: shares ?? this.shares,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: identical(error, _unset) ? this.error : error,
    );
  }
}

@immutable
class SharedWorkoutInboxState {
  const SharedWorkoutInboxState({
    required this.sections,
    this.senderProfiles = const {},
    this.busyShareIds = const {},
    this.isOffline = false,
    this.liveError,
  });

  factory SharedWorkoutInboxState.initial() => SharedWorkoutInboxState(
        sections: Map.unmodifiable({
          for (final section in SharedWorkoutInboxSection.values)
            section: const SharedWorkoutSectionState(),
        }),
      );

  final Map<SharedWorkoutInboxSection, SharedWorkoutSectionState> sections;
  final Map<String, SocialUserProfile> senderProfiles;
  final Set<String> busyShareIds;
  final bool isOffline;
  final Object? liveError;

  SharedWorkoutSectionState section(SharedWorkoutInboxSection section) =>
      sections[section] ?? const SharedWorkoutSectionState();

  SharedWorkoutInboxState copyWith({
    Map<SharedWorkoutInboxSection, SharedWorkoutSectionState>? sections,
    Map<String, SocialUserProfile>? senderProfiles,
    Set<String>? busyShareIds,
    bool? isOffline,
    Object? liveError = _unset,
  }) {
    return SharedWorkoutInboxState(
      sections: sections ?? this.sections,
      senderProfiles: senderProfiles ?? this.senderProfiles,
      busyShareIds: busyShareIds ?? this.busyShareIds,
      isOffline: isOffline ?? this.isOffline,
      liveError: identical(liveError, _unset) ? this.liveError : liveError,
    );
  }
}

List<WorkoutShare> mergeWorkoutShares(
  Iterable<WorkoutShare> existing,
  Iterable<WorkoutShare> incoming,
) {
  final byId = <String, WorkoutShare>{
    for (final share in existing) share.id: share,
    for (final share in incoming) share.id: share,
  };
  final shares = byId.values.toList(growable: false);
  shares.sort((a, b) {
    final aTime = a.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bTime.compareTo(aTime);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  return List.unmodifiable(shares);
}

List<WorkoutShare> sortWorkoutSharesForSection(
  SharedWorkoutInboxSection section,
  Iterable<WorkoutShare> source,
) {
  final shares = source.toList(growable: false);
  shares.sort((a, b) {
    final aTime = _sectionTime(section, a);
    final bTime = _sectionTime(section, b);
    final byTime =
        section.descending ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  return List.unmodifiable(shares);
}

DateTime _sectionTime(
  SharedWorkoutInboxSection section,
  WorkoutShare share,
) {
  final fallback = share.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return switch (section) {
    SharedWorkoutInboxSection.newWorkouts => fallback,
    SharedWorkoutInboxSection.scheduled =>
      share.scheduledFor ?? DateTime.utc(9999),
    SharedWorkoutInboxSection.completed => share.completedAt ?? fallback,
  };
}

String workoutMovementSummary(
  WorkoutSnapshot snapshot, {
  int maxMovements = 3,
}) {
  final movements = snapshot.enabledCalloutIds
      .map(_humanizeMovement)
      .take(maxMovements)
      .toList(growable: false);
  final remaining = snapshot.enabledCalloutIds.length - movements.length;
  if (movements.isEmpty) return 'Custom movements';
  return [
    ...movements,
    if (remaining > 0) '+$remaining',
  ].join(' • ');
}

String _humanizeMovement(String id) {
  return id
      .split(RegExp(r'[_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

const _unset = Object();
