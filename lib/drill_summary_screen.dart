import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';
import 'features/badges/badge_models.dart';
import 'features/badges/presentation/badge_widgets.dart';
import 'features/drill/presentation/drill_runner_screen.dart';
import 'features/drill/providers.dart';
import 'features/recordings/saved_recordings_provider.dart';

class DrillSummaryScreen extends ConsumerStatefulWidget {
  final Duration totalTime;
  final int calloutsCompleted;
  final String? videoPath;

  const DrillSummaryScreen({
    super.key,
    required this.totalTime,
    required this.calloutsCompleted,
    this.videoPath,
  });

  @override
  ConsumerState<DrillSummaryScreen> createState() => _DrillSummaryScreenState();
}

class _DrillSummaryScreenState extends ConsumerState<DrillSummaryScreen>
    with SingleTickerProviderStateMixin {
  static const _galleryAlbumName = 'Snap & Go Review';

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  var _localRecordingSaveQueued = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _calculateCalories(
      {required double weightLbs,
      required Duration duration,
      required double intensityMet}) {
    if (weightLbs <= 0) return 0.0;
    final double weightKg = weightLbs * 0.453592;
    final double durationHours = duration.inSeconds / 3600.0;
    return intensityMet * weightKg * durationHours;
  }

  Future<void> _saveVideoToGallery(
    BuildContext context,
    String? path,
    String lang,
    UserProfile user,
    bool isPro,
  ) async {
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(lang == 'es' ? 'Video no encontrado' : 'Video not found')),
      );
      return;
    }

    File? namedVideo;
    try {
      namedVideo = await _copyVideoWithGalleryName(
        path,
        user,
        widget.calloutsCompleted,
      );
      await Gal.putVideo(namedVideo.path, album: _galleryAlbumName);
      if (isPro) {
        await ref
            .read(badgeProgressProvider.notifier)
            .recordPremiumRecordingSaved();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(lang == 'es'
                ? 'Video guardado en $_galleryAlbumName'
                : 'Video saved to $_galleryAlbumName'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Gallery Save Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  lang == 'es' ? 'Error al guardar' : 'Error saving video')),
        );
      }
    } finally {
      try {
        if (namedVideo != null && await namedVideo.exists()) {
          await namedVideo.delete();
        }
      } catch (e) {
        debugPrint("Temporary Gallery Copy Cleanup Error: $e");
      }
    }
  }

  Future<File> _copyVideoWithGalleryName(
    String sourcePath,
    UserProfile user,
    int calloutsCompleted,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}gallery_exports',
    );
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final fileName = _galleryVideoFileName(
      user,
      calloutsCompleted,
      DateTime.now(),
    );
    final destination = File(
      '${exportDir.path}${Platform.pathSeparator}$fileName',
    );
    if (await destination.exists()) {
      await destination.delete();
    }

    return File(sourcePath).copy(destination.path);
  }

  String _galleryVideoFileName(
    UserProfile user,
    int calloutsCompleted,
    DateTime savedAt,
  ) {
    return SavedWorkoutVideoFileNames.fileName(
      userName: user.teamName,
      calloutsCompleted: calloutsCompleted,
      savedAt: savedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProfileProvider);
    final config = ref.watch(drillConfigProvider);
    final lang = ref.watch(languageProvider);
    final isPro = ref.watch(isProProvider);
    final nextChases = ref.watch(homeBadgeChasesProvider);

    final burned = _calculateCalories(
      weightLbs: user.weightLbs,
      duration: widget.totalTime,
      intensityMet: config.metValue,
    );

    final effectiveVideoPath = widget.videoPath;
    if (effectiveVideoPath != null && File(effectiveVideoPath).existsSync()) {
      _queueLocalRecordingSave(effectiveVideoPath);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildHeader(lang, user),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildStatsRow(lang),
                      const SizedBox(height: 18),

                      WorkoutBadgeSummary(isEs: lang == 'es'),

                      if (nextChases.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _NextChaseCard(
                          badge: nextChases.first,
                          calloutsCompleted: widget.calloutsCompleted,
                          lang: lang,
                        ),
                      ],

                      const SizedBox(height: 30),

                      _buildCaloriesCard(burned, lang),

                      const SizedBox(height: 30),

                      // FIX: Safe state protection if branding failed or was locked
                      if (effectiveVideoPath != null &&
                          File(effectiveVideoPath).existsSync())
                        _buildVideoCard(
                          context,
                          effectiveVideoPath,
                          lang,
                          user,
                          isPro,
                        )
                      else if (!isPro && config.videoEnabled)
                        _buildFailedBrandingCard(lang)
                    ],
                  ),
                ),
              ),
              _buildFooterButtons(context, lang),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String lang, UserProfile user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey[300],
          backgroundImage: user.profileImageUrl != null
              ? FileImage(File(user.profileImageUrl!))
              : null,
          child: user.profileImageUrl == null
              ? const Icon(Icons.person, size: 50)
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          user.teamName ?? (lang == 'es' ? 'Luchador' : 'Wrestler'),
          style:
              const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        Text(
          lang == 'es' ? 'DRILL COMPLETADO!' : 'DRILL COMPLETE!',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: Theme.of(context).primaryColor,
              ),
        ),
      ],
    );
  }

  void _queueLocalRecordingSave(String path) {
    if (_localRecordingSaveQueued) return;
    _localRecordingSaveQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(savedRecordingsProvider.notifier).saveWorkoutVideo(
              sourcePath: path,
              duration: widget.totalTime,
              calloutsCompleted: widget.calloutsCompleted,
              userName: ref.read(userProfileProvider).teamName,
            ),
      );
    });
  }

  Widget _buildStatsRow(String lang) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem(widget.calloutsCompleted.toString(),
            lang == 'es' ? 'Comandos' : 'Callouts'),
        Container(width: 1, height: 40, color: Colors.grey[300]),
        _statItem(
            "${widget.totalTime.inMinutes}:${(widget.totalTime.inSeconds % 60).toString().padLeft(2, '0')}",
            lang == 'es' ? 'Tiempo' : 'Time'),
      ],
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildCaloriesCard(double burned, String lang) {
    return Card(
      elevation: 8,
      shadowColor: AppBrandColors.gold.withValues(alpha: 0.4),
      color: AppBrandColors.goldLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
        child: Column(
          children: [
            const Icon(Icons.local_fire_department_rounded,
                color: AppBrandColors.red, size: 48),
            const SizedBox(height: 8),
            Text(
              burned.toStringAsFixed(0),
              style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: AppBrandColors.red),
            ),
            Text(
              lang == 'es' ? 'CALORIAS QUEMADAS' : 'CALORIES BURNED',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppBrandColors.goldDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(
    BuildContext context,
    String path,
    String lang,
    UserProfile user,
    bool isPro,
  ) {
    final engineState = ref.watch(drillEngineProvider);
    final bool isProcessing = engineState.isRecording;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
              color: AppBrandColors.blueLight, shape: BoxShape.circle),
          child: const Icon(Icons.videocam, color: AppBrandColors.blue),
        ),
        title: Text(lang == 'es' ? 'Video de review' : 'Review Video'),
        subtitle: Text(lang == 'es' ? 'Listo para guardar' : 'Ready to save'),
        trailing: FilledButton.icon(
          onPressed: isProcessing
              ? null
              : () => _saveVideoToGallery(
                    context,
                    path,
                    lang,
                    user,
                    isPro,
                  ),
          icon: isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download),
          label: Text(lang == 'es' ? 'Guardar' : 'Save'),
        ),
      ),
    );
  }

  // FIX: Custom fallback card for Free-tier users who triggered a watermark native failure
  Widget _buildFailedBrandingCard(String lang) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.red[50],
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.error_outline, color: Colors.red),
        ),
        title: Text(
            lang == 'es'
                ? 'Error al Procesar Video'
                : 'Video Processing Failed',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red)),
        subtitle: Text(lang == 'es'
            ? 'No se pudo aplicar la marca de agua obligatoria.'
            : 'Mandatory watermark could not be applied.'),
      ),
    );
  }

  Widget _buildFooterButtons(BuildContext context, String lang) {
    final preset = defaultOvertimeWorkoutPreset;
    final isEs = lang == 'es';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _startOvertime(context),
            icon: const Icon(Icons.more_time),
            label: Text(
              isEs
                  ? 'Ir a Overtime: ${preset.title(isEs: true)}'
                  : 'Go Overtime: ${preset.title(isEs: false)}',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AppBrandColors.red,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isEs
                ? '3 minutos. Dificultad 9. Un periodo mas.'
                : '3 minutes. Difficulty 9. One more period.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: Theme.of(context).primaryColor),
            ),
            child: Text(
              lang == 'es' ? 'VOLVER AL INICIO' : 'BACK TO HOME',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _startOvertime(BuildContext context) {
    final preset = defaultOvertimeWorkoutPreset;
    final difficulty = _intervalForDifficulty(preset.recommendedDifficulty);
    final notifier = ref.read(drillConfigProvider.notifier);
    final shouldDisableFreeRecording =
        !ref.read(isProProvider) && ref.read(drillConfigProvider).videoEnabled;

    notifier.applyWorkoutPreset(
      preset,
      totalDurationSeconds: preset.recommendedDurationSeconds,
      minIntervalSeconds: difficulty.$1,
      maxIntervalSeconds: difficulty.$2,
      videoEnabled: shouldDisableFreeRecording ? false : null,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DrillRunnerScreen()),
    );
  }
}

class _NextChaseCard extends StatelessWidget {
  final Badge badge;
  final int calloutsCompleted;
  final String lang;

  const _NextChaseCard({
    required this.badge,
    required this.calloutsCompleted,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final isEs = lang == 'es';
    final remaining = _badgeRemaining(badge);
    final unit = _badgeUnit(badge);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppBrandColors.gold.withValues(alpha: 0.4)),
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
                  isEs ? 'Siguiente persecucion' : 'Next Chase',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppBrandColors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isEs
                ? 'Completaste $calloutsCompleted comandos. Faltan $remaining $unit para ${badge.displayTitle}.'
                : 'You completed $calloutsCompleted callouts. $remaining $unit to ${badge.displayTitle}.',
            style: TextStyle(
              color: AppBrandColors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: badge.completionRatio,
              minHeight: 8,
              backgroundColor: AppBrandColors.white.withValues(alpha: 0.16),
              valueColor: const AlwaysStoppedAnimation(AppBrandColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

(double, double) _intervalForDifficulty(int difficulty) {
  if (difficulty <= 3) return (3.0, 5.0);
  if (difficulty <= 6) return (2.0, 4.0);
  if (difficulty <= 8) return (1.0, 2.0);
  return (0.5, 1.5);
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
  if (badge.category == BadgeCategory.flex) return 'bonus workout$plural';
  if (badge.category == BadgeCategory.combo) return 'session$plural';
  return 'rep$plural';
}
