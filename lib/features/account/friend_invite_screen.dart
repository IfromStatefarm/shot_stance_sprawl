import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_controller.dart';
import 'account_models.dart';
import 'social_account_gate.dart';

class FriendInviteScreen extends ConsumerWidget {
  final String username;

  const FriendInviteScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(accountIdentityProvider).asData?.value;
    final action = ref.watch(accountControllerProvider);

    ref.listen<AccountActionState>(accountControllerProvider, (previous, next) {
      if (next.message == null || next.message == previous?.message) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next.message!)));
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Friend invite')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 38,
                child: Icon(Icons.sports_mma, size: 38),
              ),
              const SizedBox(height: 18),
              Text(
                '@$username invited you to connect',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Friends can send each other workouts and build shared streaks.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: action.busy
                    ? null
                    : () => unawaited(_connect(context, ref, identity != null)),
                icon: Icon(
                  identity == null ? Icons.login : Icons.person_add_alt_1,
                ),
                label: Text(
                  identity == null
                      ? 'Sign in to add friend'
                      : 'Send friend request',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Maybe later'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    bool signedIn,
  ) async {
    if (!signedIn && !await requireSocialAccount(context, ref)) return;
    try {
      await ref
          .read(accountControllerProvider.notifier)
          .sendFriendRequest(username);
    } catch (_) {
      // The controller's state listener presents the user-facing error.
    }
  }
}
