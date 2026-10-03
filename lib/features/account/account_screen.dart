import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../social/team_sheet.dart';
import '../compliance/compliance.dart';
import 'account_controller.dart';
import 'account_models.dart';

class AccountSettingsCard extends ConsumerWidget {
  final bool isEs;

  const AccountSettingsCard({super.key, required this.isEs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ageEligibility = ref.watch(ageEligibilityProvider);
    if (ageEligibility.loaded && !ageEligibility.allowsConnectedFeatures) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: const Icon(Icons.lock_outline),
        title: Text(isEs ? 'Modo de entrenamiento local' : 'Local training mode'),
        subtitle: Text(
          isEs
              ? 'Las cuentas, equipos y funciones conectadas requieren 13 anos o mas.'
              : 'Accounts, teams, and connected features require age 13 or older.',
        ),
      );
    }
    final available = ref.watch(firebaseAvailabilityProvider);
    final identity = ref.watch(accountIdentityProvider);
    final account = identity.asData?.value;

    if (!available) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(isEs ? 'Modo local' : 'Local mode'),
        subtitle: Text(
          isEs
              ? 'Los workouts funcionan; las funciones sociales necesitan Firebase.'
              : 'Workouts still work; team features need Firebase.',
        ),
        trailing: TextButton(
          onPressed: () => unawaited(_retryFirebase(context, ref)),
          child: Text(isEs ? 'Reintentar' : 'Retry'),
        ),
        onTap: () => _openAccount(context),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        foregroundImage: account?.photoUrl?.isNotEmpty == true
            ? NetworkImage(account!.photoUrl!)
            : null,
        child: Icon(account == null ? Icons.person_add_alt_1 : Icons.person),
      ),
      title: Text(
        account == null
            ? (isEs ? 'Conectar una cuenta' : 'Connect an account')
            : (account.displayName?.isNotEmpty == true
                ? account.displayName!
                : account.email ?? (isEs ? 'Tu cuenta' : 'Your account')),
      ),
      subtitle: Text(
        account == null
            ? (isEs
                ? 'Necesario solo para equipos y workouts compartidos'
                : 'Required only for teams and shared workouts')
            : (isEs
                ? 'Administra usuario, invitaciones y privacidad'
                : 'Manage your account and team'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openAccount(context),
    );
  }

  Future<void> _openAccount(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AccountScreen()),
    );
  }

  Future<void> _retryFirebase(BuildContext context, WidgetRef ref) async {
    final available =
        await ref.read(firebaseAvailabilityProvider.notifier).retry();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          available
              ? (isEs ? 'Firebase conectado' : 'Firebase connected')
              : (isEs
                  ? 'Firebase sigue sin conexión. Los workouts locales funcionan.'
                  : 'Firebase is still offline. Local workouts still work.'),
        ),
      ),
    );
  }
}

class AccountScreen extends ConsumerWidget {
  final bool closeAfterSignIn;

  const AccountScreen({super.key, this.closeAfterSignIn = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ageEligibility = ref.watch(ageEligibilityProvider);
    ref.listen<AccountActionState>(accountControllerProvider, (previous, next) {
      if (next.message == null || next.message == previous?.message) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next.message!)));
    });
    ref.listen<AsyncValue<AccountIdentity?>>(accountIdentityProvider,
        (previous, next) {
      if (!closeAfterSignIn || next.asData?.value == null) return;
      Navigator.of(context).pop(true);
    });

    final available = ref.watch(firebaseAvailabilityProvider);
    final identity = ref.watch(accountIdentityProvider);
    final action = ref.watch(accountControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Snap & Go account')),
      body: SafeArea(
        child: ageEligibility.loaded && !ageEligibility.allowsConnectedFeatures
            ? const ConnectedFeaturesRestrictedView()
            : !available
            ? _FirebaseUnavailableView(busy: action.busy)
            : identity.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _AccountErrorView(error: error),
                data: (account) => account == null
                    ? _SignedOutView(busy: action.busy)
                    : _SignedInView(account: account, action: action),
              ),
      ),
    );
  }
}

class _FirebaseUnavailableView extends ConsumerWidget {
  final bool busy;

  const _FirebaseUnavailableView({required this.busy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cloud_off_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          'You are in local mode',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your workouts and on-device progress remain available. Sign-in and '
          'social tools return when Firebase is configured or reconnects.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => unawaited(
                    ref.read(firebaseAvailabilityProvider.notifier).retry(),
                  ),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry Firebase'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => _ignore(
                    ref
                        .read(accountControllerProvider.notifier)
                        .shareDataExport(),
                  ),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export local data'),
        ),
      ],
    );
  }
}

class _AccountErrorView extends StatelessWidget {
  final Object error;

  const _AccountErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(accountErrorMessage(error), textAlign: TextAlign.center),
      ),
    );
  }
}

class _SignedOutView extends ConsumerStatefulWidget {
  final bool busy;

  const _SignedOutView({required this.busy});

  @override
  ConsumerState<_SignedOutView> createState() => _SignedOutViewState();
}

class _SignedOutViewState extends ConsumerState<_SignedOutView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _createAccount = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(accountControllerProvider.notifier);
    final showApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Connect your account',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'An account is only required for teams, shared workouts, and social '
          'streaks. You can always train and keep progress on this device.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed:
              widget.busy ? null : () => _ignore(controller.signInWithGoogle()),
          icon: const Icon(Icons.g_mobiledata, size: 30),
          label: const Text('Continue with Google'),
        ),
        if (showApple) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: widget.busy
                ? null
                : () => _ignore(controller.signInWithApple()),
            icon: const Icon(Icons.apple),
            label: const Text('Continue with Apple'),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('OR USE EMAIL'),
              ),
              Expanded(child: Divider()),
            ],
          ),
        ),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                enabled: !widget.busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) => value?.contains('@') == true
                    ? null
                    : 'Enter a valid email.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                enabled: !widget.busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) => (value?.length ?? 0) >= 6
                    ? null
                    : 'Use at least 6 characters.',
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.busy ? null : _submitEmail,
                  child: Text(_createAccount ? 'Create account' : 'Sign in'),
                ),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => setState(() => _createAccount = !_createAccount),
                child: Text(
                  _createAccount
                      ? 'I already have an account'
                      : 'Create an account with email',
                ),
              ),
              if (!_createAccount)
                TextButton(
                  onPressed: widget.busy
                      ? null
                      : () => _ignore(
                            controller.sendPasswordResetEmail(_email.text),
                          ),
                  child: const Text('Forgot password?'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed:
              widget.busy ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.fitness_center),
          label: const Text('Keep training without an account'),
        ),
      ],
    );
  }

  void _submitEmail() {
    if (_formKey.currentState?.validate() != true) return;
    final controller = ref.read(accountControllerProvider.notifier);
    _ignore(
      _createAccount
          ? controller.createEmailAccount(_email.text, _password.text)
          : controller.signInWithEmail(_email.text, _password.text),
    );
  }
}

class _SignedInView extends ConsumerStatefulWidget {
  final AccountIdentity account;
  final AccountActionState action;

  const _SignedInView({required this.account, required this.action});

  @override
  ConsumerState<_SignedInView> createState() => _SignedInViewState();
}

class _SignedInViewState extends ConsumerState<_SignedInView> {
  @override
  Widget build(BuildContext context) {
    final controller = ref.read(accountControllerProvider.notifier);
    final busy = widget.action.busy;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _AccountHeader(account: widget.account),
        if (widget.action.localProgressSyncPending) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.sync_problem_outlined),
              title: const Text('Progress sync pending'),
              subtitle: const Text('Your progress is safe on this device.'),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => _ignore(controller.retryLocalProgressSync()),
                child: const Text('Retry'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('TEAM', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: busy ? null : () => showTeamSheet(context, ref),
          icon: const Icon(Icons.groups_outlined),
          label: const Text('Create, join, or manage my team'),
        ),
        const SizedBox(height: 24),
        Text('YOUR DATA', style: Theme.of(context).textTheme.labelLarge),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_outlined),
          title: const Text('Export my data'),
          subtitle: const Text(
              'Creates a readable JSON copy of local and account data.'),
          trailing: const Icon(Icons.ios_share),
          onTap: busy
              ? null
              : () => _ignore(controller.shareDataExport(
                    sharePositionOrigin: _shareOrigin(context),
                  )),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          subtitle:
              const Text('Local workouts and progress stay on this device.'),
          onTap: busy ? null : () => _ignore(controller.signOut()),
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_forever, color: AppBrandColors.red),
          title: const Text(
            'Delete account',
            style: TextStyle(color: AppBrandColors.red),
          ),
          subtitle: const Text(
            'Deletes cloud account data. Local workouts remain unless you delete them separately.',
          ),
          onTap:
              busy ? null : () => _confirmAccountDeletion(context, controller),
        ),
      ],
    );
  }

  Future<void> _confirmAccountDeletion(
    BuildContext context,
    AccountController controller,
  ) async {
    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete cloud account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your account and team membership. '
              'If you created a team, it will be deleted. Type DELETE to confirm.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmation,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppBrandColors.red),
            onPressed: () => Navigator.pop(
              dialogContext,
              confirmation.text.trim() == 'DELETE',
            ),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    confirmation.dispose();
    if (confirmed == true) await _ignore(controller.deleteAccount());
  }
}

class _AccountHeader extends StatelessWidget {
  final AccountIdentity account;

  const _AccountHeader({required this.account});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          foregroundImage: account.photoUrl?.isNotEmpty == true
              ? NetworkImage(account.photoUrl!)
              : null,
          child: const Icon(Icons.person, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.displayName?.isNotEmpty == true
                    ? account.displayName!
                    : 'Connected account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (account.email != null) Text(account.email!),
              const Text('Local training remains available offline.'),
            ],
          ),
        ),
      ],
    );
  }
}

Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null;
}

Future<void> _ignore(Future<dynamic> future) async {
  try {
    await future;
  } catch (_) {
    // AccountController publishes a user-facing message through its state.
  }
}
