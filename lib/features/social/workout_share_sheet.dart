import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account.dart';
import 'team_sheet.dart';
import 'social_models.dart';
import 'social_providers.dart';
import 'workout_snapshot.dart';

enum WorkoutRecipientState {
  notSent,
  sending,
  sent,
  accepted,
  completed,
  declined,
  retry,
}

WorkoutRecipientState workoutRecipientStateForStatus(
  WorkoutShareStatus status,
) {
  return switch (status) {
    WorkoutShareStatus.sent => WorkoutRecipientState.sent,
    WorkoutShareStatus.accepted ||
    WorkoutShareStatus.scheduled ||
    WorkoutShareStatus.started =>
      WorkoutRecipientState.accepted,
    WorkoutShareStatus.completed => WorkoutRecipientState.completed,
    WorkoutShareStatus.declined => WorkoutRecipientState.declined,
  };
}

Future<void> showWorkoutShareSheet({
  required BuildContext context,
  required WidgetRef ref,
  required WorkoutSnapshot workoutSnapshot,
  required String workoutSourceKey,
  required bool isEs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WorkoutShareSheet(
      workoutSnapshot: workoutSnapshot,
      workoutSourceKey: workoutSourceKey,
      isEs: isEs,
    ),
  );
}

@Deprecated('Use showWorkoutShareSheet.')
Future<void> showSendWorkoutToFriendsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required WorkoutSnapshot workoutSnapshot,
  required String workoutSourceKey,
  required bool isEs,
}) {
  return showWorkoutShareSheet(
    context: context,
    ref: ref,
    workoutSnapshot: workoutSnapshot,
    workoutSourceKey: workoutSourceKey,
    isEs: isEs,
  );
}

class WorkoutShareSheet extends ConsumerStatefulWidget {
  const WorkoutShareSheet({
    super.key,
    required this.workoutSnapshot,
    required this.workoutSourceKey,
    required this.isEs,
  });

  final WorkoutSnapshot workoutSnapshot;
  final String workoutSourceKey;
  final bool isEs;

  @override
  ConsumerState<WorkoutShareSheet> createState() => _WorkoutShareSheetState();
}

class _WorkoutShareSheetState extends ConsumerState<WorkoutShareSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecipientIds = {};
  final Map<String, WorkoutRecipientState> _localStates = {};
  Map<String, SocialUserProfile> _profiles = const {};
  String _profileLoadKey = '';
  Object? _profileError;
  bool _profilesLoading = false;
  bool _bulkSending = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(accountIdentityProvider).asData?.value;
    final teamMembership = ref.watch(teamMembershipProvider);
    final teamMembers = ref.watch(teamMemberIdsProvider);
    final team = ref.watch(currentTeamProvider);
    final sentShares = ref.watch(
      sentWorkoutSharesForSourceProvider(widget.workoutSourceKey),
    );
    final memberIds = identity == null || team.asData?.value?.status != 'active'
        ? const <String>[]
        : (teamMembers.asData?.value ?? const <String>[])
            .where((uid) => uid != identity.uid)
            .toList(growable: false);
    _ensureProfilesLoaded(memberIds);

    final sharesByRecipient = _sharesByRecipient(
      sentShares.asData?.value ?? const <WorkoutShare>[],
    );
    final visibleProfiles = memberIds
        .map((uid) => _profiles[uid])
        .whereType<SocialUserProfile>()
        .where(_matchesSearch)
        .toList(growable: false)
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    final historyReady = !sentShares.isLoading;
    final selectableVisibleIds = {
      for (final profile in visibleProfiles)
        if (_isSelectable(
          _recipientState(profile.uid, sharesByRecipient),
          historyReady: historyReady,
        ))
          profile.uid,
    };
    final selectedVisibleCount =
        selectableVisibleIds.where(_selectedRecipientIds.contains).length;
    final visibleCapacity = workoutShareRecipientLimit -
        (_selectedRecipientIds.length - selectedVisibleCount);
    final visibleSelectionTarget = selectableVisibleIds.length < visibleCapacity
        ? selectableVisibleIds.length
        : visibleCapacity;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkoutShareHeader(
              snapshot: widget.workoutSnapshot,
              isEs: widget.isEs,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                }),
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      widget.isEs ? 'Buscar integrantes' : 'Search teammates',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: widget.isEs ? 'Borrar' : 'Clear',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isEs ? 'DESTINATARIOS' : 'RECIPIENTS',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: selectableVisibleIds.isEmpty || _bulkSending
                        ? null
                        : () => _toggleSelectAll(selectableVisibleIds),
                    child: Text(
                      visibleSelectionTarget > 0 &&
                              selectedVisibleCount >= visibleSelectionTarget
                          ? (widget.isEs ? 'Quitar todos' : 'Clear all')
                          : (widget.isEs ? 'Elegir todos' : 'Select all'),
                    ),
                  ),
                ],
              ),
            ),
            if (sentShares.isLoading) const LinearProgressIndicator(),
            Expanded(
              child: _recipientList(
                members: teamMembers,
                teamLoading: teamMembership.isLoading || team.isLoading,
                teamError: teamMembership.hasError || team.hasError,
                memberIds: memberIds,
                visibleProfiles: visibleProfiles,
                sharesByRecipient: sharesByRecipient,
                historyReady: historyReady,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _bulkSending
                          ? null
                          : () => showTeamSheet(context, ref),
                      icon: const Icon(Icons.groups_outlined),
                      label: Text(
                        widget.isEs ? 'Mi equipo' : 'My Team',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selectedRecipientIds.isEmpty || _bulkSending
                          ? null
                          : () => unawaited(
                                _sendSelected(sharesByRecipient),
                              ),
                      icon: _bulkSending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        widget.isEs
                            ? 'Enviar (${_selectedRecipientIds.length})'
                            : 'Send (${_selectedRecipientIds.length})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextButton(
                onPressed:
                    _bulkSending ? null : () => Navigator.of(context).pop(),
                child: Text(widget.isEs ? 'Listo' : 'Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipientList({
    required AsyncValue<List<String>> members,
    required bool teamLoading,
    required bool teamError,
    required List<String> memberIds,
    required List<SocialUserProfile> visibleProfiles,
    required Map<String, WorkoutShare> sharesByRecipient,
    required bool historyReady,
  }) {
    if (teamLoading || members.isLoading || _profilesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (teamError || members.hasError) {
      return _SheetMessage(
        icon: Icons.cloud_off_outlined,
        message: widget.isEs
            ? 'No se pudieron cargar tus integrantes.'
            : 'Could not load your teammates.',
        buttonLabel: widget.isEs ? 'Reintentar' : 'Retry',
        onPressed: () {
          ref.invalidate(teamMembershipProvider);
          ref.invalidate(currentTeamProvider);
          ref.invalidate(teamMemberIdsProvider);
        },
      );
    }
    if (_profileError != null) {
      return _SheetMessage(
        icon: Icons.sync_problem_outlined,
        message: widget.isEs
            ? 'No se pudieron cargar los perfiles.'
            : 'Could not load teammate profiles.',
        buttonLabel: widget.isEs ? 'Reintentar' : 'Retry',
        onPressed: () => _reloadProfiles(memberIds),
      );
    }
    if (memberIds.isEmpty) {
      return _SheetMessage(
        icon: Icons.group_add_outlined,
        message: widget.isEs
            ? 'Crea un equipo o invita integrantes para enviar workouts.'
            : 'Create a team or invite teammates to send workouts.',
        buttonLabel: widget.isEs ? 'Mi equipo' : 'My Team',
        onPressed: () => showTeamSheet(context, ref),
      );
    }
    if (visibleProfiles.isEmpty) {
      return _SheetMessage(
        icon: Icons.search_off,
        message: widget.isEs
            ? 'Ningún integrante coincide con tu búsqueda.'
            : 'No teammates match your search.',
        buttonLabel: widget.isEs ? 'Borrar busqueda' : 'Clear search',
        onPressed: () {
          _searchController.clear();
          setState(() => _query = '');
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: visibleProfiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final profile = visibleProfiles[index];
        final state = _recipientState(profile.uid, sharesByRecipient);
        final selectable = _isSelectable(state, historyReady: historyReady);
        return _RecipientTile(
          profile: profile,
          state: state,
          isEs: widget.isEs,
          selected: _selectedRecipientIds.contains(profile.uid),
          selectable: selectable && !_bulkSending,
          onToggle: () => _toggleRecipient(profile.uid),
        );
      },
    );
  }

  Map<String, WorkoutShare> _sharesByRecipient(List<WorkoutShare> shares) {
    final result = <String, WorkoutShare>{};
    for (final share in shares) {
      if (share.workoutSourceKey != widget.workoutSourceKey) continue;
      final prior = result[share.recipientUid];
      if (prior == null ||
          _shareRank(share.status) > _shareRank(prior.status)) {
        result[share.recipientUid] = share;
      }
    }
    return result;
  }

  WorkoutRecipientState _recipientState(
    String recipientUid,
    Map<String, WorkoutShare> sharesByRecipient,
  ) {
    final local = _localStates[recipientUid];
    if (local == WorkoutRecipientState.sending) {
      return local!;
    }
    final share = sharesByRecipient[recipientUid];
    if (share != null) return workoutRecipientStateForStatus(share.status);
    return local ?? WorkoutRecipientState.notSent;
  }

  bool _matchesSearch(SocialUserProfile profile) {
    if (_query.isEmpty) return true;
    return profile.displayName.toLowerCase().contains(_query) ||
        (profile.username?.toLowerCase().contains(_query) ?? false);
  }

  bool _isSelectable(
    WorkoutRecipientState state, {
    required bool historyReady,
  }) {
    if (!historyReady) return false;
    return state == WorkoutRecipientState.notSent ||
        state == WorkoutRecipientState.retry;
  }

  void _toggleRecipient(String uid) {
    if (!_selectedRecipientIds.contains(uid) &&
        _selectedRecipientIds.length >= workoutShareRecipientLimit) {
      _showRecipientLimit();
      return;
    }
    setState(() {
      if (!_selectedRecipientIds.add(uid)) _selectedRecipientIds.remove(uid);
    });
  }

  void _toggleSelectAll(Set<String> visibleIds) {
    final selectedVisibleCount =
        visibleIds.where(_selectedRecipientIds.contains).length;
    final visibleCapacity = workoutShareRecipientLimit -
        (_selectedRecipientIds.length - selectedVisibleCount);
    final targetCount = visibleIds.length < visibleCapacity
        ? visibleIds.length
        : visibleCapacity;
    if (targetCount == 0) {
      _showRecipientLimit();
      return;
    }
    if (selectedVisibleCount >= targetCount) {
      setState(() => _selectedRecipientIds.removeAll(visibleIds));
      return;
    }
    final available = workoutShareRecipientLimit - _selectedRecipientIds.length;
    final unselectedRecipients = visibleIds
        .where((uid) => !_selectedRecipientIds.contains(uid))
        .toList(growable: false);
    final recipientsToAdd =
        unselectedRecipients.take(available).toList(growable: false);
    setState(() {
      _selectedRecipientIds.addAll(recipientsToAdd);
    });
    if (recipientsToAdd.length < unselectedRecipients.length) {
      _showRecipientLimit();
    }
  }

  void _showRecipientLimit() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            widget.isEs
                ? 'Puedes enviar a un maximo de '
                    '$workoutShareRecipientLimit integrantes a la vez.'
                : 'You can send to at most $workoutShareRecipientLimit '
                    'teammates at once.',
          ),
        ),
      );
  }

  void _ensureProfilesLoaded(List<String> friendIds) {
    final sortedIds = [...friendIds]..sort();
    final key = sortedIds.join('\u0000');
    if (key == _profileLoadKey) return;
    _profileLoadKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadProfiles(sortedIds, key));
    });
  }

  void _reloadProfiles(List<String> friendIds) {
    _profileLoadKey = '';
    _ensureProfilesLoaded(friendIds);
  }

  Future<void> _loadProfiles(List<String> friendIds, String key) async {
    if (friendIds.isEmpty) {
      setState(() {
        _profiles = const {};
        _profilesLoading = false;
        _profileError = null;
      });
      return;
    }
    setState(() {
      _profilesLoading = true;
      _profileError = null;
    });
    try {
      final profiles =
          await ref.read(socialRepositoryProvider).loadProfiles(friendIds);
      if (!mounted || key != _profileLoadKey) return;
      setState(() {
        _profiles = {for (final profile in profiles) profile.uid: profile};
      });
    } catch (error) {
      if (mounted && key == _profileLoadKey) {
        setState(() => _profileError = error);
      }
    } finally {
      if (mounted && key == _profileLoadKey) {
        setState(() => _profilesLoading = false);
      }
    }
  }

  Future<void> _sendSelected(
    Map<String, WorkoutShare> sharesByRecipient,
  ) async {
    if (_bulkSending) return;
    final recipientIds = _selectedRecipientIds.where((uid) {
      final state = _recipientState(uid, sharesByRecipient);
      return state == WorkoutRecipientState.notSent ||
          state == WorkoutRecipientState.retry;
    }).toList(growable: false);
    if (recipientIds.isEmpty) return;

    setState(() {
      _bulkSending = true;
      for (final uid in recipientIds) {
        _localStates[uid] = WorkoutRecipientState.sending;
      }
    });
    try {
      final batch =
          await ref.read(socialRepositoryProvider).shareWorkoutWithRecipients(
                recipientUids: recipientIds,
                workoutSourceKey: widget.workoutSourceKey,
                workoutSnapshot: widget.workoutSnapshot,
              );
      if (!mounted) return;
      setState(() {
        for (final uid in recipientIds) {
          final result = batch.byRecipient[uid];
          _localStates[uid] = result == null
              ? WorkoutRecipientState.retry
              : workoutRecipientStateForStatus(result.status);
          if (result != null) _selectedRecipientIds.remove(uid);
        }
        _bulkSending = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              widget.isEs
                  ? 'Workout enviado a ${recipientIds.length} destinatarios.'
                  : 'Workout sent to ${recipientIds.length} '
                      'recipient${recipientIds.length == 1 ? '' : 's'}.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        for (final uid in recipientIds) {
          _localStates[uid] = WorkoutRecipientState.retry;
        }
        _bulkSending = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(accountErrorMessage(error))),
        );
    }
  }
}

class _WorkoutShareHeader extends StatelessWidget {
  const _WorkoutShareHeader({
    required this.snapshot,
    required this.isEs,
    required this.onClose,
  });

  final WorkoutSnapshot snapshot;
  final bool isEs;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final minutes = (snapshot.durationSeconds / 60).ceil();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fitness_center),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEs ? snapshot.titleEs : snapshot.titleEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  isEs
                      ? '$minutes min · Nivel ${snapshot.difficulty} · ${snapshot.enabledCalloutIds.length} comandos'
                      : '$minutes min · Level ${snapshot.difficulty} · ${snapshot.enabledCalloutIds.length} callouts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isEs ? 'Cerrar' : 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.profile,
    required this.state,
    required this.isEs,
    required this.selected,
    required this.selectable,
    required this.onToggle,
  });

  final SocialUserProfile profile;
  final WorkoutRecipientState state;
  final bool isEs;
  final bool selected;
  final bool selectable;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: selectable || state != WorkoutRecipientState.notSent,
      onTap: selectable ? onToggle : null,
      leading: CircleAvatar(
        foregroundImage: profile.photoUrl?.isNotEmpty == true
            ? NetworkImage(profile.photoUrl!)
            : null,
        child: profile.photoUrl?.isNotEmpty == true
            ? null
            : const Icon(Icons.person),
      ),
      title: Text(profile.displayName),
      subtitle: Row(
        children: [
          _RecipientStateIcon(state: state),
          const SizedBox(width: 5),
          Text(_recipientStateLabel(state, isEs)),
          if (profile.username != null) ...[
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                '@${profile.username}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: selectable
          ? Checkbox(value: selected, onChanged: (_) => onToggle())
          : state == WorkoutRecipientState.sending
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const SizedBox(width: 20),
    );
  }
}

class _RecipientStateIcon extends StatelessWidget {
  const _RecipientStateIcon({required this.state});

  final WorkoutRecipientState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      WorkoutRecipientState.notSent => (
          Icons.radio_button_unchecked,
          Theme.of(context).colorScheme.outline
        ),
      WorkoutRecipientState.sending => (
          Icons.sync,
          Theme.of(context).colorScheme.primary
        ),
      WorkoutRecipientState.sent => (Icons.check, Colors.green),
      WorkoutRecipientState.accepted => (Icons.done_all, Colors.green),
      WorkoutRecipientState.completed => (Icons.emoji_events, Colors.amber),
      WorkoutRecipientState.declined => (
          Icons.block_outlined,
          Theme.of(context).colorScheme.outline
        ),
      WorkoutRecipientState.retry => (
          Icons.refresh,
          Theme.of(context).colorScheme.error
        ),
    };
    return Icon(icon, size: 16, color: color);
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({
    required this.icon,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

String _recipientStateLabel(WorkoutRecipientState state, bool isEs) {
  return switch (state) {
    WorkoutRecipientState.notSent => isEs ? 'No enviado' : 'Not sent',
    WorkoutRecipientState.sending => isEs ? 'Enviando' : 'Sending',
    WorkoutRecipientState.sent => isEs ? 'Enviado' : 'Sent',
    WorkoutRecipientState.accepted => isEs ? 'Aceptado' : 'Accepted',
    WorkoutRecipientState.completed => isEs ? 'Completado' : 'Completed',
    WorkoutRecipientState.declined => isEs ? 'Rechazado' : 'Declined',
    WorkoutRecipientState.retry => isEs ? 'Reintentar' : 'Retry',
  };
}

int _shareRank(WorkoutShareStatus status) {
  return switch (status) {
    WorkoutShareStatus.sent => 0,
    WorkoutShareStatus.accepted => 1,
    WorkoutShareStatus.scheduled => 2,
    WorkoutShareStatus.started => 3,
    WorkoutShareStatus.completed => 4,
    WorkoutShareStatus.declined => 5,
  };
}
