import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../drill/providers.dart';
import 'onboarding.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({
    super.key,
    required this.onFinished,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _questions = [
    'What best describes you?',
    'What are you training for?',
    'What do you want to improve most?',
    'How hard do you want Snap & Go to push you?',
    'Do you want workout reminders?',
  ];

  int _step = 0;
  OnboardingRole? _role;
  OnboardingGoal? _goal;
  OnboardingFocus? _focus;
  OnboardingPushLevel? _pushLevel;
  bool? _workoutReminders;
  var _saving = false;

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _role != null;
      case 1:
        return _goal != null;
      case 2:
        return _focus != null;
      case 3:
        return _pushLevel != null;
      case 4:
        return _workoutReminders != null;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _questions.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_step + 1}/${_questions.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Build your first drill',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppBrandColors.red,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  _questions[_step],
                  key: ValueKey(_step),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: ListView(
                    key: ValueKey('choices-$_step'),
                    children: _choiceTiles(context),
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Back',
                    onPressed:
                        _saving || _step == 0 ? null : () => setState(_back),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _canContinue && !_saving ? _continueOrFinish : null,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(_step == _questions.length - 1
                              ? Icons.check
                              : Icons.arrow_forward),
                      label: Text(
                        _step == _questions.length - 1 ? 'Finish' : 'Continue',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _choiceTiles(BuildContext context) {
    switch (_step) {
      case 0:
        return [
          for (final value in OnboardingRole.values)
            _ChoiceTile(
              icon: _roleIcon(value),
              title: value.label,
              selected: _role == value,
              onTap: () => setState(() => _role = value),
            ),
        ];
      case 1:
        return [
          for (final value in OnboardingGoal.values)
            _ChoiceTile(
              icon: _goalIcon(value),
              title: value.label,
              selected: _goal == value,
              onTap: () => setState(() => _goal = value),
            ),
        ];
      case 2:
        return [
          for (final value in OnboardingFocus.values)
            _ChoiceTile(
              icon: _focusIcon(value),
              title: value.label,
              selected: _focus == value,
              onTap: () => setState(() => _focus = value),
            ),
        ];
      case 3:
        return [
          for (final value in OnboardingPushLevel.values)
            _ChoiceTile(
              icon: _pushIcon(value),
              title: value.label,
              selected: _pushLevel == value,
              onTap: () => setState(() => _pushLevel = value),
            ),
        ];
      case 4:
        return [
          _ChoiceTile(
            icon: Icons.notifications_active_outlined,
            title: 'Yes, remind me',
            subtitle: 'Snap & Go will ask permission for workout reminders.',
            selected: _workoutReminders == true,
            onTap: () => setState(() => _workoutReminders = true),
          ),
          _ChoiceTile(
            icon: Icons.notifications_off_outlined,
            title: 'Not now',
            subtitle: 'You can turn reminders on later in Setup.',
            selected: _workoutReminders == false,
            onTap: () => setState(() => _workoutReminders = false),
          ),
        ];
      default:
        return const [];
    }
  }

  void _back() {
    _step = (_step - 1).clamp(0, _questions.length - 1);
  }

  Future<void> _continueOrFinish() async {
    if (_step < _questions.length - 1) {
      setState(() => _step++);
      return;
    }

    setState(() => _saving = true);

    final profile = OnboardingProfile(
      role: _role!,
      goal: _goal!,
      focus: _focus!,
      pushLevel: _pushLevel!,
      workoutRemindersEnabled: _workoutReminders == true,
      completedAt: DateTime.now(),
    );

    _applyStarterSetup(profile);
    await ref.read(onboardingProvider.notifier).complete(profile);

    if (!mounted) return;
    if (profile.workoutRemindersEnabled) {
      final granted = await const NotificationPermissionPrompter()
          .requestWorkoutReminderPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Workout reminders are turned on.'
                : 'Reminders saved, but notification permission is off.',
          ),
        ),
      );
      if (!granted) {
        await ref
            .read(onboardingProvider.notifier)
            .setWorkoutRemindersEnabled(false);
      }
    }

    if (!mounted) return;
    widget.onFinished();
  }

  void _applyStarterSetup(OnboardingProfile profile) {
    final config = _starterConfigFor(profile);
    ref.read(drillConfigProvider.notifier)
      ..setEnabledCalloutIds(config.calloutIds)
      ..setIntervalRange(
        minSeconds: config.minIntervalSeconds,
        maxSeconds: config.maxIntervalSeconds,
      )
      ..setTotalDurationSeconds(config.totalDurationSeconds);
  }

  _StarterDrillConfig _starterConfigFor(OnboardingProfile profile) {
    final calloutIds = switch (profile.focus) {
      OnboardingFocus.offense => {'stance', 'fake', 'level_change', 'shot'},
      OnboardingFocus.defense => {'stance', 'sprawl', 'down_block', 'circle'},
      OnboardingFocus.conditioning => {
          'stance',
          'high_knees',
          'foot_fire',
          'sprawl',
        },
      OnboardingFocus.handfight => {
          'hand_fight',
          'snap_down',
          'circle',
          'level_change',
        },
    };

    final intervals = switch (profile.pushLevel) {
      OnboardingPushLevel.build => (3.0, 5.0),
      OnboardingPushLevel.hard => (1.0, 2.0),
      OnboardingPushLevel.max => (0.5, 1.5),
    };

    final duration = switch (profile.goal) {
      OnboardingGoal.dailyPractice => 180,
      OnboardingGoal.tournament => 300,
      OnboardingGoal.season => 300,
    };

    return _StarterDrillConfig(
      calloutIds: calloutIds,
      minIntervalSeconds: intervals.$1,
      maxIntervalSeconds: intervals.$2,
      totalDurationSeconds: duration,
    );
  }

  IconData _roleIcon(OnboardingRole value) {
    return switch (value) {
      OnboardingRole.wrestler => Icons.sports_mma,
      OnboardingRole.coach => Icons.record_voice_over,
      OnboardingRole.parent => Icons.family_restroom,
    };
  }

  IconData _goalIcon(OnboardingGoal value) {
    return switch (value) {
      OnboardingGoal.dailyPractice => Icons.calendar_today,
      OnboardingGoal.tournament => Icons.emoji_events,
      OnboardingGoal.season => Icons.flag,
    };
  }

  IconData _focusIcon(OnboardingFocus value) {
    return switch (value) {
      OnboardingFocus.offense => Icons.sports_mma,
      OnboardingFocus.defense => Icons.shield,
      OnboardingFocus.conditioning => Icons.local_fire_department,
      OnboardingFocus.handfight => Icons.back_hand,
    };
  }

  IconData _pushIcon(OnboardingPushLevel value) {
    return switch (value) {
      OnboardingPushLevel.build => Icons.trending_up,
      OnboardingPushLevel.hard => Icons.speed,
      OnboardingPushLevel.max => Icons.bolt,
    };
  }
}

class _StarterDrillConfig {
  final Set<String> calloutIds;
  final double minIntervalSeconds;
  final double maxIntervalSeconds;
  final int totalDurationSeconds;

  const _StarterDrillConfig({
    required this.calloutIds,
    required this.minIntervalSeconds,
    required this.maxIntervalSeconds,
    required this.totalDurationSeconds,
  });
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected
            ? AppBrandColors.red.withValues(alpha: 0.08)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppBrandColors.red : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppBrandColors.red
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: selected ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppBrandColors.red),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
