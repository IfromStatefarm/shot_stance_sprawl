import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shot_stance_sprawl/features/drill/providers.dart';
import 'package:shot_stance_sprawl/features/drill/recording_policy.dart';
import 'package:shot_stance_sprawl/drill_runner.dart';
import 'app_theme.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          height: 1,
        );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          style: style,
          children: const [
            TextSpan(
              text: 'Snap & Go ',
              style: TextStyle(color: AppBrandColors.red),
            ),
            TextSpan(
              text: 'Shadow Wrestling Coach',
              style: TextStyle(color: AppBrandColors.black),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _difficultyValue = 1.0;
  bool _showFreeVideoDurationHint = false;
  final bool _legacyFreeVideoLimitMessageEnabled = false;
  DateTime? _lastFreeVideoDurationToastAt;
  Timer? _freeVideoDurationHintTimer;

  final List<(String, double, double)> _difficultyLevels = [
    ('Easy', 3.0, 5.0),
    ('Medium', 2.0, 4.0),
    ('Hard', 1.0, 2.0),
    ('Dan Gable', 0.5, 1.5),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(drillConfigProvider);
      int index = 1;
      for (int i = 0; i < _difficultyLevels.length; i++) {
        if ((config.minIntervalSeconds - _difficultyLevels[i].$2).abs() < 0.1) {
          index = i;
          break;
        }
      }
      setState(() {
        _difficultyValue = index.toDouble();
      });
    });
  }

  void _updateDifficulty(double value) {
    setState(() => _difficultyValue = value);
    final index = value.round();
    final level = _difficultyLevels[index];
    ref.read(drillConfigProvider.notifier).setIntervalRange(
          minSeconds: level.$2,
          maxSeconds: level.$3,
        );
  }

  void _showFadingToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 100,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: _FadeToast(message: message),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  void _showFreeVideoDurationLockMessage(
    BuildContext context, {
    required bool isEs,
  }) {
    final now = DateTime.now();
    final lastShown = _lastFreeVideoDurationToastAt;
    if (lastShown != null &&
        now.difference(lastShown) < const Duration(milliseconds: 1200)) {
      return;
    }

    _lastFreeVideoDurationToastAt = now;
    _showFadingToast(
      context,
      isEs
          ? 'Actualiza a Pro para videos mas largos o desactiva grabacion para drills mas largos'
          : 'Upgrade to Pro for longer videos or toggle recording off for longer drills',
    );

    setState(() => _showFreeVideoDurationHint = true);
    _freeVideoDurationHintTimer?.cancel();
    _freeVideoDurationHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showFreeVideoDurationHint = false);
      }
    });
  }

  void _showRecordingSheet(
    BuildContext context,
    String id,
    String name, {
    String? initialAudioPath,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RecordingSheetContent(
        calloutId: id,
        calloutName: name,
        initialAudioPath: initialAudioPath,
      ),
    );
  }

  @override
  void dispose() {
    _freeVideoDurationHintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(drillConfigProvider);
    final engine = ref.watch(drillEngineProvider);
    final calloutsAsync = ref.watch(calloutsProvider);
    final lang = ref.watch(languageProvider);
    final notifier = ref.read(drillConfigProvider.notifier);
    final isPro = ref.watch(isProProvider);

    final isEs = lang == 'es';
    final isFreeRecordingLocked = config.videoEnabled && !isPro;
    final selectedDurationMinutes =
        isFreeRecordingLocked ? 1 : (config.totalDurationSeconds / 60).round();
    final durationSliderMaxMinutes = config.videoEnabled && isPro ? 10 : 15;
    final durationSliderValue = isFreeRecordingLocked
        ? 1.0
        : selectedDurationMinutes.clamp(1, durationSliderMaxMinutes).toDouble();
    final showFreeVideoDurationHint =
        isFreeRecordingLocked && _showFreeVideoDurationHint;

    return Scaffold(
      appBar: AppBar(
        title: const _BrandTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
              children: [
                Text(
                  isEs ? 'Comandos' : 'Callouts',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                calloutsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (list) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final c = list[index];
                      return _CalloutTile(
                        callout: c,
                        enabled: config.enabledCalloutIds.contains(c.id),
                        onChanged: (v) =>
                            notifier.toggleCallout(c.id, enabled: v),
                        onRecordTapped: () => _showRecordingSheet(
                          context,
                          c.id,
                          isEs ? c.nameEs : c.nameEn,
                          initialAudioPath: c.audioUrl,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.18,
            minChildSize: 0.18,
            maxChildSize: 0.65,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, -5),
                    ),
                  ],
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: () {
                              // BUG FIX: Prevent Silent Drill Start
                              if (config.enabledCalloutIds.isEmpty) {
                                _showFadingToast(
                                    context,
                                    isEs
                                        ? 'Selecciona al menos un comando'
                                        : 'Select at least one callout');
                                return;
                              }

                              if (engine.running) {
                                ref.read(drillEngineProvider.notifier).stop();
                              } else {
                                if (calloutsAsync.isLoading) return;
                                if (calloutsAsync.hasError) {
                                  _showFadingToast(
                                      context,
                                      isEs
                                          ? 'Error de comandos'
                                          : 'Callouts unavailable');
                                  return;
                                }

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const DrillRunnerScreen()),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  engine.running ? Colors.red : Colors.green,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: Icon(
                                engine.running ? Icons.stop : Icons.play_arrow,
                                size: 32),
                            label: Text(
                              engine.running
                                  ? (isEs ? 'DETENER' : 'STOP')
                                  : (isEs ? 'INICIAR' : 'START'),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(isEs ? 'GRABAR VIDEO' : 'RECORD VIDEO',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey)),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () async {
                                final enableVideo =
                                    !ref.read(drillConfigProvider).videoEnabled;
                                notifier.setVideoEnabled(enableVideo);

                                final drillEngine =
                                    ref.read(drillEngineProvider.notifier);
                                if (enableVideo) {
                                  if (!isPro) {
                                    _showFreeVideoDurationLockMessage(
                                      context,
                                      isEs: isEs,
                                    );
                                  }
                                  if (_legacyFreeVideoLimitMessageEnabled &&
                                      !isPro) {
                                    if (ref
                                            .read(drillConfigProvider)
                                            .totalDurationSeconds >
                                        RecordingPolicy
                                            .freeRecordingLimitSeconds) {
                                      setState(() {
                                        _showFreeVideoDurationHint = true;
                                      });
                                    }
                                    _showFadingToast(
                                        context,
                                        isEs
                                            ? 'Límite de 60s'
                                            : 'Free limit: 60s');
                                  }
                                  await drillEngine.preloadCamera();
                                } else {
                                  setState(() {
                                    _showFreeVideoDurationHint = false;
                                  });
                                  await drillEngine.disposeCamera();
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: 48,
                                width: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: config.videoEnabled
                                      ? Colors.red
                                      : Colors.grey[300],
                                  boxShadow: config.videoEnabled
                                      ? [
                                          BoxShadow(
                                              color:
                                                  Colors.red.withValues(alpha: 0.5),
                                              blurRadius: 10,
                                              spreadRadius: 2)
                                        ]
                                      : [],
                                ),
                                child: Icon(
                                  config.videoEnabled
                                      ? Icons.videocam
                                      : Icons.videocam_off,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.timer,
                                size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(isEs ? 'Duración:' : 'Duration:',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              '${durationSliderValue.round()} min',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        if (showFreeVideoDurationHint)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 28),
                                Expanded(
                                  child: Text(
                                    'Upgrade to Pro for longer videos or toggle recording for longer drills',
                                    style: TextStyle(
                                      color: AppBrandColors.goldDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Slider(
                          value: durationSliderValue,
                          min: 1,
                          max: durationSliderMaxMinutes.toDouble(),
                          divisions: durationSliderMaxMinutes - 1,
                          label:
                              '${durationSliderValue.round().toString()} min',
                          onChangeStart: (_) {
                            if (isFreeRecordingLocked) {
                              _showFreeVideoDurationLockMessage(
                                context,
                                isEs: isEs,
                              );
                            }
                          },
                          onChanged: (val) {
                            if (isFreeRecordingLocked) {
                              _showFreeVideoDurationLockMessage(
                                context,
                                isEs: isEs,
                              );
                              return;
                            }

                            final requestedSeconds = (val * 60).round();
                            notifier.setTotalDurationSeconds(requestedSeconds);
                            if (_showFreeVideoDurationHint) {
                              setState(() {
                                _showFreeVideoDurationHint = false;
                              });
                            }
                          },
                        ),
                        Row(
                          children: [
                            const Icon(Icons.speed,
                                size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(isEs ? 'Dificultad:' : 'Difficulty:',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              _difficultyLevels[_difficultyValue.round()].$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppBrandColors.blue),
                            ),
                          ],
                        ),
                        Slider(
                          value: _difficultyValue,
                          min: 0,
                          max: 3,
                          divisions: 3,
                          onChanged: _updateDifficulty,
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FadeToast extends StatefulWidget {
  final String message;
  const _FadeToast({required this.message});

  @override
  State<_FadeToast> createState() => _FadeToastState();
}

class _FadeToastState extends State<_FadeToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          widget.message,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _CalloutTile extends ConsumerWidget {
  final Callout callout;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRecordTapped;

  const _CalloutTile({
    required this.callout,
    required this.enabled,
    required this.onChanged,
    required this.onRecordTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(drillConfigProvider);
    final savedAudioPath =
        config.customAudioPaths[callout.id] ?? callout.audioUrl;
    final hasRecording = savedAudioPath != null && savedAudioPath.isNotEmpty;
    final overrideMap = config.calloutOverrideDurations;
    final currentDuration =
        overrideMap[callout.id] ?? callout.defaultDurationSeconds;

    final isPro = ref.watch(isProProvider);
    final proPurchase = ref.watch(proPurchaseProvider);
    final lang = ref.watch(languageProvider);
    final displayName = lang == 'es' ? callout.nameEs : callout.nameEn;

    return Card(
      elevation: enabled ? 3 : 1,
      color: enabled
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: enabled
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => onChanged(!enabled),
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: enabled
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (enabled)
                    Text("ON",
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  if (isPro) {
                    onRecordTapped();
                  } else if (proPurchase.canBuy) {
                    unawaited(ref.read(proPurchaseProvider.notifier).buyPro());
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          proPurchase.errorMessage ??
                              'Snap&Go Pro is loading. Try again in a moment.',
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        Theme.of(context).canvasColor.withValues(alpha: 0.5),
                  ),
                  child: Icon(
                    !isPro && !callout.isCustom
                        ? Icons.lock
                        : (hasRecording ? Icons.mic : Icons.mic_none),
                    size: 16,
                    color: !isPro
                        ? AppBrandColors.gold
                        : (hasRecording ? AppBrandColors.blue : Colors.grey),
                  ),
                ),
              ),
            ),
            if (callout.type == 'Duration')
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    if (!enabled) return;
                    _showDurationPicker(
                        context, ref, callout.id, currentDuration);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: enabled
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${currentDuration}s",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: enabled ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDurationPicker(
      BuildContext context, WidgetRef ref, String id, int current) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          child: Column(
            children: [
              const Text("Select Duration",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                // BUG FIX: Added the 45s interval that was requested!
                children: [5, 15, 30, 45, 60].map((val) {
                  final isSelected = val == current;
                  return ChoiceChip(
                    label: Text("${val}s"),
                    selected: isSelected,
                    onSelected: (_) {
                      ref
                          .read(drillConfigProvider.notifier)
                          .setCalloutDuration(id, val);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordingSheetContent extends ConsumerStatefulWidget {
  final String calloutId;
  final String calloutName;
  final String? initialAudioPath;

  const _RecordingSheetContent({
    required this.calloutId,
    required this.calloutName,
    this.initialAudioPath,
  });

  @override
  ConsumerState<_RecordingSheetContent> createState() =>
      _RecordingSheetContentState();
}

class _RecordingSheetContentState
    extends ConsumerState<_RecordingSheetContent> {
  final recorder = AudioRecorder();
  final audioPlayer = AudioPlayer();
  bool isRecording = false;
  String? recordedPath;

  @override
  void initState() {
    super.initState();
    unawaited(audioPlayer.setPlayerMode(PlayerMode.mediaPlayer));
    unawaited(audioPlayer.setReleaseMode(ReleaseMode.stop));
  }

  @override
  void dispose() {
    recorder.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/${widget.calloutId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const config = RecordConfig(encoder: AudioEncoder.aacLc);
      await recorder.start(config, path: path);

      setState(() => isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await recorder.stop();
    setState(() {
      isRecording = false;
      recordedPath = path;
    });

    if (path != null) {
      ref
          .read(drillConfigProvider.notifier)
          .updateCalloutAudio(widget.calloutId, path);
    }
  }

  Future<void> _playPreview(String path) async {
    try {
      await audioPlayer.stop();
      await audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('Could not play custom callout preview: $e');
    }
  }

  Future<void> _deleteOverrideRecording(String path) async {
    await audioPlayer.stop();
    ref.read(drillConfigProvider.notifier).removeCalloutAudio(widget.calloutId);

    setState(() {
      recordedPath = null;
      isRecording = false;
    });

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Could not delete custom callout audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(drillConfigProvider);
    final overridePath = config.customAudioPaths[widget.calloutId];
    final resettablePath = recordedPath ?? overridePath;
    final activePath = resettablePath ?? widget.initialAudioPath;
    final lang = ref.watch(languageProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text(
            isRecording
                ? (lang == 'es' ? 'Grabando...' : 'Recording...')
                : (lang == 'es'
                    ? 'Voz: ${widget.calloutName}'
                    : 'Voice: ${widget.calloutName}'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  GestureDetector(
                    onTap: isRecording ? _stopRecording : _startRecording,
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor:
                          isRecording ? Colors.red : Colors.redAccent,
                      child: Icon(isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(isRecording ? "STOP" : "REC"),
                ],
              ),
              if (activePath != null && !isRecording)
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _playPreview(activePath),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: AppBrandColors.blue,
                        child: Icon(Icons.play_arrow,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text("PLAY"),
                  ],
                ),
              if (resettablePath != null &&
                  resettablePath != widget.initialAudioPath &&
                  !isRecording)
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _deleteOverrideRecording(resettablePath),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: AppBrandColors.goldDark,
                        child: Icon(Icons.delete_outline,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(lang == 'es' ? "BORRAR" : "DELETE"),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lang == 'es' ? 'Listo' : 'Done'),
          ),
        ],
      ),
    );
  }
}
