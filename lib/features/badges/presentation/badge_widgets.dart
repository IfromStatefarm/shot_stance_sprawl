import 'dart:math' as math;

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_theme.dart';
import '../badge_models.dart';
import '../badge_progress_provider.dart';

class HomeBadgeChases extends ConsumerWidget {
  final bool isEs;

  const HomeBadgeChases({
    super.key,
    this.isEs = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chases = ref.watch(homeBadgeChasesProvider);
    if (chases.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppBrandColors.gold.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppBrandColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEs ? 'Persiguiendo ahora' : 'Chasing Now',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppBrandColors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final badge in chases) ...[
            _HomeChaseRow(badge: badge),
            if (badge != chases.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class BadgeProgressSection extends ConsumerWidget {
  final bool isEs;

  const BadgeProgressSection({
    super.key,
    this.isEs = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(badgeViewsProvider);
    final almostThere = ref.watch(almostThereBadgesProvider);
    final recentlyEarned = ref.watch(recentlyEarnedBadgesProvider);
    final moveMastery = badges.where((badge) {
      return badge.category == BadgeCategory.moveMastery ||
          badge.category == BadgeCategory.timedMastery;
    }).toList();
    final streaks = badges
        .where((badge) => badge.category == BadgeCategory.streak)
        .toList();
    final grindAndCombos = badges.where((badge) {
      return badge.category == BadgeCategory.grind ||
          badge.category == BadgeCategory.combo ||
          badge.category == BadgeCategory.season;
    }).toList();
    final bonus =
        badges.where((badge) => badge.category == BadgeCategory.flex).toList();
    final secrets = badges
        .where((badge) => badge.category == BadgeCategory.secret)
        .toList();
    final premium = badges
        .where((badge) => badge.category == BadgeCategory.premium)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BadgeSection(
          title: isEs ? 'Casi listo' : 'Almost There',
          badges: almostThere,
          emptyText: isEs
              ? 'Completa mas reps para activar una persecucion.'
              : 'Stack more reps to light up a chase.',
        ),
        _BadgeSection(
          title: isEs ? 'Ganadas recientemente' : 'Recently Earned',
          badges: recentlyEarned,
          emptyText: isEs
              ? 'Tu primer badge aparecera aqui.'
              : 'Your first unlocked badge will land here.',
        ),
        _BadgeSection(
          title: isEs ? 'Dominio de movimientos' : 'Move Mastery',
          badges: moveMastery,
        ),
        _BadgeSection(
          title: isEs ? 'Rachas' : 'Streaks',
          badges: streaks,
        ),
        _BadgeSection(
          title: isEs ? 'Trabajo y combos' : 'Grind + Combos',
          badges: grindAndCombos,
        ),
        _BadgeSection(
          title: isEs ? 'Badges bonus' : 'Bonus Badges',
          badges: bonus,
        ),
        _BadgeSection(
          title: isEs ? 'Badges secretos' : 'Secret Badges',
          badges: secrets,
        ),
        _BadgeSection(
          title: isEs ? 'Badges Coach Mode' : 'Coach Mode Badges',
          badges: premium,
        ),
      ],
    );
  }
}

class WorkoutBadgeSummary extends ConsumerWidget {
  final bool isEs;

  const WorkoutBadgeSummary({
    super.key,
    this.isEs = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(badgeProgressProvider);
    final result = state.lastWorkoutResult;
    if (result == null) return const SizedBox.shrink();

    final badgesById = {
      for (final badge in ref.watch(badgeViewsProvider)) badge.id: badge,
    };
    final unlocked = result.newlyUnlockedBadgeIds
        .map((id) => badgesById[id])
        .whereType<Badge>()
        .toList();
    final updates = result.updatedBadgeIds
        .where((id) => !result.newlyUnlockedBadgeIds.contains(id))
        .map((id) => badgesById[id])
        .whereType<Badge>()
        .where((badge) => badge.currentProgress > 0)
        .take(3)
        .toList();
    final almostThere = result.almostThereBadgeId == null
        ? null
        : badgesById[result.almostThereBadgeId!];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppBrandColors.gold.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: AppBrandColors.gold.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: AppBrandColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEs ? 'Recompensas del drill' : 'Workout Rewards',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RewardStat(
                  label: isEs ? 'Reps estimadas' : 'Estimated reps',
                  value: _formatNumber(result.estimatedRepsEarned),
                  color: AppBrandColors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RewardStat(
                  label: isEs ? 'Racha actual' : 'Current streak',
                  value: '${result.currentStreak}',
                  suffix: isEs ? ' dias' : ' days',
                  color: AppBrandColors.blue,
                ),
              ),
            ],
          ),
          if (unlocked.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              isEs ? 'Recien desbloqueados' : 'Newly Unlocked',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  return _BadgeTile(
                    badge: unlocked[index],
                    compact: true,
                    highlight: true,
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: unlocked.length,
              ),
            ),
          ],
          if (updates.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final badge in updates) _ProgressUpdateRow(badge: badge),
          ],
          if (almostThere != null) ...[
            const SizedBox(height: 12),
            _AlmostThereNudge(badge: almostThere),
          ],
        ],
      ),
    );
  }
}

class _HomeChaseRow extends StatelessWidget {
  final Badge badge;

  const _HomeChaseRow({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(badge.tier);

    return Row(
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: CustomPaint(
            painter: _MiniRingPainter(
              progress: badge.completionRatio,
              color: color,
            ),
            child: Icon(_badgeIcon(badge.iconName), color: color, size: 19),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _chaseText(badge),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppBrandColors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: badge.completionRatio,
                  minHeight: 6,
                  backgroundColor: AppBrandColors.white.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BadgeSection extends StatelessWidget {
  final String title;
  final List<Badge> badges;
  final String? emptyText;

  const _BadgeSection({
    required this.title,
    required this.badges,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final visibleBadges = badges.take(24).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (visibleBadges.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                emptyText ?? 'No badges here yet.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            SizedBox(
              height: 154,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  return _BadgeTile(badge: visibleBadges[index]);
                },
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: visibleBadges.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final Badge badge;
  final bool compact;
  final bool highlight;

  const _BadgeTile({
    required this.badge,
    this.compact = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = badge.isUnlocked ? _tierColor(badge.tier) : Colors.grey;
    final isLockedSecret = badge.isSecret && !badge.isUnlocked;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showBadgeDetails(context, badge),
      child: Container(
        width: compact ? 118 : 132,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: badge.isUnlocked
              ? color.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlight
                ? AppBrandColors.gold
                : color.withValues(alpha: badge.isUnlocked ? 0.45 : 0.18),
          ),
          boxShadow: badge.isUnlocked
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CustomPaint(
                    painter: _MiniRingPainter(
                      progress: badge.completionRatio,
                      color: color,
                      locked: !badge.isUnlocked,
                    ),
                    child: Icon(
                      isLockedSecret ? Icons.lock : _badgeIcon(badge.iconName),
                      color: color,
                      size: 20,
                    ),
                  ),
                ),
                const Spacer(),
                if (badge.isPremium)
                  const Icon(
                    Icons.workspace_premium,
                    size: 17,
                    color: AppBrandColors.gold,
                  )
                else if (badge.isUnlocked)
                  const Icon(
                    Icons.check_circle,
                    size: 17,
                    color: Colors.green,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              badge.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
            ),
            const Spacer(),
            Text(
              '${_formatNumber(badge.currentProgress)} / '
              '${_formatNumber(badge.targetProgress)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardStat extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  final Color color;

  const _RewardStat({
    required this.label,
    required this.value,
    required this.color,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value$suffix',
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressUpdateRow extends StatelessWidget {
  final Badge badge;

  const _ProgressUpdateRow({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(badge.tier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(_badgeIcon(badge.iconName), color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: badge.completionRatio,
                    minHeight: 5,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(badge.completionRatio * 100).round()}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _AlmostThereNudge extends StatelessWidget {
  final Badge badge;

  const _AlmostThereNudge({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppBrandColors.gold.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag, color: AppBrandColors.goldDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only ${_remainingText(badge)} until ${badge.displayTitle}.',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool locked;

  const _MiniRingPainter({
    required this.progress,
    required this.color,
    this.locked = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(3.0, size.shortestSide * 0.1);
    final rect = Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    const start = -math.pi / 2;
    final track = Paint()
      ..color = color.withValues(alpha: locked ? 0.16 : 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, start, math.pi * 2, false, track);
    canvas.drawArc(
      rect,
      start,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.locked != locked;
  }
}

void _showBadgeDetails(BuildContext context, Badge badge) {
  final color = badge.isUnlocked ? _tierColor(badge.tier) : Colors.grey;

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: _MiniRingPainter(
                      progress: badge.completionRatio,
                      color: color,
                      locked: !badge.isUnlocked,
                    ),
                    child: Icon(
                      badge.isSecret && !badge.isUnlocked
                          ? Icons.lock
                          : _badgeIcon(badge.iconName),
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        badge.displayTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        '${badge.tier.label} • ${badge.category.id}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              badge.displayDescription,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: badge.completionRatio,
                minHeight: 9,
                backgroundColor: color.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Progress: ${_formatNumber(badge.currentProgress)} / '
              '${_formatNumber(badge.targetProgress)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (badge.unlockedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Unlocked: ${_formatDate(badge.unlockedAt!)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ] else if (badge.isSecret && badge.hint != null) ...[
              const SizedBox(height: 8),
              Text(
                'Hint: ${badge.hint}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

String _chaseText(Badge badge) {
  if (badge.category == BadgeCategory.combo) {
    return 'Complete ${badge.displayTitle}';
  }
  return '${_remainingText(badge)} away from ${badge.displayTitle}';
}

String _remainingText(Badge badge) {
  final remaining =
      (badge.targetProgress - badge.currentProgress).clamp(0, 1 << 30);
  final unit = _unitFor(badge, remaining);
  return '${_formatNumber(remaining)} $unit';
}

String _unitFor(Badge badge, int value) {
  final plural = value == 1 ? '' : 's';
  if (badge.category == BadgeCategory.streak) return 'day$plural';
  if (badge.category == BadgeCategory.timedMastery || badge.metricLooksTimed) {
    return 'minute$plural';
  }
  if (badge.iconName == 'sprawl') return 'sprawl$plural';
  if (badge.iconName == 'overtime') return 'overtime workout$plural';
  if (badge.iconName == 'fake') return 'fake$plural';
  if (badge.iconName == 'down_block') return 'down block$plural';
  if (badge.iconName == 'circle') return 'circle callout$plural';
  if (badge.iconName == 'snap_down') return 'snap down$plural';
  if (badge.iconName == 'level_change') return 'level change$plural';
  if (badge.category == BadgeCategory.grind) return 'workout$plural';
  return 'rep$plural';
}

extension on Badge {
  bool get metricLooksTimed =>
      iconName == 'timer' ||
      iconName == 'stance' ||
      iconName == 'hand_fight' ||
      iconName == 'high_knees' ||
      iconName == 'foot_fire';
}

IconData _badgeIcon(String iconName) {
  switch (iconName) {
    case 'shot':
      return Icons.sports_mma;
    case 'sprawl':
      return Icons.keyboard_double_arrow_down;
    case 'stance':
      return Icons.accessibility_new;
    case 'fake':
      return Icons.bolt;
    case 'down_block':
      return Icons.shield;
    case 'circle':
      return Icons.rotate_right;
    case 'snap_down':
      return Icons.pan_tool_alt;
    case 'hand_fight':
      return Icons.back_hand;
    case 'level_change':
      return Icons.swap_vert;
    case 'high_knees':
      return Icons.directions_run;
    case 'foot_fire':
      return Icons.local_fire_department;
    case 'streak':
      return Icons.local_fire_department;
    case 'grind':
      return Icons.fitness_center;
    case 'timer':
      return Icons.timer;
    case 'difficulty':
      return Icons.speed;
    case 'combo':
      return Icons.hub;
    case 'season':
      return Icons.emoji_events;
    case 'overtime':
      return Icons.more_time;
    case 'premium':
      return Icons.workspace_premium;
    case 'secret':
      return Icons.lock;
    default:
      return Icons.military_tech;
  }
}

Color _tierColor(BadgeTier tier) {
  switch (tier) {
    case BadgeTier.bronze:
      return const Color(0xFFB66A32);
    case BadgeTier.silver:
      return const Color(0xFF87909A);
    case BadgeTier.gold:
      return AppBrandColors.gold;
    case BadgeTier.platinum:
      return AppBrandColors.blue;
    case BadgeTier.blackBelt:
      return AppBrandColors.black;
    case BadgeTier.legend:
      return AppBrandColors.red;
  }
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

String _formatDate(DateTime date) {
  return '${date.month}/${date.day}/${date.year}';
}
