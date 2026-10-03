import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_theme.dart';
import '../../../core/local_file_storage.dart';
import '../../account/account.dart';
import '../../badges/badges.dart';
import '../../compliance/compliance.dart';
import '../../onboarding/onboarding.dart';
import '../../onboarding/season_schedule.dart';
import '../../recordings/recordings.dart';
import '../../social/social.dart';
import '../models.dart';
import '../workout_presets.dart';

part 'dashboard/training_dashboard_widgets.dart';

const int _dailyRepGoal = 50;

class TrainingDashboard extends ConsumerWidget {
  final TrainingProgress progress;
  final bool isEs;
  final bool missionLoading;
  final WorkoutPreset dailyMission;
  final VoidCallback? onStartMission;
  final VoidCallback onBrowseWorkouts;
  final VoidCallback onCustomizeDrill;

  const TrainingDashboard({
    super.key,
    required this.progress,
    required this.isEs,
    required this.missionLoading,
    required this.dailyMission,
    required this.onStartMission,
    required this.onBrowseWorkouts,
    required this.onCustomizeDrill,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadSharedWorkoutCount = ref
            .watch(socialProfileProvider)
            .asData
            ?.value
            ?.unreadSharedWorkoutCount ??
        0;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _DashboardHeader(progress: progress, isEs: isEs),
          const SizedBox(height: 16),
          _MissionCard(
            isEs: isEs,
            loading: missionLoading,
            preset: dailyMission,
            onStartMission: onStartMission,
            onBrowseWorkouts: onBrowseWorkouts,
            onSendWorkout: () => unawaited(
              _sendTodayMission(context, ref, dailyMission, isEs: isEs),
            ),
            onOpenSharedWorkouts: () => unawaited(
              _openSharedWorkouts(context, ref),
            ),
            unreadSharedWorkoutCount: unreadSharedWorkoutCount,
            onCustomizeDrill: onCustomizeDrill,
          ),
          const SizedBox(height: 20),
          HomeBadgeChases(isEs: isEs),
          const SizedBox(height: 20),
          _SectionTitle(
              text: isEs ? 'Lo que persigues' : 'What you are chasing'),
          const SizedBox(height: 10),
          _ProgressGrid(metrics: _coreProgressMetrics(progress)),
        ],
      ),
    );
  }
}

Future<void> _sendTodayMission(
  BuildContext context,
  WidgetRef ref,
  WorkoutPreset preset, {
  required bool isEs,
}) async {
  if (!await requireSocialAccount(context, ref) || !context.mounted) return;
  final snapshot = workoutSnapshotForDailyMission(preset);
  await showWorkoutShareSheet(
    context: context,
    ref: ref,
    workoutSnapshot: snapshot,
    workoutSourceKey: workoutSourceKeyForDailyMission(preset, DateTime.now()),
    isEs: isEs,
  );
}

Future<void> _openSharedWorkouts(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await requireSocialAccount(context, ref) || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const SharedWorkoutInboxScreen()),
  );
}

class TrainingProgressView extends ConsumerWidget {
  final TrainingProgress progress;
  final bool isEs;
  final VoidCallback onStartTraining;

  const TrainingProgressView({
    super.key,
    required this.progress,
    required this.isEs,
    required this.onStartTraining,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeState = ref.watch(badgeProgressProvider);
    final badges = ref.watch(badgeViewsProvider);
    final todayReps = progress.repsForDate(DateTime.now());
    final streak =
        math.max(progress.currentStreak(), badgeState.stats.currentStreak);
    final weekly = _weeklyStats(progress);
    final masteryMetrics = _masteryMetrics(progress, badgeState.stats);
    final spotlightMetrics = _spotlightMasteryMetrics(masteryMetrics);
    final nextBadge = _nextProgressBadge(badges);
    final nextStreakBadge = _nextBadgeInCategory(badges, BadgeCategory.streak);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ProgressCommandCenter(
            todayReps: todayReps,
            weeklyReps: weekly.totalReps,
            streak: streak,
            nextBadge: nextBadge,
            onStartTraining: onStartTraining,
            isEs: isEs,
          ),
          const SizedBox(height: 16),
          _MomentumStrip(
            streak: streak,
            totalCallouts: progress.totalCallouts,
            totalTrainingMinutes: badgeState.stats.totalTrainingSeconds ~/ 60,
            earnedBadges: badges.where((badge) => badge.isUnlocked).length,
            isEs: isEs,
          ),
          const SizedBox(height: 20),
          _SectionTitle(
            text: isEs ? 'Tableros de dominio 1,000' : '1,000 Mastery Boards',
          ),
          const SizedBox(height: 10),
          _ProgressGrid(metrics: spotlightMetrics),
          const SizedBox(height: 22),
          _SectionTitle(
            text: isEs ? 'Progreso por movimiento' : 'Move-specific progress',
          ),
          const SizedBox(height: 10),
          _MoveProgressList(metrics: masteryMetrics),
          const SizedBox(height: 20),
          _StreakSeasonGrid(
            progress: progress,
            badgeState: badgeState,
            nextStreakBadge: nextStreakBadge,
            weekly: weekly,
            isEs: isEs,
          ),
          const SizedBox(height: 20),
          _WeeklyStatsPanel(weekly: weekly, isEs: isEs),
          const SizedBox(height: 22),
          _SectionTitle(text: isEs ? 'Badges' : 'Badges'),
          const SizedBox(height: 10),
          BadgeProgressSection(isEs: isEs),
        ],
      ),
    );
  }
}

class RecordingsView extends ConsumerWidget {
  final bool isEs;
  final bool recordingEnabled;
  final ValueChanged<bool> onRecordingChanged;
  final VoidCallback onStartRecordedDrill;

  const RecordingsView({
    super.key,
    required this.isEs,
    required this.recordingEnabled,
    required this.onRecordingChanged,
    required this.onStartRecordedDrill,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingsAsync = ref.watch(savedRecordingsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          recordingsAsync.when(
            data: (recordings) => _RecordingsHero(
              recordings: recordings,
              recordingEnabled: recordingEnabled,
              isEs: isEs,
              onRecordingChanged: onRecordingChanged,
              onStartRecordedDrill: onStartRecordedDrill,
            ),
            loading: () => _RecordingsHero(
              recordings: const [],
              recordingEnabled: recordingEnabled,
              isEs: isEs,
              onRecordingChanged: onRecordingChanged,
              onStartRecordedDrill: onStartRecordedDrill,
              loading: true,
            ),
            error: (_, __) => _RecordingsHero(
              recordings: const [],
              recordingEnabled: recordingEnabled,
              isEs: isEs,
              onRecordingChanged: onRecordingChanged,
              onStartRecordedDrill: onStartRecordedDrill,
              error: true,
            ),
          ),
          const SizedBox(height: 18),
          _SectionTitle(
            text: isEs ? 'Videos de review' : 'Saved review videos',
          ),
          const SizedBox(height: 10),
          recordingsAsync.when(
            data: (recordings) {
              if (recordings.isEmpty) {
                return _EmptyRecordingLibrary(
                  isEs: isEs,
                  onStartRecordedDrill: onStartRecordedDrill,
                );
              }
              return _SavedRecordingList(
                recordings: recordings,
                isEs: isEs,
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => _RecordingError(
              isEs: isEs,
              onRetry: () {
                ref.read(savedRecordingsProvider.notifier).refreshLibrary();
              },
            ),
          ),
        ],
      ),
    );
  }
}
