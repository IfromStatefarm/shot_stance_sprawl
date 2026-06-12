import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

import 'app_theme.dart';
import 'services/branding_service.dart';
import 'features/drill/providers.dart';
import 'features/drill/recording_policy.dart';
import 'drill_summary_screen.dart';

class DrillRunnerScreen extends ConsumerStatefulWidget {
  const DrillRunnerScreen({super.key});
  @override
  ConsumerState<DrillRunnerScreen> createState() => _DrillRunnerScreenState();
}

class _DrillRunnerScreenState extends ConsumerState<DrillRunnerScreen> {
  static const int _countdownMs = 1000;
  int? _count;
  bool _showGo = false;
  bool _isProcessingVideo = false;
  bool _isEndingDrill = false;
  bool _summaryNavigationStarted = false;
  Timer? _countTimer;
  Future<_CountdownDrillStart>? _countdownPrep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCountdown());
  }

  void _runCountdown() {
    setState(() => _count = 5);
    _countdownPrep = _prepareDrillForCountdown();

    _countTimer =
        Timer.periodic(const Duration(milliseconds: _countdownMs), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }

      final currentCount = _count;
      if (currentCount != null && currentCount > 1) {
        setState(() => _count = currentCount - 1);
        return;
      }

      if (_count == 1) {
        t.cancel();
        final prep = await (_countdownPrep ?? _prepareDrillForCountdown());

        if (!mounted || _isEndingDrill) return;
        setState(() => _showGo = true);

        await ref.read(drillEngineProvider.notifier).start(
              config: prep.config,
              allCallouts: prep.callouts,
              isPro: prep.isPro,
              playStartWhistle: false,
            );

        if (!mounted || _isEndingDrill) return;
        setState(() => _count = null);

        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _showGo = false);
        });
      }
    });
  }

  Future<_CountdownDrillStart> _prepareDrillForCountdown() async {
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

    return _CountdownDrillStart(
      config: cfg,
      callouts: callouts,
      isPro: isPremium,
    );
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestEndDrill() async {
    if (_isProcessingVideo || _isEndingDrill || _summaryNavigationStarted) {
      return;
    }

    _countTimer?.cancel();
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

  // Added robust file lock checking by attempting to open the file in read mode
  Future<bool> _waitForFileReady(String path) async {
    final file = File(path);
    int attempts = 0;
    int lastSize = -1;
    int stableReads = 0;
    // Poll for up to 30 seconds to ensure Android finishes writing MP4 metadata.
    while (attempts < 60) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0 && len == lastSize) {
          stableReads++;
        } else {
          stableReads = 0;
        }

        // Ensure size is > 0 and has stopped growing across consecutive checks.
        if (stableReads >= 2) {
          try {
            // Attempt to open the file; if it fails, it's still locked by the camera OS
            final raf = await file.open(mode: FileMode.read);
            await raf.close();
            return true;
          } catch (e) {
            debugPrint("File still locked by camera, waiting... $e");
          }
        }
        lastSize = len; // Track size to ensure write completion
      }
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }
    debugPrint("Video file was not ready for branding after 30s: $path");
    return false;
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
                  ? '10-minute Pro video limit reached.'
                  : '60-second Free video limit reached. Upgrading unlocks 10 minutes!'),
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
              // Removed arbitrary delay. Rely on enhanced polling to detect file release.
              final isReady = await _waitForFileReady(finalPath!);

              if (!mounted) return;

              if (isReady) {
                final brandedPath = await BrandingService().applyBranding(
                  inputVideoPath: finalPath!,
                  assetLogoPath: 'assets/images/watermark logo transparent.png',
                  isPremium: isPremium,
                );

                if (!mounted) return;

                finalPath =
                    brandedPath; // If branding failed on Free, this is safely null now
              } else {
                finalPath = null;
              }
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

    final state = ref.watch(drillEngineProvider);
    final cfg = ref.watch(drillConfigProvider);

    Duration remaining = state.total - state.elapsed;
    if (remaining.isNegative) remaining = Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drill Runner'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              (_isProcessingVideo || _isEndingDrill) ? null : _requestEndDrill,
        ),
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isProcessingVideo,
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _TimerCard(remaining: remaining, total: state.total),
                      const SizedBox(height: 8),
                      if (state.isRecording)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _BlinkingDot(),
                              const SizedBox(width: 8),
                              Text(
                                "RECORDING",
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      if (state.lastCallout != null)
                        _InfoTile(
                          label: 'Last Callout',
                          value: state.lastCallout!.name,
                          icon: Icons.campaign,
                        ),
                      _InfoTile(
                        label: 'Difficulty',
                        value: _difficultyLabel(
                          cfg.minIntervalSeconds,
                          cfg.maxIntervalSeconds,
                        ),
                        icon: Icons.av_timer,
                      ),
                      if (state.holdRemaining != null)
                        _InfoTile(
                          label: 'Hold Remaining',
                          value: _fmt(state.holdRemaining!),
                          icon: Icons.schedule,
                        ),
                      if (cfg.videoEnabled && state.cameraInitialized)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              color: Colors.black,
                              height: 300,
                              width: double.infinity,
                              child: Builder(
                                builder: (context) {
                                  final controller = ref
                                      .read(drillEngineProvider.notifier)
                                      .cameraController;
                                  if (controller == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return CameraPreview(controller);
                                },
                              ),
                            ),
                          ),
                        )
                      else if (cfg.videoEnabled)
                        const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()))
                      else
                        const SizedBox(height: 50),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _isProcessingVideo
                                  ? null
                                  : (state.paused
                                      ? () async {
                                          final callouts = await ref.read(
                                              calloutsForActivePackProvider
                                                  .future);
                                          ref
                                              .read(
                                                  drillEngineProvider.notifier)
                                              .resume(
                                                config: cfg,
                                                allCallouts: callouts,
                                              );
                                        }
                                      : () => ref
                                          .read(drillEngineProvider.notifier)
                                          .pause()),
                              icon: Icon(state.paused
                                  ? Icons.play_arrow
                                  : Icons.pause),
                              label: Text(state.paused ? 'Resume' : 'Pause'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (_isProcessingVideo || _isEndingDrill)
                                  ? null
                                  : _requestEndDrill,
                              icon: const Icon(Icons.stop),
                              label: const Text('End Drill'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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

class _CountdownDrillStart {
  final DrillConfig config;
  final List<Callout> callouts;
  final bool isPro;

  const _CountdownDrillStart({
    required this.config,
    required this.callouts,
    required this.isPro,
  });
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

class _TimerCard extends StatelessWidget {
  final Duration remaining;
  final Duration total;
  const _TimerCard({required this.remaining, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total.inMilliseconds == 0
        ? 0.0
        : (1.0 - (remaining.inMilliseconds / total.inMilliseconds))
            .clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: pct,
              borderRadius: BorderRadius.circular(4),
              minHeight: 8,
            ),
            const SizedBox(height: 16),
            Text(
              _clock(remaining),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: [const FontFeature.tabularFigures()]),
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

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _controller,
        child: const Icon(Icons.circle, color: Colors.red, size: 14));
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoTile(
      {required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      trailing: Text(value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
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
                    : "Upgrade to Pro for faster processing.",
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
