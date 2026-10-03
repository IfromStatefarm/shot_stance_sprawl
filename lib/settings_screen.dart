import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'core/local_file_storage.dart';
import 'features/account/account.dart';
import 'features/compliance/compliance.dart';
import 'features/drill/drill.dart';
import 'features/drill/presentation/settings_presentation.dart';
import 'features/onboarding/onboarding_feature.dart';
import 'features/onboarding/season_schedule.dart';
import 'features/recordings/recordings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _buyPro(WidgetRef ref) {
    unawaited(ref.read(proPurchaseProvider.notifier).buyPro());
  }

  Future<void> _launchURL(String urlString) async {
    final url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch $urlString: $e');
    }
  }

  Future<void> _confirmDeleteLocalData(
    BuildContext context,
    WidgetRef ref,
    bool isEs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEs ? 'Borrar datos locales' : 'Delete local data'),
        content: Text(
          isEs
              ? 'Esto borra perfil, progreso, grabaciones, comandos y ajustes guardados en este dispositivo. Se conserva el rango de edad requerido para seguridad.'
              : 'This removes the profile, progress, review videos, callouts, and saved settings on this device. The required age-range safety choice is retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppBrandColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEs ? 'Borrar' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _deleteLocalData(context, ref, isEs);
    }
  }

  Future<void> _deleteLocalData(
    BuildContext context,
    WidgetRef ref,
    bool isEs,
  ) async {
    final config = ref.read(drillConfigProvider);
    final recordings =
        await ref.read(savedRecordingsProvider.future).catchError(
              (_) => const <SavedWorkoutVideo>[],
            );
    final localPaths = <String>{
      ...config.customAudioPaths.values,
      ...config.customAdLibAudioPaths.values,
      ...recordings.map((video) => video.path),
    };

    for (final path in localPaths) {
      await LocalFileStorage.deleteLocalFileIfExists(
        path,
        debugLabel: 'Could not delete local file',
      );
    }

    await LocalFileStorage.deleteDirectoryIfExists(
      await LocalStoragePaths.recordingsDirectory(),
      recursive: true,
      debugLabel: 'Could not delete recordings directory',
    );

    final prefs = await ref.read(sharedPrefsProvider.future);
    final ageEligibility = ref.read(ageEligibilityProvider).selection;
    await ref
        .read(workoutReminderNotificationsProvider)
        .cancelWorkoutReminders();
    await prefs.clear();
    if (ageEligibility != null) {
      await prefs.setString(
        AgeEligibilityStorage.preferenceKey,
        ageEligibility.name,
      );
    }
    await ref.read(languageProvider.notifier).setLanguage('en');

    ref.invalidate(sharedPrefsProvider);
    ref.invalidate(calloutButtonStyleProvider);
    ref.invalidate(drillConfigProvider);
    ref.invalidate(userProfileProvider);
    ref.invalidate(calloutsProvider);
    ref.invalidate(trainingProgressProvider);
    ref.invalidate(badgeProgressProvider);
    ref.invalidate(savedRecordingsProvider);
    ref.invalidate(proPurchaseProvider);
    ref.invalidate(onboardingProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEs ? 'Datos locales borrados' : 'Local data deleted',
        ),
      ),
    );
  }

  Future<void> _setWorkoutReminders(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
    bool isEs,
  ) async {
    if (!enabled) {
      await ref
          .read(onboardingProvider.notifier)
          .setWorkoutRemindersEnabled(false);
      await ref
          .read(workoutReminderNotificationsProvider)
          .cancelWorkoutReminders();
      return;
    }

    final granted = await const NotificationPermissionPrompter()
        .requestWorkoutReminderPermission();
    final profile = await ref
        .read(onboardingProvider.notifier)
        .setWorkoutRemindersEnabled(granted);
    final lastWorkoutCompletedAt = profile.lastWorkoutCompletedAt;
    if (granted && lastWorkoutCompletedAt != null) {
      await ref
          .read(workoutReminderNotificationsProvider)
          .scheduleAfterWorkoutCompletion(
            profile: profile,
            completedAt: lastWorkoutCompletedAt,
          );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? (isEs
                  ? 'Recordatorios activados'
                  : 'Workout reminders turned on')
              : (isEs
                  ? 'Permiso de notificaciones desactivado'
                  : 'Notification permission is off'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(languageProvider);
    final isEs = currentLang == 'es';
    final isPro = ref.watch(isProProvider);
    final proState = ref.watch(proPurchaseProvider);
    final config = ref.watch(drillConfigProvider);
    final calloutButtonStyle = ref.watch(calloutButtonStyleProvider);
    final onboarding = ref.watch(onboardingProvider);
    final ageEligibility = ref.watch(ageEligibilityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? 'Configuracion' : 'Setup'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SettingsGroup(
            title: isEs ? 'Perfil personal' : 'Personal setup',
            child: const SettingsProfileHeader(),
          ),
          _SettingsGroup(
            title: isEs ? 'Temporada de lucha' : 'Wrestling season',
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                initialValue: seasonDatesByState
                        .containsKey(onboarding.profile?.stateName)
                    ? onboarding.profile!.stateName
                    : null,
                decoration: InputDecoration(
                  labelText: isEs ? 'Estado' : 'State',
                  helperText: isEs
                      ? 'Usado para la cuenta regresiva de temporada'
                      : 'Used for the season countdown',
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final stateName in seasonDatesByState.keys)
                    DropdownMenuItem(value: stateName, child: Text(stateName)),
                ],
                onChanged: onboarding.profile == null
                    ? null
                    : (stateName) {
                        if (stateName != null) {
                          unawaited(ref
                              .read(onboardingProvider.notifier)
                              .setStateName(stateName));
                        }
                      },
              ),
            ),
          ),
          _SettingsGroup(
            title: isEs ? 'Cuenta y equipo' : 'Account and team',
            child: AccountSettingsCard(isEs: isEs),
          ),
          _SettingsGroup(
            title: isEs ? 'Idioma' : 'Language',
            child: const SettingsLanguageSelector(),
          ),
          _SettingsGroup(
            title: isEs ? 'Apariencia' : 'Look',
            child: _LookSelector(
              isEs: isEs,
              style: calloutButtonStyle,
              onChanged: (style) => unawaited(
                ref.read(calloutButtonStyleProvider.notifier).setStyle(style),
              ),
            ),
          ),
          _SettingsGroup(
            title: isEs ? 'Recordatorios' : 'Reminders',
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(
                isEs ? 'Recordatorios de workout' : 'Workout reminders',
              ),
              subtitle: Text(
                isEs
                    ? 'Muestra el permiso de notificaciones para recordatorios'
                    : 'Shows the notification permission popup for reminders',
              ),
              value: onboarding.workoutRemindersEnabled,
              onChanged: onboarding.loaded
                  ? (enabled) => unawaited(
                        _setWorkoutReminders(context, ref, enabled, isEs),
                      )
                  : null,
            ),
          ),
          _SettingsGroup(
            title: isEs ? 'Audio' : 'Audio',
            child: Column(
              children: [
                const SettingsVoicePackSelector(),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: const Icon(Icons.record_voice_over),
                  title: Text(isEs ? 'Ad libs' : 'Ad libs'),
                  subtitle: Text(
                    isEs
                        ? 'Frases extra durante comandos largos'
                        : 'Extra cues during long callouts',
                  ),
                  value: config.adLibsEnabled,
                  onChanged: (enabled) {
                    ref
                        .read(drillConfigProvider.notifier)
                        .setAdLibsEnabled(enabled);
                  },
                ),
                if (config.adLibsEnabled)
                  SettingsAdLibSlotsManager(
                    isPro: isPro,
                    onUpgradeTap: () => _buyPro(ref),
                  ),
                const Divider(height: 1),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.mic_external_on_outlined),
                  title: Text(
                    isEs ? 'Comandos personalizados' : 'Custom callouts',
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (isPro)
                      const SettingsCustomCalloutsManager()
                    else
                      SettingsProCalloutGate(currentLang: currentLang),
                  ],
                ),
              ],
            ),
          ),
          _SettingsGroup(
            title: isEs ? 'Coach Mode' : 'Coach Mode',
            child: _SubscriptionStatus(
              currentLang: currentLang,
              purchaseState: proState,
              onBuyTap: () => _buyPro(ref),
              onRestoreTap: () => unawaited(
                ref.read(proPurchaseProvider.notifier).restorePurchases(),
              ),
              onDebugChanged: kDebugMode
                  ? (isProValue) => unawaited(
                        ref
                            .read(proPurchaseProvider.notifier)
                            .setDebugOverride(isProValue),
                      )
                  : null,
            ),
          ),
          _SettingsGroup(
            title: isEs ? 'Privacidad y datos' : 'Privacy and data',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(isEs ? 'Rango de edad' : 'Age range'),
                  subtitle: Text(
                    ageEligibility.selection == null
                        ? (isEs ? 'No seleccionado' : 'Not selected')
                        : ageEligibility.selection!.label,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: const Icon(Icons.videocam_outlined),
                  title: Text(
                    isEs ? 'Guardar videos de review' : 'Save review videos',
                  ),
                  subtitle: Text(
                    isEs
                        ? 'Controla si los drills pueden guardar grabaciones'
                        : 'Controls whether drills can save review videos',
                  ),
                  value: config.videoEnabled,
                  onChanged: (enabled) {
                    ref
                        .read(drillConfigProvider.notifier)
                        .setVideoEnabled(enabled);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title:
                      Text(isEs ? 'Politica de privacidad' : 'Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => unawaited(
                    _launchURL(
                      'https://keepkidswrestling.com/Snap-and-go/privacy',
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: AppBrandColors.red,
                  ),
                  title:
                      Text(isEs ? 'Borrar datos locales' : 'Delete local data'),
                  subtitle: Text(
                    isEs
                        ? 'Perfil, progreso, audios y grabaciones'
                        : 'Profile, progress, audio, and review videos',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(
                    _confirmDeleteLocalData(context, ref, isEs),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsGroup({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
            ),
          ),
          Material(
            color: scheme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _LookSelector extends StatelessWidget {
  final bool isEs;
  final CalloutButtonStyle style;
  final ValueChanged<CalloutButtonStyle> onChanged;

  const _LookSelector({
    required this.isEs,
    required this.style,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEs ? 'Estilo de botones' : 'Button style',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<CalloutButtonStyle>(
            segments: [
              ButtonSegment(
                value: CalloutButtonStyle.classic,
                icon: const Icon(Icons.toggle_on_outlined),
                label: Text(isEs ? 'Clasico' : 'Classic'),
              ),
              ButtonSegment(
                value: CalloutButtonStyle.modern,
                icon: const Icon(Icons.image_outlined),
                label: Text(isEs ? 'Moderno' : 'Modern'),
              ),
            ],
            selected: {style},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionStatus extends StatelessWidget {
  final String currentLang;
  final ProPurchaseState purchaseState;
  final VoidCallback onBuyTap;
  final VoidCallback onRestoreTap;
  final ValueChanged<bool>? onDebugChanged;

  const _SubscriptionStatus({
    required this.currentLang,
    required this.purchaseState,
    required this.onBuyTap,
    required this.onRestoreTap,
    required this.onDebugChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEs = currentLang == 'es';
    final product = purchaseState.primaryProduct;
    final isPro = purchaseState.isPro;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            isPro ? Icons.verified_outlined : Icons.workspace_premium_outlined,
            color: isPro ? AppBrandColors.gold : AppBrandColors.red,
          ),
          title: Text(
            isPro
                ? 'Snap & Go Coach Mode'
                : (isEs ? 'Plan gratis' : 'Free plan'),
          ),
          subtitle: Text(
            isPro
                ? (isEs ? 'Activo' : 'Active')
                : product == null
                    ? (isEs
                        ? 'Coach Mode no disponible'
                        : 'Coach Mode unavailable')
                    : (isEs
                        ? 'Videos largos, voz de coach y ad libs - ${product.price}'
                        : 'Long videos, coach voice, and ad libs - ${product.price}'),
          ),
          trailing: isPro
              ? const Icon(Icons.check_circle, color: AppBrandColors.gold)
              : FilledButton(
                  onPressed: purchaseState.canBuy ? onBuyTap : null,
                  child: Text(
                    purchaseState.purchasePending
                        ? '...'
                        : (isEs ? 'Coach Mode' : 'Coach Mode'),
                  ),
                ),
        ),
        if (purchaseState.loading)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LinearProgressIndicator(),
          ),
        if (purchaseState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              purchaseState.errorMessage!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: Text(isEs ? 'Restaurar compras' : 'Restore purchases'),
          trailing: purchaseState.restorePending
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: purchaseState.restorePending ? null : onRestoreTap,
        ),
        if (onDebugChanged != null) ...[
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('Simulate Coach Mode'),
            subtitle: const Text('Debug only'),
            value: isPro,
            onChanged: onDebugChanged,
          ),
        ],
      ],
    );
  }
}
