import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account.dart';
import '../../drill/presentation/drill_runner_screen.dart';
import '../../drill/providers.dart';
import '../../onboarding/onboarding_feature.dart';
import '../application/shared_workout_inbox_controller.dart';
import '../models/shared_workout_inbox_models.dart';
import '../social_models.dart';

class SharedWorkoutInboxScreen extends ConsumerStatefulWidget {
  const SharedWorkoutInboxScreen({super.key, this.initialShareId});

  final String? initialShareId;

  @override
  ConsumerState<SharedWorkoutInboxScreen> createState() =>
      _SharedWorkoutInboxScreenState();
}

class _SharedWorkoutInboxScreenState
    extends ConsumerState<SharedWorkoutInboxScreen> {
  bool _openedInitialShare = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openInitialShare());
    });
  }

  Future<void> _openInitialShare() async {
    final shareId = widget.initialShareId?.trim();
    if (_openedInitialShare || shareId == null || shareId.isEmpty) return;
    _openedInitialShare = true;
    try {
      final share = await ref
          .read(sharedWorkoutInboxControllerProvider.notifier)
          .loadShare(shareId);
      if (!mounted) return;
      await _openWorkout(share, ref.read(languageProvider) == 'es');
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = ref.watch(languageProvider) == 'es';
    final inbox = ref.watch(sharedWorkoutInboxControllerProvider);
    return DefaultTabController(
      length: SharedWorkoutInboxSection.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEs ? 'Workouts compartidos' : 'Shared workouts'),
          bottom: TabBar(
            tabs: [
              _InboxTab(
                label: isEs ? 'Nuevos' : 'New',
                count: inbox
                    .section(SharedWorkoutInboxSection.newWorkouts)
                    .shares
                    .length,
              ),
              _InboxTab(
                label: isEs ? 'Programados' : 'Scheduled',
                count: inbox
                    .section(SharedWorkoutInboxSection.scheduled)
                    .shares
                    .length,
              ),
              _InboxTab(
                label: isEs ? 'Completados' : 'Completed',
                count: inbox
                    .section(SharedWorkoutInboxSection.completed)
                    .shares
                    .length,
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            if (inbox.isOffline)
              _InboxBanner(
                icon: Icons.cloud_off_outlined,
                text: isEs
                    ? 'Sin conexion. Mostrando workouts guardados.'
                    : 'Offline. Showing saved workouts.',
              )
            else if (inbox.liveError != null)
              _InboxBanner(
                icon: Icons.sync_problem_outlined,
                text: isEs
                    ? 'Las actualizaciones en vivo estan pausadas.'
                    : 'Live updates are temporarily paused.',
              ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final section in SharedWorkoutInboxSection.values)
                    _InboxSectionView(
                      section: section,
                      state: inbox.section(section),
                      senderProfiles: inbox.senderProfiles,
                      isOffline: inbox.isOffline,
                      isEs: isEs,
                      onRefresh: () => ref
                          .read(sharedWorkoutInboxControllerProvider.notifier)
                          .refresh(),
                      onRetry: () => ref
                          .read(sharedWorkoutInboxControllerProvider.notifier)
                          .retry(section),
                      onLoadMore: () => ref
                          .read(sharedWorkoutInboxControllerProvider.notifier)
                          .loadMore(section),
                      onOpen: (share) => _openWorkout(share, isEs),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWorkout(WorkoutShare share, bool isEs) async {
    final currentUid = ref.read(accountIdentityProvider).asData?.value?.uid;
    if (currentUid == share.recipientUid) {
      unawaited(
        ref.read(sharedWorkoutInboxControllerProvider.notifier).markRead(share),
      );
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _WorkoutDetailsSheet(
        share: share,
        isEs: isEs,
        onStartNow: () => _startNow(share, sheetContext),
        onSchedule: () => _schedule(share, sheetContext, isEs),
        onRemoveSchedule: () => _removeSchedule(share, sheetContext, isEs),
        onSaveForLater: () => _saveForLater(share, sheetContext, isEs),
        onDecline: () => _decline(share, sheetContext, isEs),
        onFistBump: () => _sendFistBump(share, isEs),
      ),
    );
  }

  Future<void> _startNow(
    WorkoutShare share,
    BuildContext sheetContext,
  ) async {
    if (!mounted) return;
    ref
        .read(drillConfigProvider.notifier)
        .applySharedWorkout(share.workoutSnapshot.toDrillConfig());
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DrillRunnerScreen(workoutShareId: share.id),
      ),
    );
  }

  Future<void> _schedule(
    WorkoutShare share,
    BuildContext sheetContext,
    bool isEs,
  ) async {
    final now = DateTime.now();
    final initial = share.scheduledFor?.toLocal() ??
        DateTime(now.year, now.month, now.day + 1, 18);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final scheduledFor = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!scheduledFor.isAfter(now)) {
      _showMessage(
        isEs ? 'Elige una hora futura.' : 'Choose a future time.',
      );
      return;
    }
    try {
      await ref
          .read(sharedWorkoutInboxControllerProvider.notifier)
          .acceptAndSchedule(share, scheduledFor);
      if (!mounted) return;
      final inbox = ref.read(sharedWorkoutInboxControllerProvider);
      final permissionGranted = await const NotificationPermissionPrompter()
          .requestWorkoutReminderPermission();
      final reminderScheduled = permissionGranted &&
          await ref
              .read(workoutReminderNotificationsProvider)
              .scheduleFriendWorkout(
                shareId: share.id,
                workoutTitle: isEs
                    ? share.workoutSnapshot.titleEs
                    : share.workoutSnapshot.titleEn,
                scheduledFor: scheduledFor,
                senderName: inbox.senderProfiles[share.senderUid]?.displayName,
                isEs: isEs,
              );
      if (!mounted) return;
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      _showMessage(
        reminderScheduled
            ? (isEs
                ? 'Workout programado. Te avisaremos antes.'
                : 'Workout scheduled. We’ll remind you beforehand.')
            : (isEs
                ? 'Workout programado. Los avisos estan desactivados.'
                : 'Workout scheduled. Notifications are off.'),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _removeSchedule(
    WorkoutShare share,
    BuildContext sheetContext,
    bool isEs,
  ) async {
    try {
      await ref
          .read(sharedWorkoutInboxControllerProvider.notifier)
          .removeSchedule(share);
      if (!mounted) return;
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      _showMessage(
        isEs
            ? 'Horario eliminado. El workout esta en Nuevos.'
            : 'Schedule removed. The workout is back in New.',
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _saveForLater(
    WorkoutShare share,
    BuildContext sheetContext,
    bool isEs,
  ) async {
    try {
      await ref
          .read(sharedWorkoutInboxControllerProvider.notifier)
          .saveForLater(share);
      if (!mounted) return;
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      _showMessage(
        isEs ? 'Guardado en Nuevos para despues.' : 'Saved in New for later.',
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _decline(
    WorkoutShare share,
    BuildContext sheetContext,
    bool isEs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEs ? 'Rechazar workout?' : 'Decline workout?'),
        content: Text(
          isEs
              ? 'Se quitara de tu inbox.'
              : 'It will be removed from your inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isEs ? 'Rechazar' : 'Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(sharedWorkoutInboxControllerProvider.notifier)
          .decline(share);
      if (!mounted) return;
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      _showMessage(isEs ? 'Workout rechazado.' : 'Workout declined.');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _sendFistBump(WorkoutShare share, bool isEs) async {
    try {
      await ref
          .read(sharedWorkoutInboxControllerProvider.notifier)
          .sendFistBump(share);
      _showMessage(isEs ? 'Punito enviado.' : 'Fist bump sent.');
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) => _showMessage(accountErrorMessage(error));

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InboxSectionView extends StatelessWidget {
  const _InboxSectionView({
    required this.section,
    required this.state,
    required this.senderProfiles,
    required this.isOffline,
    required this.isEs,
    required this.onRefresh,
    required this.onRetry,
    required this.onLoadMore,
    required this.onOpen,
  });

  final SharedWorkoutInboxSection section;
  final SharedWorkoutSectionState state;
  final Map<String, SocialUserProfile> senderProfiles;
  final bool isOffline;
  final bool isEs;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final ValueChanged<WorkoutShare> onOpen;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.shares.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.shares.isEmpty) {
      return _InboxStateMessage(
        icon: isOffline ? Icons.cloud_off_outlined : Icons.error_outline,
        title: isOffline
            ? (isEs ? 'Estas sin conexion' : 'You are offline')
            : (isEs ? 'No pudimos cargar el inbox' : 'Could not load inbox'),
        subtitle: isOffline
            ? (isEs
                ? 'Conectate para descargar estos workouts.'
                : 'Connect to download these workouts.')
            : accountErrorMessage(state.error!),
        buttonLabel: isEs ? 'Reintentar' : 'Retry',
        onPressed: onRetry,
      );
    }
    if (state.shares.isEmpty) {
      return _InboxStateMessage(
        icon: _emptyIcon(section),
        title: _emptyTitle(section, isEs),
        subtitle: _emptySubtitle(section, isEs),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 420 &&
              state.hasMore &&
              !state.isLoadingMore) {
            onLoadMore();
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
          itemCount: state.shares.length + 1,
          itemBuilder: (context, index) {
            if (index == state.shares.length) {
              return _PaginationFooter(
                state: state,
                isEs: isEs,
                onRetry: onRetry,
              );
            }
            final share = state.shares[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SharedWorkoutCard(
                share: share,
                sender: senderProfiles[share.senderUid],
                isEs: isEs,
                onTap: () => onOpen(share),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SharedWorkoutCard extends StatelessWidget {
  const _SharedWorkoutCard({
    required this.share,
    required this.sender,
    required this.isEs,
    required this.onTap,
  });

  final WorkoutShare share;
  final SocialUserProfile? sender;
  final bool isEs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final snapshot = share.workoutSnapshot;
    final unread = share.recipientReadAt == null;
    return Card(
      elevation: unread ? 2 : 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: unread
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: unread ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    foregroundImage: sender?.photoUrl?.isNotEmpty == true
                        ? NetworkImage(sender!.photoUrl!)
                        : null,
                    child: sender?.photoUrl?.isNotEmpty == true
                        ? null
                        : const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender?.displayName ??
                              (isEs ? 'Un integrante' : 'A teammate'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _receivedLabel(share.sentAt, isEs),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (unread) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _WorkoutStatusChip(status: share.status, isEs: isEs),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isEs ? snapshot.titleEs : snapshot.titleEn,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _WorkoutFact(
                    icon: Icons.timer_outlined,
                    text: _durationLabel(snapshot.durationSeconds),
                  ),
                  _WorkoutFact(
                    icon: Icons.speed_rounded,
                    text: isEs
                        ? 'Nivel ${snapshot.difficulty}'
                        : 'Level ${snapshot.difficulty}',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                workoutMovementSummary(snapshot),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (share.senderMessage?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '“${share.senderMessage!.trim()}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutDetailsSheet extends ConsumerWidget {
  const _WorkoutDetailsSheet({
    required this.share,
    required this.isEs,
    required this.onStartNow,
    required this.onSchedule,
    required this.onRemoveSchedule,
    required this.onSaveForLater,
    required this.onDecline,
    required this.onFistBump,
  });

  final WorkoutShare share;
  final bool isEs;
  final VoidCallback onStartNow;
  final VoidCallback onSchedule;
  final VoidCallback onRemoveSchedule;
  final VoidCallback onSaveForLater;
  final VoidCallback onDecline;
  final VoidCallback onFistBump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(sharedWorkoutInboxControllerProvider);
    final currentUid = ref.watch(accountIdentityProvider).asData?.value?.uid;
    final isRecipient = currentUid == share.recipientUid;
    final friendUid = isRecipient ? share.senderUid : share.recipientUid;
    final friend = inbox.senderProfiles[friendUid];
    final busy = inbox.busyShareIds.contains(share.id);
    final snapshot = share.workoutSnapshot;
    final completed = share.status == WorkoutShareStatus.completed;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEs ? snapshot.titleEs : snapshot.titleEn,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              isRecipient
                  ? (isEs
                      ? 'De ${friend?.displayName ?? 'un integrante'}'
                      : 'From ${friend?.displayName ?? 'a teammate'}')
                  : (isEs
                      ? 'Enviado a ${friend?.displayName ?? 'un integrante'}'
                      : 'Sent to ${friend?.displayName ?? 'a teammate'}'),
            ),
            if (share.senderMessage?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Text('“${share.senderMessage!.trim()}”'),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WorkoutFact(
                  icon: Icons.timer_outlined,
                  text: _durationLabel(snapshot.durationSeconds),
                ),
                _WorkoutFact(
                  icon: Icons.speed_rounded,
                  text: isEs
                      ? 'Nivel ${snapshot.difficulty}'
                      : 'Level ${snapshot.difficulty}',
                ),
                _WorkoutStatusChip(status: share.status, isEs: isEs),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              isEs ? 'Movimientos' : 'Movements',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(workoutMovementSummary(snapshot, maxMovements: 8)),
            if (share.scheduledFor != null) ...[
              const SizedBox(height: 12),
              Text(
                '${isEs ? 'Programado' : 'Scheduled'}: '
                '${_dateTimeLabel(share.scheduledFor!)}',
              ),
            ],
            if (share.recipientResultSummary != null) ...[
              const SizedBox(height: 12),
              Text(
                isEs
                    ? '${share.recipientResultSummary!.calloutsCompleted} comandos completados'
                    : '${share.recipientResultSummary!.calloutsCompleted} callouts completed',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 22),
            if (busy)
              const Center(child: CircularProgressIndicator())
            else if (completed) ...[
              FilledButton.tonalIcon(
                onPressed: onFistBump,
                icon: const Icon(Icons.sports_mma_outlined),
                label: Text(isEs ? 'Enviar punito' : 'Send Fist Bump'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(isEs ? 'Listo' : 'Done'),
              ),
            ] else if (!isRecipient)
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(isEs ? 'Listo' : 'Done'),
              )
            else ...[
              FilledButton.icon(
                onPressed: onStartNow,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(isEs ? 'Empezar ahora' : 'Start Now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onSchedule,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  share.status == WorkoutShareStatus.scheduled
                      ? (isEs ? 'Cambiar horario' : 'Reschedule')
                      : (isEs ? 'Aceptar y programar' : 'Accept & Schedule'),
                ),
              ),
              if (share.status == WorkoutShareStatus.scheduled)
                TextButton.icon(
                  onPressed: onRemoveSchedule,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: Text(
                    isEs ? 'Eliminar horario' : 'Remove schedule',
                  ),
                )
              else
                TextButton.icon(
                  onPressed: onSaveForLater,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(isEs ? 'Guardar para despues' : 'Save for Later'),
                ),
              TextButton.icon(
                onPressed: onDecline,
                icon: const Icon(Icons.close_rounded),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                label: Text(isEs ? 'Rechazar' : 'Decline'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InboxTab extends StatelessWidget {
  const _InboxTab({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Text('$count', style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _InboxBanner extends StatelessWidget {
  const _InboxBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _WorkoutFact extends StatelessWidget {
  const _WorkoutFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _WorkoutStatusChip extends StatelessWidget {
  const _WorkoutStatusChip({required this.status, required this.isEs});

  final WorkoutShareStatus status;
  final bool isEs;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_statusLabel(status, isEs)),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.state,
    required this.isEs,
    required this.onRetry,
  });

  final SharedWorkoutSectionState state;
  final bool isEs;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(isEs ? 'Reintentar' : 'Retry loading more'),
          ),
        ),
      );
    }
    if (!state.hasMore) {
      return const SizedBox(height: 12);
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.expand_more),
          label: Text(isEs ? 'Cargar mas' : 'Load more'),
        ),
      ),
    );
  }
}

class _InboxStateMessage extends StatelessWidget {
  const _InboxStateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(subtitle, textAlign: TextAlign.center),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onPressed,
                child: Text(buttonLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _emptyIcon(SharedWorkoutInboxSection section) => switch (section) {
      SharedWorkoutInboxSection.newWorkouts => Icons.move_to_inbox_outlined,
      SharedWorkoutInboxSection.scheduled => Icons.event_outlined,
      SharedWorkoutInboxSection.completed => Icons.emoji_events_outlined,
    };

String _emptyTitle(SharedWorkoutInboxSection section, bool isEs) =>
    switch (section) {
      SharedWorkoutInboxSection.newWorkouts =>
        isEs ? 'No hay workouts nuevos' : 'No new workouts',
      SharedWorkoutInboxSection.scheduled =>
        isEs ? 'Nada programado' : 'Nothing scheduled',
      SharedWorkoutInboxSection.completed =>
        isEs ? 'Ninguno completado aun' : 'Nothing completed yet',
    };

String _emptySubtitle(SharedWorkoutInboxSection section, bool isEs) =>
    switch (section) {
      SharedWorkoutInboxSection.newWorkouts => isEs
          ? 'Los workouts que te envíen tus integrantes aparecerán aquí.'
          : 'Workouts teammates send you will appear here.',
      SharedWorkoutInboxSection.scheduled => isEs
          ? 'Acepta un workout y elige cuando hacerlo.'
          : 'Accept a workout and choose when to do it.',
      SharedWorkoutInboxSection.completed => isEs
          ? 'Los workouts del equipo terminados aparecerán aquí.'
          : 'Finished team workouts will appear here.',
    };

String _statusLabel(WorkoutShareStatus status, bool isEs) => switch (status) {
      WorkoutShareStatus.sent => isEs ? 'Nuevo' : 'New',
      WorkoutShareStatus.accepted => isEs ? 'Guardado' : 'Saved',
      WorkoutShareStatus.scheduled => isEs ? 'Programado' : 'Scheduled',
      WorkoutShareStatus.started => isEs ? 'Iniciado' : 'Started',
      WorkoutShareStatus.completed => isEs ? 'Completado' : 'Completed',
      WorkoutShareStatus.declined => isEs ? 'Rechazado' : 'Declined',
    };

String _durationLabel(int seconds) {
  final minutes = (seconds / 60).ceil();
  return '$minutes min';
}

String _receivedLabel(DateTime? sentAt, bool isEs) {
  if (sentAt == null) return isEs ? 'Recibido ahora' : 'Received now';
  final difference = DateTime.now().difference(sentAt.toLocal());
  if (difference.inMinutes < 1) return isEs ? 'Ahora' : 'Just now';
  if (difference.inHours < 1) {
    return isEs
        ? 'Hace ${difference.inMinutes} min'
        : '${difference.inMinutes} min ago';
  }
  if (difference.inDays < 1) {
    return isEs
        ? 'Hace ${difference.inHours} h'
        : '${difference.inHours} hr ago';
  }
  if (difference.inDays < 7) {
    return isEs
        ? 'Hace ${difference.inDays} dias'
        : '${difference.inDays} days ago';
  }
  return _dateTimeLabel(sentAt);
}

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
          ? local.hour - 12
          : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.month}/${local.day}/${local.year} $hour:$minute $period';
}
