import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AgeEligibility {
  under13,
  thirteenOrOlder,
}

extension AgeEligibilityAccess on AgeEligibility {
  bool get allowsConnectedFeatures => this == AgeEligibility.thirteenOrOlder;

  String get label => switch (this) {
        AgeEligibility.under13 => 'Under 13',
        AgeEligibility.thirteenOrOlder => '13 or older',
      };
}

@immutable
class AgeEligibilityState {
  final bool loaded;
  final AgeEligibility? selection;

  const AgeEligibilityState({
    this.loaded = false,
    this.selection,
  });

  bool get allowsConnectedFeatures =>
      selection?.allowsConnectedFeatures ?? false;
}

abstract final class AgeEligibilityStorage {
  static const preferenceKey = 'age_eligibility_v1';

  static Future<AgeEligibility?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(preferenceKey);
    for (final value in AgeEligibility.values) {
      if (value.name == stored) return value;
    }
    return null;
  }

  static Future<void> save(AgeEligibility value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, value.name);
  }
}

final ageEligibilityProvider =
    NotifierProvider<AgeEligibilityNotifier, AgeEligibilityState>(
  AgeEligibilityNotifier.new,
);

class AgeEligibilityNotifier extends Notifier<AgeEligibilityState> {
  @override
  AgeEligibilityState build() {
    unawaited(load());
    return const AgeEligibilityState();
  }

  Future<AgeEligibilityState> load() async {
    final selection = await AgeEligibilityStorage.load();
    state = AgeEligibilityState(loaded: true, selection: selection);
    return state;
  }

  Future<AgeEligibilityState> ensureLoaded() async {
    if (state.loaded) return state;
    return load();
  }

  Future<void> select(AgeEligibility selection) async {
    await AgeEligibilityStorage.save(selection);
    state = AgeEligibilityState(loaded: true, selection: selection);
  }
}

class AgeEligibilityScreen extends ConsumerStatefulWidget {
  final FutureOr<void> Function(AgeEligibility selection) onFinished;

  const AgeEligibilityScreen({
    super.key,
    required this.onFinished,
  });

  @override
  ConsumerState<AgeEligibilityScreen> createState() =>
      _AgeEligibilityScreenState();
}

class _AgeEligibilityScreenState extends ConsumerState<AgeEligibilityScreen> {
  bool _saving = false;

  Future<void> _select(AgeEligibility selection) async {
    if (_saving) return;
    setState(() => _saving = true);
    await ref.read(ageEligibilityProvider.notifier).select(selection);
    await widget.onFinished(selection);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Age range')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.person_outline, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'Select your age range',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose the range that applies to the person using this '
                    'app. Snap & Go uses the answer to provide an '
                    'age-appropriate experience.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  for (final option in AgeEligibility.values) ...[
                    OutlinedButton(
                      key: ValueKey('age-${option.name}'),
                      onPressed: _saving ? null : () => _select(option),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: Text(option.label),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_saving) const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConnectedFeaturesRestrictedView extends StatelessWidget {
  final bool compact;

  const ConnectedFeaturesRestrictedView({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, size: 48),
        const SizedBox(height: 12),
        Text(
          'Local training mode',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Accounts, teams, social sharing, cloud features, '
          'and purchases are available only to users age 13 or older. Local '
          'workouts, on-device progress, and local recordings remain available.',
          textAlign: TextAlign.center,
        ),
      ],
    );
    if (compact) {
      return Padding(padding: const EdgeInsets.all(20), child: content);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: content,
        ),
      ),
    );
  }
}

Future<bool> requireConnectedFeatureEligibility(
  BuildContext context,
  WidgetRef ref,
) async {
  final eligibility =
      await ref.read(ageEligibilityProvider.notifier).ensureLoaded();
  if (eligibility.allowsConnectedFeatures) return true;
  if (!context.mounted) return false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Local training mode'),
      content: const Text(
        'This connected feature is available only to users age 13 or older. '
        'You can keep using workouts and on-device progress.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return false;
}
