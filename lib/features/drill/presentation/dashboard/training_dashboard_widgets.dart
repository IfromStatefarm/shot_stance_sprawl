part of '../training_dashboard.dart';

class _RecordingsHero extends StatelessWidget {
  final List<SavedWorkoutVideo> recordings;
  final bool recordingEnabled;
  final bool isEs;
  final ValueChanged<bool> onRecordingChanged;
  final VoidCallback onStartRecordedDrill;
  final bool loading;
  final bool error;

  const _RecordingsHero({
    required this.recordings,
    required this.recordingEnabled,
    required this.isEs,
    required this.onRecordingChanged,
    required this.onStartRecordedDrill,
    this.loading = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final totalSeconds = recordings.fold<int>(
      0,
      (sum, video) => sum + video.durationSeconds,
    );
    final latest = recordings.isEmpty ? null : recordings.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppBrandColors.blue.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: recordingEnabled
                      ? AppBrandColors.red
                      : AppBrandColors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  recordingEnabled
                      ? Icons.fiber_manual_record
                      : Icons.video_library,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEs ? 'Sala de review' : 'Review Room',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppBrandColors.white,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    Text(
                      error
                          ? (isEs
                              ? 'No se pudo cargar'
                              : 'Could not load library')
                          : latest == null
                              ? (isEs
                                  ? 'Graba tu primer drill'
                                  : 'Record your first drill')
                              : '${isEs ? 'Ultimo' : 'Latest'} ${_formatRecordingDate(latest.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppBrandColors.gold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: recordingEnabled,
                onChanged: onRecordingChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _VaultStat(
                  label: isEs ? 'Videos' : 'Videos',
                  value: loading ? '--' : '${recordings.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _VaultStat(
                  label: isEs ? 'Tiempo' : 'Time',
                  value: loading ? '--' : _formatDurationCompact(totalSeconds),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStartRecordedDrill,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: Text(isEs ? 'Grabar review' : 'Record Review'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppBrandColors.red,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _LocalOnlyChip(isEs: isEs),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedRecordingList extends ConsumerWidget {
  final List<SavedWorkoutVideo> recordings;
  final bool isEs;

  const _SavedRecordingList({
    required this.recordings,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final video in recordings) ...[
          _SavedRecordingTile(
            video: video,
            isEs: isEs,
            onPlay: () => _openRecording(context, ref, video, isEs),
            onShare: () => _shareRecording(context, ref, video, isEs),
            onDelete: () => _confirmDeleteRecording(context, ref, video, isEs),
          ),
          if (video != recordings.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SavedRecordingTile extends StatelessWidget {
  final SavedWorkoutVideo video;
  final bool isEs;
  final VoidCallback onPlay;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _SavedRecordingTile({
    required this.video,
    required this.isEs,
    required this.onPlay,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: isEs ? 'Reproducir video' : 'Play video',
            child: Material(
              color: AppBrandColors.black,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPlay,
                child: SizedBox(
                  width: 70,
                  height: 76,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppBrandColors.red.withValues(alpha: 0.82),
                                AppBrandColors.black,
                                AppBrandColors.blue.withValues(alpha: 0.82),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            _clock(video.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEs ? 'Review guardado' : 'Saved Review',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatRecordingDate(video.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _RecordingPill(
                      icon: Icons.timer,
                      text: _clock(video.duration),
                    ),
                    _RecordingPill(
                      icon: Icons.campaign,
                      text: '${video.calloutsCompleted} callouts',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: isEs ? 'Compartir' : 'Share',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share),
                color: AppBrandColors.blue,
              ),
              IconButton(
                tooltip: isEs ? 'Eliminar' : 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: AppBrandColors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyRecordingLibrary extends StatelessWidget {
  final bool isEs;
  final VoidCallback onStartRecordedDrill;

  const _EmptyRecordingLibrary({
    required this.isEs,
    required this.onStartRecordedDrill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.blueLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppBrandColors.blue.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          const Icon(Icons.video_library, color: AppBrandColors.blue, size: 42),
          const SizedBox(height: 8),
          Text(
            isEs ? 'Sin videos de review' : 'No review videos yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppBrandColors.blue,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            isEs
                ? 'Tu proximo drill grabado aparecera aqui.'
                : 'Your next recorded drill review will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onStartRecordedDrill,
            icon: const Icon(Icons.fiber_manual_record),
            label: Text(isEs ? 'Grabar ahora' : 'Record Review'),
          ),
        ],
      ),
    );
  }
}

class _RecordingError extends StatelessWidget {
  final bool isEs;
  final VoidCallback onRetry;

  const _RecordingError({
    required this.isEs,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.redLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppBrandColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEs
                  ? 'No se pudieron cargar los videos.'
                  : 'Saved videos could not be loaded.',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: isEs ? 'Reintentar' : 'Retry',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _VaultStat extends StatelessWidget {
  final String label;
  final String value;

  const _VaultStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppBrandColors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppBrandColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppBrandColors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOnlyChip extends StatelessWidget {
  final bool isEs;

  const _LocalOnlyChip({required this.isEs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: AppBrandColors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_iphone, color: AppBrandColors.gold, size: 18),
          const SizedBox(width: 6),
          Text(
            isEs ? 'Local' : 'Local',
            style: const TextStyle(
              color: AppBrandColors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RecordingPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppBrandColors.blue),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCommandCenter extends StatelessWidget {
  final int todayReps;
  final int weeklyReps;
  final int streak;
  final Badge? nextBadge;
  final VoidCallback onStartTraining;
  final bool isEs;

  const _ProgressCommandCenter({
    required this.todayReps,
    required this.weeklyReps,
    required this.streak,
    required this.nextBadge,
    required this.onStartTraining,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final todayPct = (todayReps / _dailyRepGoal).clamp(0.0, 1.0).toDouble();
    final badge = nextBadge;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppBrandColors.red.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppBrandColors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.query_stats, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEs ? 'Progreso' : 'Progress',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppBrandColors.white,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    Text(
                      badge == null
                          ? (isEs ? 'Sigue acumulando' : 'Keep stacking')
                          : _badgeChaseLine(badge),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppBrandColors.gold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onStartTraining,
                icon: const Icon(Icons.play_arrow),
                label: Text(isEs ? 'Entrenar' : 'Train'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppBrandColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: todayPct,
              minHeight: 9,
              backgroundColor: AppBrandColors.white.withValues(alpha: 0.16),
              valueColor: const AlwaysStoppedAnimation(AppBrandColors.gold),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DarkPill(
                icon: Icons.flag,
                text: '$todayReps / $_dailyRepGoal today',
              ),
              _DarkPill(
                icon: Icons.calendar_view_week,
                text: '${_formatNumber(weeklyReps)} this week',
              ),
              _DarkPill(
                icon: Icons.local_fire_department,
                text: '$streak day streak',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MomentumStrip extends StatelessWidget {
  final int streak;
  final int totalCallouts;
  final int totalTrainingMinutes;
  final int earnedBadges;
  final bool isEs;

  const _MomentumStrip({
    required this.streak,
    required this.totalCallouts,
    required this.totalTrainingMinutes,
    required this.earnedBadges,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      _MiniStatData(
        label: isEs ? 'Racha' : 'Streak',
        value: '$streak',
        suffix: isEs ? 'dias' : 'days',
        color: AppBrandColors.gold,
        icon: Icons.local_fire_department,
      ),
      _MiniStatData(
        label: isEs ? 'Comandos' : 'Callouts',
        value: _formatNumber(totalCallouts),
        suffix: isEs ? 'total' : 'total',
        color: AppBrandColors.blue,
        icon: Icons.campaign,
      ),
      _MiniStatData(
        label: isEs ? 'Minutos' : 'Minutes',
        value: _formatNumber(totalTrainingMinutes),
        suffix: isEs ? 'total' : 'total',
        color: AppBrandColors.red,
        icon: Icons.timer,
      ),
      _MiniStatData(
        label: isEs ? 'Badges' : 'Badges',
        value: '$earnedBadges',
        suffix: isEs ? 'ganados' : 'earned',
        color: AppBrandColors.goldDark,
        icon: Icons.workspace_premium,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final stat in stats)
              SizedBox(width: width, child: _MomentumTile(stat: stat)),
          ],
        );
      },
    );
  }
}

class _MoveProgressList extends StatelessWidget {
  final List<_ProgressMetric> metrics;

  const _MoveProgressList({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            _MoveProgressRow(metric: metrics[i]),
            if (i != metrics.length - 1)
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _MoveProgressRow extends StatelessWidget {
  final _ProgressMetric metric;

  const _MoveProgressRow({required this.metric});

  @override
  Widget build(BuildContext context) {
    final pct = metric.target == 0
        ? 0.0
        : (metric.current / metric.target).clamp(0.0, 1.0).toDouble();
    final remaining = math.max(0, metric.target - metric.current);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, color: metric.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: TextStyle(
                        color: metric.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: metric.color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(metric.color),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatNumber(metric.current)} / '
                  '${_formatNumber(metric.target)}${metric.unitSuffix}  '
                  '${_formatNumber(remaining)}${metric.unitSuffix} left',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
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

class _StreakSeasonGrid extends StatelessWidget {
  final TrainingProgress progress;
  final BadgeProgressState badgeState;
  final Badge? nextStreakBadge;
  final _WeeklyStats weekly;
  final bool isEs;

  const _StreakSeasonGrid({
    required this.progress,
    required this.badgeState,
    required this.nextStreakBadge,
    required this.weekly,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 620;
        final children = [
          _StreakPanel(
            streak: math.max(
              progress.currentStreak(),
              badgeState.stats.currentStreak,
            ),
            nextStreakBadge: nextStreakBadge,
            noPauseWorkouts: badgeState.stats.noPauseWorkoutCount,
            totalWorkouts: badgeState.stats.totalWorkouts,
            isEs: isEs,
          ),
          _SeasonPanel(
            progress: progress,
            weekly: weekly,
            totalWorkouts: badgeState.stats.totalWorkouts,
            isEs: isEs,
          ),
        ];

        if (stack) {
          return Column(
            children: [
              children[0],
              const SizedBox(height: 12),
              children[1],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

class _StreakPanel extends StatelessWidget {
  final int streak;
  final Badge? nextStreakBadge;
  final int noPauseWorkouts;
  final int totalWorkouts;
  final bool isEs;

  const _StreakPanel({
    required this.streak,
    required this.nextStreakBadge,
    required this.noPauseWorkouts,
    required this.totalWorkouts,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final target = nextStreakBadge?.targetProgress ?? math.max(streak, 1);
    final pct =
        target == 0 ? 1.0 : (streak / target).clamp(0.0, 1.0).toDouble();
    final daysLeft = math.max(0, target - streak);

    return _PanelShell(
      title: isEs ? 'Rachas' : 'Streaks',
      icon: Icons.local_fire_department,
      color: AppBrandColors.gold,
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: _ChaseRing(
                  progress: pct,
                  rawProgress: pct,
                  color: AppBrandColors.gold,
                  icon: Icons.local_fire_department,
                  isComplete: daysLeft == 0 && streak > 0,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$streak ${isEs ? 'dias' : 'days'}',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextStreakBadge == null
                          ? (isEs ? 'Racha maxima' : 'Max streak ladder')
                          : '$daysLeft ${isEs ? 'dias para' : 'days to'} '
                              '${nextStreakBadge!.displayTitle}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Sin pausa' : 'No pause',
                  value: _formatNumber(noPauseWorkouts),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Workouts' : 'Workouts',
                  value: _formatNumber(totalWorkouts),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeasonPanel extends StatelessWidget {
  final TrainingProgress progress;
  final _WeeklyStats weekly;
  final int totalWorkouts;
  final bool isEs;

  const _SeasonPanel({
    required this.progress,
    required this.weekly,
    required this.totalWorkouts,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final daysLeft = progress.daysUntilState();
    final targetDate = progress.stateDate;
    final weeklyAverage = weekly.averageReps.round();

    return _PanelShell(
      title: isEs ? 'Temporada' : 'Season Stats',
      icon: Icons.emoji_events,
      color: AppBrandColors.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            daysLeft == null
                ? (isEs ? 'Sin fecha' : 'No target date')
                : '$daysLeft ${isEs ? 'dias' : 'days'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            targetDate == null
                ? (isEs ? 'Configura tu meta' : 'Set a target date')
                : '${isEs ? 'Fecha' : 'Target'} ${_formatShortDate(targetDate)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Semana' : 'Week reps',
                  value: _formatNumber(weekly.totalReps),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Promedio' : 'Avg/day',
                  value: _formatNumber(weeklyAverage),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PanelStat(
            label: isEs ? 'Workouts de temporada' : 'Season workouts',
            value: _formatNumber(totalWorkouts),
          ),
        ],
      ),
    );
  }
}

class _WeeklyStatsPanel extends StatelessWidget {
  final _WeeklyStats weekly;
  final bool isEs;

  const _WeeklyStatsPanel({
    required this.weekly,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final maxReps = math.max(1, weekly.bestReps);

    return _PanelShell(
      title: isEs ? 'Semana' : 'Weekly Stats',
      icon: Icons.calendar_view_week,
      color: AppBrandColors.red,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Total' : 'Total',
                  value: _formatNumber(weekly.totalReps),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Dias activos' : 'Active days',
                  value: '${weekly.activeDays}/7',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PanelStat(
                  label: isEs ? 'Mejor dia' : 'Best day',
                  value: _formatNumber(weekly.bestReps),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in weekly.days) ...[
                Expanded(
                  child: _WeeklyBar(
                    day: day,
                    maxReps: maxReps,
                  ),
                ),
                if (day != weekly.days.last) const SizedBox(width: 7),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyBar extends StatelessWidget {
  final _WeeklyDay day;
  final int maxReps;

  const _WeeklyBar({
    required this.day,
    required this.maxReps,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (day.reps / maxReps).clamp(0.0, 1.0).toDouble();
    final height = 18 + (pct * 54);
    final isToday = TrainingProgress.dateKey(day.date) ==
        TrainingProgress.dateKey(DateTime.now());

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          day.reps == 0 ? '' : _formatNumber(day.reps),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: isToday ? AppBrandColors.red : null,
              ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          height: height,
          decoration: BoxDecoration(
            color: isToday ? AppBrandColors.red : AppBrandColors.blue,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: (isToday ? AppBrandColors.red : AppBrandColors.blue)
                    .withValues(alpha: day.reps > 0 ? 0.2 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _dayInitial(day.date),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: isToday
                    ? AppBrandColors.red
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _PanelShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  const _PanelShell({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PanelStat extends StatelessWidget {
  final String label;
  final String value;

  const _PanelStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentumTile extends StatelessWidget {
  final _MiniStatData stat;

  const _MomentumTile({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: stat.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: stat.color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(stat.icon, color: stat.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: stat.color,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${stat.value} ${stat.suffix}',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
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

class _DarkPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DarkPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppBrandColors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppBrandColors.gold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppBrandColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatData {
  final String label;
  final String value;
  final String suffix;
  final Color color;
  final IconData icon;

  const _MiniStatData({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
    required this.icon,
  });
}

class _WeeklyStats {
  final List<_WeeklyDay> days;
  final int totalReps;
  final int activeDays;
  final int bestReps;
  final double averageReps;

  const _WeeklyStats({
    required this.days,
    required this.totalReps,
    required this.activeDays,
    required this.bestReps,
    required this.averageReps,
  });
}

class _WeeklyDay {
  final DateTime date;
  final int reps;

  const _WeeklyDay({
    required this.date,
    required this.reps,
  });
}

class _DashboardHeader extends ConsumerStatefulWidget {
  final TrainingProgress progress;
  final bool isEs;

  const _DashboardHeader({
    required this.progress,
    required this.isEs,
  });

  @override
  ConsumerState<_DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends ConsumerState<_DashboardHeader>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextDay();
  }

  void _scheduleNextDay() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleNextDay();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleNextDay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  String _headline(SeasonCountdown? countdown, bool loaded) {
    if (countdown == null) {
      return !loaded
          ? (widget.isEs ? 'Cargando temporada...' : 'Loading season...')
          : (widget.isEs ? 'Selecciona tu estado' : 'Choose your state');
    }
    if (countdown.isToday) {
      if (countdown.phase == SeasonCountdownPhase.postseasonEnd) {
        return widget.isEs ? 'La postemporada terminó' : 'Post Season is Over';
      }
      return widget.isEs
          ? '¡Hoy es el día! ¡Buena suerte!'
          : "Today's the Day. Good luck!";
    }
    final days = countdown.daysRemaining;
    if (widget.isEs) {
      final label = switch (countdown.phase) {
        SeasonCountdownPhase.seasonStart => 'La temporada empieza',
        SeasonCountdownPhase.postseasonStart => 'La postemporada empieza',
        SeasonCountdownPhase.postseasonEnd => 'La postemporada termina',
      };
      return '$label en $days ${days == 1 ? 'día' : 'días'}';
    }
    final label = switch (countdown.phase) {
      SeasonCountdownPhase.seasonStart => 'Season starts',
      SeasonCountdownPhase.postseasonStart => 'Post Season starts',
      SeasonCountdownPhase.postseasonEnd => 'Post Season ends',
    };
    return '$label in $days ${days == 1 ? 'day' : 'days'}';
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final stateName = onboarding.profile?.stateName;
    final countdown =
        stateName != null && seasonDatesByState.containsKey(stateName)
            ? countdownForState(stateName, DateTime.now())
            : null;
    final todayReps = widget.progress.repsForDate(DateTime.now());
    final streak = widget.progress.currentStreak();
    final pct = (todayReps / _dailyRepGoal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppBrandColors.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: AppBrandColors.black,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _headline(countdown, onboarding.loaded),
                  maxLines: 2,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppBrandColors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          if (countdown != null) ...[
            const SizedBox(height: 6),
            Text(
              '${countdown.title} • $stateName • ${_formatShortDate(countdown.targetDate)}',
              style: const TextStyle(
                color: AppBrandColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (onboarding.loaded &&
              countdown == null &&
              onboarding.profile != null) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: widget.isEs ? 'Seleccionar estado' : 'Select state',
                filled: true,
                fillColor: AppBrandColors.white,
                border: const OutlineInputBorder(),
              ),
              dropdownColor: AppBrandColors.white,
              items: [
                for (final name in seasonDatesByState.keys)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (name) {
                if (name != null) {
                  unawaited(
                      ref.read(onboardingProvider.notifier).setStateName(name));
                }
              },
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderPill(
                icon: Icons.flag,
                text: widget.isEs
                    ? 'Meta de hoy: $_dailyRepGoal reps'
                    : "Today's goal: $_dailyRepGoal reps",
              ),
              _HeaderPill(
                icon: Icons.local_fire_department,
                text: widget.isEs
                    ? 'Racha actual: $streak dias'
                    : 'Current streak: $streak days',
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppBrandColors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation(AppBrandColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppBrandColors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppBrandColors.gold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppBrandColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final bool isEs;
  final bool loading;
  final WorkoutPreset preset;
  final VoidCallback? onStartMission;
  final VoidCallback onBrowseWorkouts;
  final VoidCallback onSendWorkout;
  final VoidCallback onOpenSharedWorkouts;
  final int unreadSharedWorkoutCount;
  final VoidCallback onCustomizeDrill;

  const _MissionCard({
    required this.isEs,
    required this.loading,
    required this.preset,
    required this.onStartMission,
    required this.onBrowseWorkouts,
    required this.onSendWorkout,
    required this.onOpenSharedWorkouts,
    required this.unreadSharedWorkoutCount,
    required this.onCustomizeDrill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppBrandColors.gold.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: AppBrandColors.red.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppBrandColors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flash_on, color: AppBrandColors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEs ? 'Mision de hoy' : "Today's mission",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppBrandColors.gold,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            preset.title(isEs: isEs),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppBrandColors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            preset.purpose(isEs: isEs),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppBrandColors.white.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MissionPill(
                icon: Icons.timer,
                text: preset.durationLabel(isEs: isEs),
              ),
              _MissionPill(
                icon: Icons.speed,
                text: isEs
                    ? 'Nivel ${preset.difficultyLabel(isEs: isEs)}'
                    : 'Level ${preset.difficultyLabel(isEs: isEs)}',
              ),
              _MissionPill(
                icon: Icons.bolt,
                text: isEs
                    ? '${preset.calloutIds.length} comandos'
                    : '${preset.calloutIds.length} callouts',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preset.calloutListLabel(isEs: isEs),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppBrandColors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : onStartMission,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
              isEs ? 'Iniciar mision de hoy' : "Start Today's Mission",
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: AppBrandColors.red,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MissionActionButton(
                  onPressed: onBrowseWorkouts,
                  icon: Icons.view_carousel,
                  label: 'Workouts',
                  foregroundColor: AppBrandColors.gold,
                  borderColor: AppBrandColors.gold,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MissionActionButton(
                  onPressed: onSendWorkout,
                  icon: Icons.send_rounded,
                  label: isEs ? 'Enviar' : 'Send',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MissionActionButton(
                  onPressed: onOpenSharedWorkouts,
                  icon: Icons.move_to_inbox_outlined,
                  label: isEs ? 'Recibidos' : 'Shared',
                  unreadCount: unreadSharedWorkoutCount,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCustomizeDrill,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(isEs ? 'Personalizar drill' : 'Customize drill'),
              style: TextButton.styleFrom(
                foregroundColor: AppBrandColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionActionButton extends StatelessWidget {
  const _MissionActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.unreadCount = 0,
    this.foregroundColor = AppBrandColors.white,
    this.borderColor,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final int unreadCount;
  final Color foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        foregroundColor: foregroundColor,
        side: BorderSide(
          color: borderColor ?? AppBrandColors.white.withValues(alpha: 0.34),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MissionActionIcon(icon: icon, unreadCount: unreadCount),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionActionIcon extends StatelessWidget {
  const _MissionActionIcon({required this.icon, required this.unreadCount});

  final IconData icon;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final displayCount = unreadCount > 99 ? '99+' : '$unreadCount';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 20),
        if (unreadCount > 0)
          Positioned(
            top: -9,
            right: -14,
            child: Semantics(
              label: '$unreadCount unread shared workouts',
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppBrandColors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  displayCount,
                  style: const TextStyle(
                    color: AppBrandColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MissionPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MissionPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppBrandColors.redLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppBrandColors.redDark),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppBrandColors.redDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _ProgressGrid extends StatelessWidget {
  final List<_ProgressMetric> metrics;

  const _ProgressGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 4 ? 0.86 : 0.78,
          ),
          itemBuilder: (context, index) {
            return _ProgressChaseCard(metric: metrics[index]);
          },
        );
      },
    );
  }
}

class _ProgressChaseCard extends StatelessWidget {
  final _ProgressMetric metric;

  const _ProgressChaseCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final rawPct = metric.target == 0
        ? 0.0
        : (metric.current / metric.target).clamp(0.0, 1.0).toDouble();
    final visualPct = rawPct >= 1.0 ? 1.0 : 0.15 + (rawPct * 0.85);
    final remaining = math.max(0, metric.target - metric.current);
    final isComplete = rawPct >= 1.0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: metric.color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: metric.color.withValues(alpha: isComplete ? 0.48 : 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: metric.color.withValues(alpha: isComplete ? 0.18 : 0.08),
            blurRadius: isComplete ? 18 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(metric.icon, color: metric.color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.15, end: visualPct),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return _ChaseRing(
                    progress: value,
                    rawProgress: rawPct,
                    color: metric.color,
                    icon: metric.icon,
                    isComplete: isComplete,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${_formatNumber(metric.current)} / ${_formatNumber(metric.target)}${metric.unitSuffix}',
              maxLines: 1,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              isComplete
                  ? 'Complete'
                  : '${_formatNumber(remaining)}${metric.unitSuffix} left',
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: metric.color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChaseRing extends StatelessWidget {
  final double progress;
  final double rawProgress;
  final Color color;
  final IconData icon;
  final bool isComplete;

  const _ChaseRing({
    required this.progress,
    required this.rawProgress,
    required this.color,
    required this.icon,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ChaseRingPainter(
                progress: progress,
                color: color,
                isComplete: isComplete,
              ),
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 18),
                    Text(
                      '${(rawProgress * 100).clamp(0, 100).round()}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChaseRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isComplete;

  const _ChaseRingPainter({
    required this.progress,
    required this.color,
    required this.isComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.11;
    final inset = strokeWidth / 2 + 2;
    final rect = Offset(inset, inset) &
        Size(size.width - inset * 2, size.height - inset * 2);
    const gap = math.pi / 4;
    const startAngle = -math.pi / 2 + gap / 2;
    const trackSweep = math.pi * 2 - gap;
    final sweep = trackSweep * progress.clamp(0.0, 1.0);

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = color.withValues(alpha: isComplete ? 0.32 : 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 7
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + trackSweep,
        colors: [
          color.withValues(alpha: 0.72),
          color,
          AppBrandColors.gold,
          color,
        ],
        stops: const [0.0, 0.46, 0.78, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, trackSweep, false, trackPaint);
    canvas.drawArc(rect, startAngle, sweep, false, glowPaint);
    canvas.drawArc(rect, startAngle, sweep, false, progressPaint);

    final endAngle = startAngle + sweep;
    final radius = rect.width / 2;
    final center = rect.center;
    final end = Offset(
      center.dx + math.cos(endAngle) * radius,
      center.dy + math.sin(endAngle) * radius,
    );
    canvas.drawCircle(end, strokeWidth * 0.45, Paint()..color = Colors.white);
    canvas.drawCircle(end, strokeWidth * 0.28, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ChaseRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isComplete != isComplete;
  }
}

class _ProgressMetric {
  final String label;
  final int current;
  final int target;
  final IconData icon;
  final Color color;
  final String unitSuffix;

  const _ProgressMetric({
    required this.label,
    required this.current,
    required this.target,
    required this.icon,
    required this.color,
    this.unitSuffix = '',
  });
}

List<_ProgressMetric> _masteryMetrics(
  TrainingProgress progress,
  BadgeStats stats,
) {
  int timedMinutes(String id) {
    final badgeMinutes = (stats.timedSecondsByCallout[id] ?? 0) ~/ 60;
    if (id == 'stance') {
      return math.max(progress.stanceMinutes, badgeMinutes);
    }
    return badgeMinutes;
  }

  return [
    _ProgressMetric(
      label: 'Shots',
      current: progress.calloutCount('shot'),
      target: 1000,
      icon: Icons.sports_mma,
      color: AppBrandColors.red,
    ),
    _ProgressMetric(
      label: 'Sprawls',
      current: progress.calloutCount('sprawl'),
      target: 1000,
      icon: Icons.keyboard_double_arrow_down,
      color: AppBrandColors.blue,
    ),
    _ProgressMetric(
      label: 'Stance Time',
      current: timedMinutes('stance'),
      target: 1000,
      icon: Icons.accessibility_new,
      color: AppBrandColors.goldDark,
      unitSuffix: ' min',
    ),
    _ProgressMetric(
      label: 'Fakes',
      current: progress.calloutCount('fake'),
      target: 1000,
      icon: Icons.bolt,
      color: AppBrandColors.black,
    ),
    _ProgressMetric(
      label: 'Down Blocks',
      current: progress.calloutCount('down_block'),
      target: 1000,
      icon: Icons.shield,
      color: AppBrandColors.redDark,
    ),
    _ProgressMetric(
      label: 'Circles',
      current: progress.calloutCount('circle'),
      target: 1000,
      icon: Icons.rotate_right,
      color: AppBrandColors.blue,
    ),
    _ProgressMetric(
      label: 'Snap Downs',
      current: progress.calloutCount('snap_down'),
      target: 1000,
      icon: Icons.pan_tool_alt,
      color: AppBrandColors.goldDark,
    ),
    _ProgressMetric(
      label: 'Level Changes',
      current: progress.calloutCount('level_change'),
      target: 1000,
      icon: Icons.swap_vert,
      color: AppBrandColors.red,
    ),
    _ProgressMetric(
      label: 'Handfight Time',
      current: timedMinutes('hand_fight'),
      target: 1000,
      icon: Icons.back_hand,
      color: AppBrandColors.black,
      unitSuffix: ' min',
    ),
    _ProgressMetric(
      label: 'High Knees',
      current: timedMinutes('high_knees'),
      target: 1000,
      icon: Icons.directions_run,
      color: AppBrandColors.blue,
      unitSuffix: ' min',
    ),
    _ProgressMetric(
      label: 'Foot Fire',
      current: timedMinutes('foot_fire'),
      target: 1000,
      icon: Icons.local_fire_department,
      color: AppBrandColors.red,
      unitSuffix: ' min',
    ),
  ];
}

List<_ProgressMetric> _spotlightMasteryMetrics(List<_ProgressMetric> metrics) {
  if (metrics.every((metric) => metric.current == 0)) {
    return metrics.take(4).toList();
  }

  final sorted = [...metrics]..sort((a, b) {
      final aPct = a.target == 0 ? 0.0 : a.current / a.target;
      final bPct = b.target == 0 ? 0.0 : b.current / b.target;
      final pctCompare = bPct.compareTo(aPct);
      if (pctCompare != 0) return pctCompare;
      return (a.target - a.current).compareTo(b.target - b.current);
    });

  return sorted.take(4).toList();
}

List<_ProgressMetric> _coreProgressMetrics(TrainingProgress progress) {
  return [
    _ProgressMetric(
      label: 'Single Legs',
      current: progress.calloutCount('shot'),
      target: 1000,
      icon: Icons.fitness_center,
      color: AppBrandColors.red,
    ),
    _ProgressMetric(
      label: 'Sprawls',
      current: progress.calloutCount('sprawl'),
      target: 1000,
      icon: Icons.arrow_downward,
      color: AppBrandColors.blue,
    ),
    _ProgressMetric(
      label: 'Stance Time',
      current: progress.stanceMinutes,
      target: 1000,
      icon: Icons.timer,
      color: AppBrandColors.goldDark,
      unitSuffix: ' min',
    ),
    _ProgressMetric(
      label: 'Fakes',
      current: progress.calloutCount('fake'),
      target: 1000,
      icon: Icons.bolt,
      color: AppBrandColors.black,
    ),
  ];
}

_WeeklyStats _weeklyStats(TrainingProgress progress, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final days = [
    for (var offset = 6; offset >= 0; offset--)
      _WeeklyDay(
        date: today.subtract(Duration(days: offset)),
        reps: progress.repsForDate(today.subtract(Duration(days: offset))),
      ),
  ];
  final total = days.fold<int>(0, (sum, day) => sum + day.reps);
  final active = days.where((day) => day.reps > 0).length;
  final best =
      days.fold<int>(0, (maxValue, day) => math.max(maxValue, day.reps));

  return _WeeklyStats(
    days: days,
    totalReps: total,
    activeDays: active,
    bestReps: best,
    averageReps: total / 7,
  );
}

Badge? _nextProgressBadge(List<Badge> badges) {
  final candidates = badges
      .where(
          (badge) => !badge.isUnlocked && !badge.isPremium && !badge.isSecret)
      .toList()
    ..sort((a, b) {
      final almostCompare =
          (b.isAlmostThere ? 1 : 0).compareTo(a.isAlmostThere ? 1 : 0);
      if (almostCompare != 0) return almostCompare;
      final ratioCompare = b.completionRatio.compareTo(a.completionRatio);
      if (ratioCompare != 0) return ratioCompare;
      return _badgeRemaining(a).compareTo(_badgeRemaining(b));
    });

  return candidates.isEmpty ? null : candidates.first;
}

Badge? _nextBadgeInCategory(List<Badge> badges, BadgeCategory category) {
  final candidates = badges
      .where((badge) => badge.category == category && !badge.isUnlocked)
      .toList()
    ..sort((a, b) => a.targetProgress.compareTo(b.targetProgress));

  return candidates.isEmpty ? null : candidates.first;
}

Future<void> _openRecording(
  BuildContext context,
  WidgetRef ref,
  SavedWorkoutVideo video,
  bool isEs,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await LocalFileStorage.localFileExists(video.path)) {
    await ref.read(savedRecordingsProvider.notifier).deleteVideo(video.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isEs
              ? 'El video ya no existe en este telefono.'
              : 'That video is no longer on this phone.',
        ),
      ),
    );
    return;
  }

  final result = await OpenFilex.open(video.path, type: 'video/mp4');
  if (result.type == ResultType.done) return;

  if (result.type == ResultType.fileNotFound) {
    await ref.read(savedRecordingsProvider.notifier).deleteVideo(video.id);
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        isEs
            ? 'No se pudo abrir el video en este telefono.'
            : 'Could not open this video on this phone.',
      ),
    ),
  );
}

Future<void> _shareRecording(
  BuildContext context,
  WidgetRef ref,
  SavedWorkoutVideo video,
  bool isEs,
) async {
  if (!await requireConnectedFeatureEligibility(context, ref) ||
      !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  if (!await LocalFileStorage.localFileExists(video.path)) {
    await ref.read(savedRecordingsProvider.notifier).deleteVideo(video.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isEs
              ? 'El video ya no existe en este telefono.'
              : 'That video is no longer on this phone.',
        ),
      ),
    );
    return;
  }

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(video.path)],
      text: 'Snap & Go review video',
      subject: 'Snap & Go Review',
      sharePositionOrigin: origin,
    ),
  );
}

Future<void> _confirmDeleteRecording(
  BuildContext context,
  WidgetRef ref,
  SavedWorkoutVideo video,
  bool isEs,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(isEs ? 'Eliminar video?' : 'Delete video?'),
        content: Text(
          isEs
              ? 'Este video se quitara de tus grabaciones locales.'
              : 'This video will be removed from your local review library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppBrandColors.red),
            child: Text(isEs ? 'Eliminar' : 'Delete'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) return;
  await ref.read(savedRecordingsProvider.notifier).deleteVideo(video.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEs ? 'Video eliminado' : 'Video deleted'),
      ),
    );
  }
}

String _badgeChaseLine(Badge badge) {
  return '${_formatNumber(_badgeRemaining(badge))} '
      '${_badgeUnit(badge)} to ${badge.displayTitle}';
}

int _badgeRemaining(Badge badge) {
  return (badge.targetProgress - badge.currentProgress).clamp(0, 1 << 30);
}

String _badgeUnit(Badge badge) {
  final remaining = _badgeRemaining(badge);
  final plural = remaining == 1 ? '' : 's';
  if (badge.category == BadgeCategory.streak) return 'day$plural';
  if (badge.category == BadgeCategory.timedMastery ||
      badge.iconName == 'timer' ||
      badge.iconName == 'stance' ||
      badge.iconName == 'hand_fight' ||
      badge.iconName == 'high_knees' ||
      badge.iconName == 'foot_fire') {
    return 'minute$plural';
  }
  if (badge.category == BadgeCategory.grind) return 'workout$plural';
  if (badge.category == BadgeCategory.combo) return 'session$plural';
  return 'rep$plural';
}

String _formatNumber(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _formatShortDate(DateTime date) {
  return '${date.month}/${date.day}/${date.year}';
}

String _formatRecordingDate(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.month}/${date.day}/${date.year}  $hour:$minute $suffix';
}

String _formatDurationCompact(int seconds) {
  final duration = Duration(seconds: seconds);
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return '${duration.inHours}h ${minutes}m';
  }
  return '${duration.inMinutes}m';
}

String _clock(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _dayInitial(DateTime date) {
  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return labels[date.weekday - 1];
}
