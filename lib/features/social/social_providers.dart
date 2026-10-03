import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account.dart';
import 'device_registration_service.dart';
import 'social_models.dart';
import 'social_repository.dart';
import 'team_repository.dart';

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  if (!ref.watch(firebaseAvailabilityProvider)) {
    throw const AccountException(
      'Firebase is unavailable. Local workouts are still available.',
    );
  }
  return SocialRepository();
});

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  if (!ref.watch(firebaseAvailabilityProvider)) {
    throw const AccountException('Firebase is unavailable.');
  }
  return TeamRepository();
});

final teamMembershipProvider = StreamProvider<TeamMembership?>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(null);
  return ref.watch(teamRepositoryProvider).watchMembership();
});

final currentTeamProvider = StreamProvider<Team?>((ref) {
  final membership = ref.watch(teamMembershipProvider).asData?.value;
  if (membership == null) return Stream.value(null);
  return ref.watch(teamRepositoryProvider).watchTeam(membership.teamId);
});

final teamMemberIdsProvider = StreamProvider<List<String>>((ref) {
  final membership = ref.watch(teamMembershipProvider).asData?.value;
  if (membership == null) return Stream.value(const []);
  return ref.watch(teamRepositoryProvider).watchMemberIds(membership.teamId);
});

final teamAccessCodeProvider = StreamProvider<String?>((ref) {
  final membership = ref.watch(teamMembershipProvider).asData?.value;
  if (membership == null || !membership.isOwner) return Stream.value(null);
  return ref.watch(teamRepositoryProvider).watchAccessCode(membership.teamId);
});

final socialProfileProvider = StreamProvider<SocialUserProfile?>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(null);
  return ref.watch(socialRepositoryProvider).watchMyProfile();
});

final friendshipsProvider = StreamProvider<List<Friendship>>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchFriendships();
});

final workoutInboxProvider = StreamProvider<List<WorkoutShare>>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchInbox();
});

final sentWorkoutSharesProvider = StreamProvider<List<WorkoutShare>>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchSentShares();
});

final sentWorkoutSharesForSourceProvider = StreamProvider.autoDispose
    .family<List<WorkoutShare>, String>((ref, workoutSourceKey) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(const []);
  return ref
      .watch(socialRepositoryProvider)
      .watchSentSharesForSource(workoutSourceKey);
});

final socialStatsProvider = StreamProvider<SocialStats?>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(null);
  return ref.watch(socialRepositoryProvider).watchSocialStats();
});

final socialEventsProvider = StreamProvider<List<SocialEvent>>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchSocialEvents();
});

/// Watching this provider keeps the signed-in device's FCM document current.
final deviceRegistrationProvider = Provider<void>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null || !ref.watch(firebaseAvailabilityProvider)) return;
  final service = DeviceRegistrationService();
  ref.onDispose(() => unawaited(service.dispose()));
  unawaited(
    service.start(identity.uid).catchError((Object error) {
      debugPrint('FCM device registration is unavailable: $error');
    }),
  );
});

/// Repairs trusted friend-profile access projections created before the
/// current rules. The callable is idempotent and runs once per signed-in user.
final friendAccessSyncProvider = Provider<void>((ref) {
  final identity = ref.watch(accountIdentityProvider).asData?.value;
  if (identity == null || !ref.watch(firebaseAvailabilityProvider)) return;
  unawaited(
    ref
        .watch(socialRepositoryProvider)
        .syncFriendAccess()
        .catchError((Object error) {
      debugPrint('Friend profile access sync is unavailable: $error');
    }),
  );
});
