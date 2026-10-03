import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_controller.dart';
import 'account_screen.dart';
import '../compliance/compliance.dart';

/// Call this before opening any team/shared-workout feature.
///
/// Local workout routes intentionally never use this gate.
Future<bool> requireSocialAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await requireConnectedFeatureEligibility(context, ref)) return false;
  if (!context.mounted) return false;
  final identity = ref.read(accountIdentityProvider).asData?.value;
  if (identity != null) return true;

  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const AccountScreen(closeAfterSignIn: true),
        ),
      ) ??
      false;
}

class SocialAccountGate extends ConsumerWidget {
  final Widget child;
  final Widget? signedOut;

  const SocialAccountGate({
    super.key,
    required this.child,
    this.signedOut,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ageEligibility = ref.watch(ageEligibilityProvider);
    if (ageEligibility.loaded && !ageEligibility.allowsConnectedFeatures) {
      return const ConnectedFeaturesRestrictedView(compact: true);
    }
    final identity = ref.watch(accountIdentityProvider);
    if (identity.asData?.value != null) return child;
    return signedOut ??
        Center(
          child: FilledButton.icon(
            onPressed: () => requireSocialAccount(context, ref),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Sign in for teams'),
          ),
        );
  }
}
