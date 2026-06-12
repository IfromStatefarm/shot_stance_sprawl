import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app_theme.dart';
import '../../workout_presets.dart';

class WorkoutPresetSheet extends StatefulWidget {
  final bool isEs;
  final WorkoutPreset dailyMission;
  final void Function(WorkoutPreset preset, {required bool startNow})
      onPresetSelected;

  const WorkoutPresetSheet({
    super.key,
    required this.isEs,
    required this.dailyMission,
    required this.onPresetSelected,
  });

  @override
  State<WorkoutPresetSheet> createState() => _WorkoutPresetSheetState();
}

class _WorkoutPresetSheetState extends State<WorkoutPresetSheet> {
  WorkoutPresetCategory _selectedCategory = WorkoutPresetCategory.quick;

  void _selectPreset(WorkoutPreset preset, {required bool startNow}) {
    Navigator.of(context).pop();
    widget.onPresetSelected(preset, startNow: startNow);
  }

  Future<void> _sharePreset(WorkoutPreset preset) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(
      ShareParams(
        text: coachAssignmentText(preset, isEs: widget.isEs),
        subject: 'Snap & Go Coach Assignment',
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    final visiblePresets = workoutPresetsForCategory(_selectedCategory);

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;

          return SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                _WorkoutSheetHeader(
                  isEs: isEs,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                  child: _DailyMissionPresetCard(
                    preset: widget.dailyMission,
                    isEs: isEs,
                    onApply: () =>
                        _selectPreset(widget.dailyMission, startNow: false),
                    onStart: () =>
                        _selectPreset(widget.dailyMission, startNow: true),
                    onShare: () => unawaited(_sharePreset(widget.dailyMission)),
                  ),
                ),
                const SizedBox(height: 14),
                _SectionHeader(
                  title: isEs ? 'Favoritos' : 'Featured',
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth =
                        (constraints.maxWidth * 0.51).clamp(198.0, 232.0);
                    final cardHeight = (cardWidth * 0.63).clamp(136.0, 150.0);

                    return SizedBox(
                      height: cardHeight.toDouble(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final preset = featuredWorkoutPresets[index];
                          return _FeaturedPresetCard(
                            width: cardWidth.toDouble(),
                            preset: preset,
                            isEs: isEs,
                            onTap: () => _selectPreset(preset, startNow: false),
                            onStart: () =>
                                _selectPreset(preset, startNow: true),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemCount: featuredWorkoutPresets.length,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _SectionHeader(
                  title: isEs ? 'Explorar' : 'Browse',
                  subtitle: isEs
                      ? '${visiblePresets.length} workouts'
                      : '${visiblePresets.length} workouts',
                ),
                const SizedBox(height: 8),
                _CategorySelector(
                  isEs: isEs,
                  selected: _selectedCategory,
                  onSelected: (category) {
                    setState(() => _selectedCategory = category);
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                    itemBuilder: (context, index) {
                      final preset = visiblePresets[index];
                      return _WorkoutPresetCard(
                        preset: preset,
                        isEs: isEs,
                        onApply: () => _selectPreset(preset, startNow: false),
                        onStart: () => _selectPreset(preset, startNow: true),
                        onShare: () => unawaited(_sharePreset(preset)),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: visiblePresets.length,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _presetSummary(WorkoutPreset preset, {required bool isEs}) {
  final calls = isEs ? 'cmd' : 'calls';
  return '${preset.durationLabel(isEs: isEs)} / D ${preset.difficultyLabel(isEs: isEs)} / ${preset.calloutIds.length} $calls';
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        margin: const EdgeInsets.only(top: 9, bottom: 8),
        decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _WorkoutSheetHeader extends StatelessWidget {
  final bool isEs;
  final VoidCallback onClose;

  const _WorkoutSheetHeader({
    required this.isEs,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isEs ? 'Workouts' : 'Workouts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          IconButton(
            tooltip: isEs ? 'Cerrar' : 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyMissionPresetCard extends StatelessWidget {
  final WorkoutPreset preset;
  final bool isEs;
  final VoidCallback onApply;
  final VoidCallback onStart;
  final VoidCallback onShare;

  const _DailyMissionPresetCard({
    required this.preset,
    required this.isEs,
    required this.onApply,
    required this.onStart,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppBrandColors.gold.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppBrandColors.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.flash_on,
                  color: AppBrandColors.black,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEs ? 'Mision de hoy' : "Today's mission",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppBrandColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.title(isEs: isEs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppBrandColors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _presetSummary(preset, isEs: isEs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppBrandColors.white.withValues(alpha: 0.64),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isEs ? 'Compartir assignment' : 'Share assignment',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share, size: 18),
                color: AppBrandColors.gold,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            preset.purpose(isEs: isEs),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppBrandColors.white.withValues(alpha: 0.76),
              fontWeight: FontWeight.w600,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(isEs ? 'Iniciar' : 'Start'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(38),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: AppBrandColors.red,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.tune),
                  label: Text(isEs ? 'Usar' : 'Use'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(38),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: AppBrandColors.gold,
                    side: const BorderSide(color: AppBrandColors.gold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturedPresetCard extends StatelessWidget {
  final double width;
  final WorkoutPreset preset;
  final bool isEs;
  final VoidCallback onTap;
  final VoidCallback onStart;

  const _FeaturedPresetCard({
    required this.width,
    required this.preset,
    required this.isEs,
    required this.onTap,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final scale = (width / 210).clamp(0.9, 1.08).toDouble();
    final playSize = (30 * scale).clamp(28.0, 32.0).toDouble();
    final padding = (12 * scale).clamp(10.0, 13.0).toDouble();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: AppBrandColors.redDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppBrandColors.red.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.title(isEs: isEs),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppBrandColors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15 * scale,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: 3 * scale),
                      Text(
                        preset.purpose(isEs: isEs),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppBrandColors.white.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                          fontSize: 12 * scale,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * scale),
                IconButton.filled(
                  constraints: BoxConstraints.tightFor(
                    width: playSize,
                    height: playSize,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onStart,
                  icon: Icon(Icons.play_arrow, size: 18 * scale),
                  style: IconButton.styleFrom(
                    backgroundColor: AppBrandColors.gold,
                    foregroundColor: AppBrandColors.black,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _presetSummary(preset, isEs: isEs),
                maxLines: 1,
                style: TextStyle(
                  color: AppBrandColors.white.withValues(alpha: 0.82),
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final bool isEs;
  final WorkoutPresetCategory selected;
  final ValueChanged<WorkoutPresetCategory> onSelected;

  const _CategorySelector({
    required this.isEs,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.filter_list, size: 18, color: AppBrandColors.red),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<WorkoutPresetCategory>(
                  value: selected,
                  isExpanded: true,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  borderRadius: BorderRadius.circular(8),
                  onChanged: (category) {
                    if (category != null) onSelected(category);
                  },
                  items: [
                    for (final category in WorkoutPresetCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(
                          category.label(isEs: isEs),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutPresetCard extends StatelessWidget {
  final WorkoutPreset preset;
  final bool isEs;
  final VoidCallback onApply;
  final VoidCallback onStart;
  final VoidCallback onShare;

  const _WorkoutPresetCard({
    required this.preset,
    required this.isEs,
    required this.onApply,
    required this.onStart,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: preset.featured
              ? AppBrandColors.gold.withValues(alpha: 0.68)
              : scheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: InkWell(
        onTap: onApply,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: preset.featured
                      ? AppBrandColors.goldLight
                      : AppBrandColors.blueLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  preset.featured ? Icons.star : Icons.fitness_center,
                  color: preset.featured
                      ? AppBrandColors.goldDark
                      : AppBrandColors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.title(isEs: isEs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.purpose(isEs: isEs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _presetSummary(preset, isEs: isEs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isEs ? 'Compartir assignment' : 'Share assignment',
                visualDensity: VisualDensity.compact,
                onPressed: onShare,
                icon: const Icon(Icons.ios_share),
                color: AppBrandColors.blue,
              ),
              IconButton.filled(
                tooltip: isEs ? 'Iniciar' : 'Start',
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 40),
                padding: EdgeInsets.zero,
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                style: IconButton.styleFrom(
                  backgroundColor: AppBrandColors.red,
                  foregroundColor: AppBrandColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
