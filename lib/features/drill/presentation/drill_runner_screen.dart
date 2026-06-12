import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

import '../../../app_theme.dart';
import '../../../drill_summary_screen.dart';
import '../application/drill_countdown_controller.dart';
import '../providers.dart';
import '../recording_policy.dart';
import '../services/video_finalization_service.dart';

class DrillRunnerScreen extends ConsumerStatefulWidget {
  const DrillRunnerScreen({super.key});
  @override
  ConsumerState<DrillRunnerScreen> createState() => _DrillRunnerScreenState();
}

class _DrillRunnerScreenState extends ConsumerState<DrillRunnerScreen> {
  static const _portraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];
  static const _runnerOrientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  int? _count;
  bool _showGo = false;
  bool _isProcessingVideo = false;
  bool _isEndingDrill = false;
  bool _summaryNavigationStarted = false;
  Timer? _orientationUnlockTimer;
  final _countdownController = DrillCountdownController();
  final _videoFinalizationService = VideoFinalizationService();

  @override
  void initState() {
    super.initState();
    _prepareRunnerOrientations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCountdown());
  }

  void _prepareRunnerOrientations() {
    unawaited(SystemChrome.setPreferredOrientations(_portraitOnly));
    _orientationUnlockTimer?.cancel();
    _orientationUnlockTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(SystemChrome.setPreferredOrientations(_runnerOrientations));
    });
  }

  void _runCountdown() {
    _countdownController.start(
      prepare: _prepareDrillForCountdown,
      shouldAbort: () => !mounted || _isEndingDrill,
      onCountChanged: (count) {
        if (mounted) setState(() => _count = count);
      },
      onShowGoChanged: (showGo) {
        if (mounted) setState(() => _showGo = showGo);
      },
      startDrill: (prep) {
        return ref.read(drillEngineProvider.notifier).start(
              config: prep.config,
              allCallouts: prep.callouts,
              isPro: prep.isPro,
              playStartWhistle: false,
            );
      },
    );
  }

  Future<CountdownDrillStart> _prepareDrillForCountdown() async {
    final isPremium = ref.read(isProProvider);
    final cfg = RecordingPolicy.effectiveConfig(
      config: ref.read(drillConfigProvider),
      isPro: isPremium,
    );
    final callouts = await ref.read(calloutsForActivePackProvider.future);

    if (mounted && !_isEndingDrill) {
      try {
        await ref.read(drillEngineProvider.notifier).warmUpForStart(
              config: cfg,
              allCallouts: callouts,
              isPro: isPremium,
            );
      } catch (e) {
        debugPrint('[drill] Countdown warm-up failed; start will retry: $e');
      }
    }

    return CountdownDrillStart(
      config: cfg,
      callouts: callouts,
      isPro: isPremium,
    );
  }

  @override
  void dispose() {
    _orientationUnlockTimer?.cancel();
    unawaited(SystemChrome.setPreferredOrientations(_portraitOnly));
    _countdownController.dispose();
    super.dispose();
  }

  Future<void> _requestEndDrill() async {
    if (_isProcessingVideo || _isEndingDrill || _summaryNavigationStarted) {
      return;
    }

    _countdownController.cancel();
    setState(() {
      _isEndingDrill = true;
      _count = null;
      _showGo = false;
    });

    await ref.read(drillEngineProvider.notifier).stop();
  }

  void _replaceWithSummary(DrillState state, String? videoPath) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DrillSummaryScreen(
          totalTime: state.elapsed,
          calloutsCompleted: state.calloutsCompleted,
          videoPath: videoPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(drillEngineProvider, (previous, next) async {
      if (!mounted) return;
      final isPremium = ref.read(isProProvider);

      if (previous?.isRecording == true &&
          next.isRecording == false &&
          !next.finished) {
        final limitSeconds =
            RecordingPolicy.recordingLimitSeconds(isPro: isPremium);
        if (next.elapsed.inSeconds >= limitSeconds) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isPremium
                  ? '10-minute Coach Mode video limit reached.'
                  : '60-second free video limit reached. Coach Mode unlocks 10 minutes!'),
              backgroundColor: AppBrandColors.goldDark,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      if (previous?.finished == false && next.finished == true) {
        if (_summaryNavigationStarted) return;
        _summaryNavigationStarted = true;

        String? finalPath = next.videoPath;

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;

          if (finalPath != null && finalPath!.isNotEmpty) {
            setState(() => _isProcessingVideo = true);

            try {
              final result = await _videoFinalizationService.finalizeVideo(
                inputVideoPath: finalPath,
                assetLogoPath: 'assets/images/watermark logo transparent.png',
                isPremium: isPremium,
              );
              if (!mounted) return;
              finalPath = result.videoPath;
            } catch (e) {
              debugPrint("Video processing critical error: $e");
              finalPath = null;
            } finally {
              if (mounted) {
                setState(() => _isProcessingVideo = false);

                _replaceWithSummary(next, finalPath);
              }
            }
          } else {
            _replaceWithSummary(next, null);
          }
        });
      }
    });

    final state = ref.watch(
      drillEngineProvider.select(
        (state) => (
          cameraInitialized: state.cameraInitialized,
          holdRemaining: state.holdRemaining,
          isRecording: state.isRecording,
          lastCallout: state.lastCallout,
          paused: state.paused,
        ),
      ),
    );
    final cfg = ref.watch(drillConfigProvider);
    final useLandscapeCameraLayout = cfg.videoEnabled &&
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      appBar: useLandscapeCameraLayout
          ? null
          : AppBar(
              title: const Text('Drill Runner'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: (_isProcessingVideo || _isEndingDrill)
                    ? null
                    : _requestEndDrill,
              ),
            ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isProcessingVideo,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (useLandscapeCameraLayout) {
                    return _LandscapeCameraView(
                      cameraInitialized: state.cameraInitialized,
                      isProcessingVideo: _isProcessingVideo,
                      isEndingDrill: _isEndingDrill,
                      paused: state.paused,
                      onPause: () =>
                          ref.read(drillEngineProvider.notifier).pause(),
                      onResume: () async {
                        final callouts = await ref
                            .read(calloutsForActivePackProvider.future);
                        ref.read(drillEngineProvider.notifier).resume(
                              config: cfg,
                              allCallouts: callouts,
                            );
                      },
                      onEnd: _requestEndDrill,
                    );
                  }

                  final compact = constraints.maxHeight < 640;
                  final previewHeight = cfg.videoEnabled
                      ? (constraints.maxHeight * (compact ? 0.25 : 0.32))
                          .clamp(138.0, compact ? 176.0 : 240.0)
                      : 0.0;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      compact ? 8 : 12,
                      16,
                      compact ? 10 : 14,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              children: [
                                _TimerCard(
                                  config: cfg,
                                  currentCallout: state.lastCallout?.name,
                                  holdRemaining: state.holdRemaining,
                                  isRecording: state.isRecording,
                                  compact: compact,
                                ),
                                if (cfg.videoEnabled) ...[
                                  SizedBox(height: compact ? 8 : 12),
                                  _CameraPanel(
                                    cameraInitialized: state.cameraInitialized,
                                    height: previewHeight,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        _RunnerControls(
                          isProcessingVideo: _isProcessingVideo,
                          isEndingDrill: _isEndingDrill,
                          paused: state.paused,
                          onPause: () =>
                              ref.read(drillEngineProvider.notifier).pause(),
                          onResume: () async {
                            final callouts = await ref
                                .read(calloutsForActivePackProvider.future);
                            ref.read(drillEngineProvider.notifier).resume(
                                  config: cfg,
                                  allCallouts: callouts,
                                );
                          },
                          onEnd: _requestEndDrill,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (_count != null || _showGo)
            Positioned.fill(
              child:
                  _CountdownOverlay(value: _showGo ? 'GO!' : '${_count ?? ''}'),
            ),
          if (_isProcessingVideo)
            const Positioned.fill(
              child: _VideoProcessingOverlay(),
            ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  static String _difficultyLabel(double minSeconds, double maxSeconds) {
    bool matches(double min, double max) {
      return (minSeconds - min).abs() < 0.1 && (maxSeconds - max).abs() < 0.1;
    }

    if (matches(3.0, 5.0)) return 'Easy mode';
    if (matches(2.0, 4.0)) return 'Medium mode';
    if (matches(1.0, 2.0)) return 'Hard mode';
    if (matches(0.5, 1.5)) return 'Dan Gable mode';
    return 'Custom mode';
  }
}

class _CountdownOverlay extends StatelessWidget {
  final String value;
  const _CountdownOverlay({required this.value});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (c, a) => ScaleTransition(
              scale: a, child: FadeTransition(opacity: a, child: c)),
          child: Text(
            value,
            key: ValueKey(value),
            style: const TextStyle(
              fontSize: 100,
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerCard extends ConsumerWidget {
  final DrillConfig config;
  final String? currentCallout;
  final Duration? holdRemaining;
  final bool isRecording;
  final bool compact;

  const _TimerCard({
    required this.config,
    required this.currentCallout,
    required this.holdRemaining,
    required this.isRecording,
    required this.compact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timer = ref.watch(
      drillEngineProvider.select(
        (state) => (
          elapsed: state.elapsed,
          total: state.total,
        ),
      ),
    );
    var remaining = timer.total - timer.elapsed;
    if (remaining.isNegative) remaining = Duration.zero;

    final pct = timer.total.inMilliseconds == 0
        ? 0.0
        : (1.0 - (remaining.inMilliseconds / timer.total.inMilliseconds))
            .clamp(0.0, 1.0);
    final callout = currentCallout?.trim().isNotEmpty == true
        ? currentCallout!.trim()
        : 'Ready';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _TimerStatusIcon(
                  icon: config.videoEnabled
                      ? (isRecording
                          ? Icons.fiber_manual_record
                          : Icons.videocam_outlined)
                      : Icons.videocam_off_outlined,
                  isActive: isRecording,
                  activeColor: Colors.red,
                  tooltip: isRecording
                      ? 'Recording'
                      : config.videoEnabled
                          ? 'Camera ready'
                          : 'Recording off',
                ),
                _TimerStatusIcon(
                  icon: Icons.fitness_center,
                  isActive: true,
                  activeColor: scheme.primary,
                  tooltip: 'Workout running',
                ),
                _TimerStatusPill(
                  icon: Icons.speed,
                  label: _DrillRunnerScreenState._difficultyLabel(
                    config.minIntervalSeconds,
                    config.maxIntervalSeconds,
                  ),
                ),
                if (holdRemaining != null)
                  _TimerStatusPill(
                    icon: Icons.hourglass_bottom,
                    label: _DrillRunnerScreenState._fmt(holdRemaining!),
                  ),
              ],
            ),
            SizedBox(height: compact ? 10 : 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                callout,
                key: ValueKey(callout),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: callout == 'Ready'
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                  fontSize: compact ? 38 : 46,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
            SizedBox(height: compact ? 8 : 10),
            Text(
              _clock(remaining),
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.primary,
                fontSize: compact ? 36 : 42,
                fontWeight: FontWeight.bold,
                fontFeatures: [const FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            LinearProgressIndicator(
              value: pct,
              borderRadius: BorderRadius.circular(4),
              minHeight: compact ? 7 : 8,
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _TimerStatusIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final String tooltip;

  const _TimerStatusIcon({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isActive ? activeColor : scheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isActive ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
    );
  }
}

class _TimerStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TimerStatusPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandscapeCameraView extends StatelessWidget {
  final bool cameraInitialized;
  final bool isProcessingVideo;
  final bool isEndingDrill;
  final bool paused;
  final VoidCallback onPause;
  final Future<void> Function() onResume;
  final VoidCallback onEnd;

  const _LandscapeCameraView({
    required this.cameraInitialized,
    required this.isProcessingVideo,
    required this.isEndingDrill,
    required this.paused,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final busy = isProcessingVideo || isEndingDrill;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: _CameraPreviewSurface(
              cameraInitialized: cameraInitialized,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              children: [
                _OverlayControlButton(
                  tooltip: paused ? 'Resume' : 'Pause',
                  icon: paused ? Icons.play_arrow : Icons.pause,
                  onPressed: busy
                      ? null
                      : paused
                          ? () => unawaited(onResume())
                          : onPause,
                ),
                const SizedBox(width: 10),
                _OverlayControlButton(
                  tooltip: 'Stop',
                  icon: Icons.stop,
                  isPrimary: true,
                  onPressed: busy ? null : onEnd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback? onPressed;

  const _OverlayControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isPrimary ? scheme.primary : Colors.black54;
    final foreground = isPrimary ? scheme.onPrimary : Colors.white;

    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: Colors.black26,
          disabledForegroundColor: Colors.white54,
          minimumSize: const Size.square(48),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _CameraPanel extends ConsumerWidget {
  final bool cameraInitialized;
  final double height;

  const _CameraPanel({
    required this.cameraInitialized,
    required this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.black,
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        child: _CameraPreviewSurface(
          cameraInitialized: cameraInitialized,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _CameraPreviewSurface extends ConsumerWidget {
  final bool cameraInitialized;
  final BoxFit fit;

  const _CameraPreviewSurface({
    required this.cameraInitialized,
    required this.fit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!cameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final controller = ref.read(drillEngineProvider.notifier).cameraController;
    if (controller == null) return const SizedBox.shrink();

    final preview = CameraPreview(controller);
    if (fit != BoxFit.cover) return Center(child: preview);

    final aspectRatio = controller.value.aspectRatio;
    const width = 1000.0;
    final height = width / (aspectRatio == 0 ? 1 : aspectRatio);

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: width,
            height: height,
            child: preview,
          ),
        ),
      ),
    );
  }
}

class _RunnerControls extends StatelessWidget {
  final bool isProcessingVideo;
  final bool isEndingDrill;
  final bool paused;
  final VoidCallback onPause;
  final Future<void> Function() onResume;
  final VoidCallback onEnd;

  const _RunnerControls({
    required this.isProcessingVideo,
    required this.isEndingDrill,
    required this.paused,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final busy = isProcessingVideo || isEndingDrill;
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
    );

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            style: buttonStyle,
            onPressed: busy
                ? null
                : paused
                    ? () async => await onResume()
                    : onPause,
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(paused ? 'Resume' : 'Pause'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: buttonStyle,
            onPressed: busy ? null : onEnd,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ),
      ],
    );
  }
}

// The  video processing overlay is a critical UX component that appears after the drill ends while the app finalizes the video file. It features a sleek loading animation and informative text to keep users engaged during this potentially lengthy process, especially on slower devices. The overlay also handles both Free and Pro user flows, providing tailored messaging based on the user's subscription status. By blocking interaction with the underlying UI, it prevents any accidental taps that could disrupt the processing workflow. Overall, this overlay transforms what could be a frustrating wait into a polished and reassuring experience for users as they await their drill summary video.
class _VideoProcessingOverlay extends ConsumerStatefulWidget {
  const _VideoProcessingOverlay();

  @override
  ConsumerState<_VideoProcessingOverlay> createState() =>
      _VideoProcessingOverlayState();
}

class _VideoProcessingOverlayState
    extends ConsumerState<_VideoProcessingOverlay> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.asset('assets/images/kkwloading_page.mp4')
          ..initialize().then((_) {
            _controller.setLooping(true);
            _controller.setVolume(0.0); // Keep processing silent
            _controller.play();
            setState(() => _initialized = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);

    return Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_initialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          Container(
              color:
                  Colors.black38), // Elegant translucent layer for legibility
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "Finalizing Video...",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isPro
                    ? "Processing raw high-quality file..."
                    : "Coach Mode skips watermark processing.",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
