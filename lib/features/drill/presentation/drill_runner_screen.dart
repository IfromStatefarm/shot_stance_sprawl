import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

import '../../../app_theme.dart';
import '../../../drill_summary_screen.dart';
import '../application/drill_countdown_controller.dart';
import '../application/drill_session_capture.dart';
import '../providers.dart';
import '../recording_policy.dart';
import '../services/video_finalization_service.dart';
import '../../onboarding/workout_reminder_notifications.dart';
import '../../social/social_providers.dart';

part 'runner/drill_runner_widgets.dart';

class DrillRunnerScreen extends ConsumerStatefulWidget {
  const DrillRunnerScreen({super.key, this.workoutShareId});

  final String? workoutShareId;
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
  DrillSessionCapture? _activeSession;

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
        final session = DrillSessionCapture.start(
          prep.config,
          workoutShareId: widget.workoutShareId,
        );
        _activeSession = session;
        if (session.workoutShareId != null) {
          unawaited(_markSharedWorkoutStarted(session.workoutShareId!));
        }
        return ref.read(drillEngineProvider.notifier).start(
              config: session.configSnapshot,
              allCallouts: prep.callouts,
              isPro: prep.isPro,
              playStartWhistle: false,
            );
      },
    );
  }

  Future<void> _markSharedWorkoutStarted(String shareId) async {
    try {
      await Future.wait([
        ref.read(socialRepositoryProvider).startWorkoutShare(shareId),
        ref.read(workoutReminderNotificationsProvider).cancelFriendWorkout(
              shareId,
            ),
      ]);
    } catch (error) {
      // The drill remains local-first. Summary retries this transition before
      // completing the share if Firebase was unavailable at the starting bell.
      debugPrint('[social] Could not mark shared workout started: $error');
    }
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
    if (_activeSession == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isEndingDrill = true;
      _count = null;
      _showGo = false;
    });

    await ref.read(drillEngineProvider.notifier).stop();
  }

  void _replaceWithSummary(DrillState state, String? videoPath) {
    if (!mounted) return;
    final session = _activeSession;
    if (session == null) {
      debugPrint(
        '[drill] Refusing summary navigation without a captured session.',
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DrillSummaryScreen(
          totalTime: state.elapsed,
          calloutsCompleted: state.calloutsCompleted,
          videoPath: videoPath,
          configSnapshot: session.configSnapshot,
          sessionId: session.sessionId,
          workoutShareId: session.workoutShareId,
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
    final configuredDrill = ref.watch(drillConfigProvider);
    final cfg = _activeSession?.configSnapshot ?? configuredDrill;
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
