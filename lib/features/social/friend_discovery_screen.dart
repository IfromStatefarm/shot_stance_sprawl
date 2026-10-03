import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_controller.dart';
import '../account/account_models.dart';
import 'social_models.dart';
import 'social_providers.dart';
import 'team_sheet.dart';

final _discoveryProfileProvider = FutureProvider.autoDispose
    .family<SocialUserProfile?, String>((ref, uid) async {
  final profiles =
      await ref.watch(socialRepositoryProvider).loadProfiles([uid]);
  for (final profile in profiles) {
    if (profile.uid == uid) return profile;
  }
  return null;
});

class FriendDiscoveryScreen extends ConsumerStatefulWidget {
  const FriendDiscoveryScreen({super.key});

  @override
  ConsumerState<FriendDiscoveryScreen> createState() =>
      _FriendDiscoveryScreenState();
}

class _FriendDiscoveryScreenState extends ConsumerState<FriendDiscoveryScreen> {
  final Set<String> _acceptingRequests = {};
  final Set<String> _safetyActions = {};

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(accountIdentityProvider).asData?.value;
    final friendships = ref.watch(friendshipsProvider);
    final team = ref.watch(currentTeamProvider);
    final activeFriendships = (friendships.asData?.value ??
            const <Friendship>[])
        .where((friendship) => friendship.status != FriendshipStatus.blocked)
        .toList(growable: false);
    final connected = activeFriendships
        .where((friendship) => friendship.status == FriendshipStatus.accepted)
        .toList(growable: false);
    final pending = activeFriendships
        .where((friendship) => friendship.status == FriendshipStatus.pending)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: identity == null
          ? const _CenteredMessage(
              icon: Icons.login,
              title: 'Sign in to manage connections',
              subtitle:
                  'Your local workouts remain available without an account.',
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(friendshipsProvider);
                ref.invalidate(teamMembershipProvider);
                ref.invalidate(currentTeamProvider);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _TeamConnectionCard(
                    teamName: team.asData?.value?.name,
                    loading: team.isLoading,
                    onManageTeam: () => showTeamSheet(context, ref),
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle('Connected friends', connected.length),
                  if (friendships.isLoading)
                    const LinearProgressIndicator()
                  else if (friendships.hasError)
                    _InlineError(
                      message: 'Could not load friendships.',
                      onRetry: () => ref.invalidate(friendshipsProvider),
                    )
                  else if (connected.isEmpty)
                    const _EmptySection('Accepted friends will appear here.')
                  else
                    ...connected.map(
                      (friendship) => _friendshipTile(
                        friendship,
                        identity.uid,
                        connected: true,
                      ),
                    ),
                  const SizedBox(height: 22),
                  _sectionTitle('Pending requests', pending.length),
                  if (pending.isEmpty)
                    const _EmptySection('No incoming or outgoing requests.')
                  else
                    ...pending.map(
                      (friendship) => _friendshipTile(
                        friendship,
                        identity.uid,
                        connected: false,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('$count'),
          ),
        ],
      ),
    );
  }

  Widget _friendshipTile(
    Friendship friendship,
    String myUid, {
    required bool connected,
  }) {
    final otherUid = friendship.otherUserId(myUid);
    if (otherUid == null) return const SizedBox.shrink();
    final profile = ref.watch(_discoveryProfileProvider(otherUid));
    final incoming = friendship.requestedBy != myUid;
    return profile.when(
      loading: () => const ListTile(
        leading: CircleAvatar(child: Icon(Icons.person)),
        title: LinearProgressIndicator(),
      ),
      error: (_, __) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
        title: const Text('Friend profile unavailable'),
        trailing: _SafetyMenu(
          busy: _safetyActions.contains(otherUid),
          onBlock: () => _blockUser(otherUid, 'this user'),
          onReport: () => _reportUser(otherUid, 'this user'),
        ),
      ),
      data: (friend) {
        final displayName = friend?.displayName ?? 'Snap & Go athlete';
        final subtitle =
            friend?.username == null ? null : Text('@${friend!.username}');
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _profileAvatar(friend),
            title: Text(displayName),
            subtitle: subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (connected)
                  const Chip(
                    avatar: Icon(Icons.check_circle, size: 17),
                    label: Text('Connected'),
                  )
                else if (incoming)
                  FilledButton(
                    onPressed: _acceptingRequests.contains(friendship.id)
                        ? null
                        : () => unawaited(_acceptRequest(friendship)),
                    child: _acceptingRequests.contains(friendship.id)
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  )
                else
                  const Chip(label: Text('Requested')),
                _SafetyMenu(
                  busy: _safetyActions.contains(otherUid),
                  onBlock: () => _blockUser(otherUid, displayName),
                  onReport: () => _reportUser(otherUid, displayName),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _acceptRequest(Friendship friendship) async {
    setState(() => _acceptingRequests.add(friendship.id));
    try {
      await ref
          .read(socialRepositoryProvider)
          .acceptFriendRequest(friendship.id);
      if (mounted) _showMessage('Friend request accepted.');
    } catch (error) {
      if (mounted) _showMessage(accountErrorMessage(error));
    } finally {
      if (mounted) setState(() => _acceptingRequests.remove(friendship.id));
    }
  }

  Future<void> _blockUser(String uid, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block $displayName?'),
        content: const Text(
          'They will no longer appear as a friend and cannot send you workouts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _safetyActions.add(uid));
    try {
      await ref.read(socialRepositoryProvider).blockUser(uid);
      if (mounted) _showMessage('$displayName was blocked.');
    } catch (error) {
      if (mounted) _showMessage(accountErrorMessage(error));
    } finally {
      if (mounted) setState(() => _safetyActions.remove(uid));
    }
  }

  Future<void> _reportUser(String uid, String displayName) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Report $displayName'),
        children: [
          _ReportReason(
            label: 'Spam or unwanted requests',
            value: 'spam',
            dialogContext: dialogContext,
          ),
          _ReportReason(
            label: 'Harassment or bullying',
            value: 'harassment',
            dialogContext: dialogContext,
          ),
          _ReportReason(
            label: 'Unsafe or inappropriate content',
            value: 'unsafe_content',
            dialogContext: dialogContext,
          ),
          _ReportReason(
            label: 'Impersonation',
            value: 'impersonation',
            dialogContext: dialogContext,
          ),
          _ReportReason(
            label: 'Something else',
            value: 'other',
            dialogContext: dialogContext,
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _safetyActions.add(uid));
    try {
      await ref.read(socialRepositoryProvider).reportUser(
            otherUid: uid,
            reason: reason,
          );
      if (mounted) _showMessage('Report submitted. Thank you.');
    } catch (error) {
      if (mounted) _showMessage(accountErrorMessage(error));
    } finally {
      if (mounted) setState(() => _safetyActions.remove(uid));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TeamConnectionCard extends StatelessWidget {
  const _TeamConnectionCard({
    required this.teamName,
    required this.loading,
    required this.onManageTeam,
  });

  final String? teamName;
  final bool loading;
  final VoidCallback onManageTeam;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_outlined, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    teamName ?? 'Connect with your team',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(teamName == null
                ? 'Join with a team code or create a team. Snap & Go never needs access to your phone contacts.'
                : 'You are connected through your team. Manage its roster, code, and shared workouts here.'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: loading ? null : onManageTeam,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_outlined),
                label: Text(
                    teamName == null ? 'Join or create team' : 'Manage team'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyMenu extends StatelessWidget {
  const _SafetyMenu({
    required this.busy,
    required this.onBlock,
    required this.onReport,
  });

  final bool busy;
  final VoidCallback onBlock;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Safety actions',
      onSelected: (value) => value == 'block' ? onBlock() : onReport(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'block', child: Text('Block')),
        PopupMenuItem(value: 'report', child: Text('Report')),
      ],
    );
  }
}

class _ReportReason extends StatelessWidget {
  const _ReportReason({
    required this.label,
    required this.value,
    required this.dialogContext,
  });

  final String label;
  final String value;
  final BuildContext dialogContext;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(dialogContext, value),
      child: Text(label),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.error_outline),
      title: Text(message),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Widget _profileAvatar(SocialUserProfile? profile) {
  return CircleAvatar(
    foregroundImage: profile?.photoUrl?.isNotEmpty == true
        ? NetworkImage(profile!.photoUrl!)
        : null,
    child:
        profile?.photoUrl?.isNotEmpty == true ? null : const Icon(Icons.person),
  );
}
