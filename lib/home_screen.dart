import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shot_stance_sprawl/features/drill/drill.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/drill_presentation.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/settings_presentation.dart';

import 'app_theme.dart';
import 'settings_screen.dart';

part 'features/drill/presentation/home/home_train_widgets.dart';

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
  int _selectedTabIndex = 0;
  int _tabTransitionDirection = 1;
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

  void _changeTab(int index) {
    if (index == _selectedTabIndex) return;

    setState(() {
      _tabTransitionDirection = index > _selectedTabIndex ? 1 : -1;
      _selectedTabIndex = index;
    });
  }

  int _difficultyIndexForPreset(WorkoutPreset preset) {
    final difficulty = preset.recommendedDifficulty;
    if (difficulty <= 3) return 0;
    if (difficulty <= 6) return 1;
    if (difficulty <= 8) return 2;
    return 3;
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
          ? 'Activa Coach Mode para videos mas largos o desactiva grabacion para drills mas largos'
          : 'Unlock Coach Mode for longer videos or toggle recording off for longer drills',
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
      builder: (context) => HomeRecordingSheetContent(
        calloutId: id,
        calloutName: name,
        initialAudioPath: initialAudioPath,
      ),
    );
  }

  Future<void> _startConfiguredDrill({required bool isEs}) async {
    final config = ref.read(drillConfigProvider);
    if (config.enabledCalloutIds.isEmpty) {
      _showFadingToast(
        context,
        isEs ? 'Selecciona al menos un comando' : 'Select at least one callout',
      );
      return;
    }

    final callouts = ref.read(calloutsProvider).asData?.value;
    if (callouts == null) {
      _showFadingToast(
        context,
        isEs ? 'Error de comandos' : 'Callouts unavailable',
      );
      return;
    }

    if (ref.read(drillEngineProvider).running) {
      await ref.read(drillEngineProvider.notifier).stop();
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DrillRunnerScreen()),
    );
  }

  Future<void> _applyWorkoutPreset(
    WorkoutPreset preset, {
    required bool startNow,
    required bool isEs,
  }) async {
    final notifier = ref.read(drillConfigProvider.notifier);
    final difficultyIndex = _difficultyIndexForPreset(preset);
    final difficultyLevel = _difficultyLevels[difficultyIndex];
    final isPro = ref.read(isProProvider);
    final shouldDisableFreeRecording =
        !isPro && ref.read(drillConfigProvider).videoEnabled;

    notifier.applyWorkoutPreset(
      preset,
      totalDurationSeconds: preset.recommendedDurationSeconds,
      minIntervalSeconds: difficultyLevel.$2,
      maxIntervalSeconds: difficultyLevel.$3,
      videoEnabled: shouldDisableFreeRecording ? false : null,
    );

    if (mounted) {
      setState(() {
        _difficultyValue = difficultyIndex.toDouble();
        if (shouldDisableFreeRecording) {
          _showFreeVideoDurationHint = false;
        }
      });
    }

    if (shouldDisableFreeRecording) {
      await ref.read(drillEngineProvider.notifier).disposeCamera();
    }

    if (startNow) {
      await _startConfiguredDrill(isEs: isEs);
      return;
    }

    if (!mounted) return;
    _showFadingToast(
      context,
      shouldDisableFreeRecording
          ? (isEs
              ? '${preset.title(isEs: isEs)} cargado. Grabacion desactivada para el workout completo.'
              : '${preset.title(isEs: isEs)} loaded. Recording turned off for the full workout.')
          : (isEs
              ? '${preset.title(isEs: isEs)} cargado'
              : '${preset.title(isEs: isEs)} loaded'),
    );
  }

  void _showWorkoutPresetSheet({required bool isEs}) {
    final dailyMission = ref.read(dailyMissionProvider);

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        sheetAnimationStyle: const AnimationStyle(
          duration: Duration(milliseconds: 420),
          reverseDuration: Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        builder: (_) => WorkoutPresetSheet(
          isEs: isEs,
          dailyMission: dailyMission,
          onPresetSelected: (preset, {required startNow}) {
            unawaited(
              _applyWorkoutPreset(
                preset,
                startNow: startNow,
                isEs: isEs,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _setRecordingEnabled(
    bool enableVideo, {
    required bool isEs,
    required bool isPro,
  }) async {
    ref.read(drillConfigProvider.notifier).setVideoEnabled(enableVideo);

    final drillEngine = ref.read(drillEngineProvider.notifier);
    if (enableVideo) {
      if (!isPro) {
        _showFreeVideoDurationLockMessage(
          context,
          isEs: isEs,
        );
      }
      if (_legacyFreeVideoLimitMessageEnabled && !isPro) {
        if (ref.read(drillConfigProvider).totalDurationSeconds >
            RecordingPolicy.freeRecordingLimitSeconds) {
          setState(() {
            _showFreeVideoDurationHint = true;
          });
        }
        _showFadingToast(
          context,
          isEs ? 'Limite de 60s' : 'Free limit: 60s',
        );
      }
      await drillEngine.preloadCamera();
    } else {
      setState(() {
        _showFreeVideoDurationHint = false;
      });
      await drillEngine.disposeCamera();
    }
  }

  Future<void> _startRecordedDrill({
    required bool isEs,
    required bool isPro,
  }) async {
    if (!ref.read(drillConfigProvider).videoEnabled) {
      await _setRecordingEnabled(true, isEs: isEs, isPro: isPro);
    }
    if (!mounted) return;
    await _startConfiguredDrill(isEs: isEs);
  }

  void _showProPrompt() {
    final proPurchase = ref.read(proPurchaseProvider);
    if (proPurchase.canBuy) {
      unawaited(ref.read(proPurchaseProvider.notifier).buyPro());
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          proPurchase.errorMessage ??
              'Snap & Go Coach Mode is loading. Try again in a moment.',
        ),
      ),
    );
  }

  void _showAdLibSheet(AdLibSlot slot, {required bool isPro}) {
    if (!slot.isUnlocked(isPro: isPro)) {
      _showProPrompt();
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AdLibRecordingSheet(
          slot: slot,
          allowCustomization: slot.canCustomize(isPro: isPro),
          onUpgradeTap: _showProPrompt,
        ),
      ),
    );
  }

  void _showAddCalloutSheet({required bool isPro}) {
    if (!isPro) {
      _showProPrompt();
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const AddCalloutSheet(autoEnableOnSave: true),
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
    final engineRunning =
        ref.watch(drillEngineProvider.select((state) => state.running));
    final calloutsAsync = ref.watch(calloutsProvider);
    final lang = ref.watch(languageProvider);
    final isPro = ref.watch(isProProvider);
    final progress = ref.watch(trainingProgressProvider);
    final dailyMission = ref.watch(dailyMissionProvider);

    final isEs = lang == 'es';

    return Scaffold(
      appBar: _buildAppBar(isEs),
      body: _buildTabTransition(
        child: _buildSelectedTab(
          config: config,
          engineRunning: engineRunning,
          calloutsAsync: calloutsAsync,
          isEs: isEs,
          isPro: isPro,
          progress: progress,
          dailyMission: dailyMission,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: _changeTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: isEs ? 'Inicio' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.fitness_center_outlined),
            selectedIcon: const Icon(Icons.fitness_center),
            label: isEs ? 'Entrenar' : 'Train',
          ),
          NavigationDestination(
            icon: const Icon(Icons.query_stats_outlined),
            selectedIcon: const Icon(Icons.query_stats),
            label: isEs ? 'Progreso' : 'Progress',
          ),
          NavigationDestination(
            icon: const Icon(Icons.video_library_outlined),
            selectedIcon: const Icon(Icons.video_library),
            label: isEs ? 'Review' : 'Review',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: isEs ? 'Ajustes' : 'Settings',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar(bool isEs) {
    if (_selectedTabIndex == 4) return null;

    Widget title;
    switch (_selectedTabIndex) {
      case 1:
        title = Text(isEs ? 'Entrenar' : 'Train');
        break;
      case 2:
        title = Text(isEs ? 'Progreso' : 'Progress');
        break;
      case 3:
        title = Text(isEs ? 'Review' : 'Review');
        break;
      default:
        title = const _BrandTitle();
    }

    return AppBar(
      title: title,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _changeTab(4),
        ),
      ],
    );
  }

  Widget _buildTabTransition({required Widget child}) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return ClipRect(
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
        reverseDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final previousChild in previousChildren)
                Positioned.fill(child: previousChild),
              if (currentChild != null) Positioned.fill(child: currentChild),
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final key = child.key;
          final childIndex =
              key is ValueKey<int> ? key.value : _selectedTabIndex;
          final isIncoming = childIndex == _selectedTabIndex;
          final direction = _tabTransitionDirection.toDouble();
          final position = isIncoming
              ? Tween<Offset>(
                  begin: Offset(direction, 0),
                  end: Offset.zero,
                ).animate(animation)
              : Tween<Offset>(
                  begin: Offset(-direction, 0),
                  end: Offset.zero,
                ).animate(animation);

          return SlideTransition(
            position: position,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedTabIndex),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSelectedTab({
    required DrillConfig config,
    required bool engineRunning,
    required AsyncValue<List<Callout>> calloutsAsync,
    required bool isEs,
    required bool isPro,
    required TrainingProgress progress,
    required WorkoutPreset dailyMission,
  }) {
    switch (_selectedTabIndex) {
      case 0:
        return TrainingDashboard(
          progress: progress,
          isEs: isEs,
          missionLoading: calloutsAsync.isLoading,
          dailyMission: dailyMission,
          onStartMission: () => unawaited(
            _applyWorkoutPreset(
              dailyMission,
              startNow: true,
              isEs: isEs,
            ),
          ),
          onBrowseWorkouts: () => _showWorkoutPresetSheet(isEs: isEs),
          onCustomizeDrill: () {
            _changeTab(1);
          },
        );
      case 1:
        return _buildTrainTab(
          config: config,
          engineRunning: engineRunning,
          calloutsAsync: calloutsAsync,
          isEs: isEs,
          isPro: isPro,
          dailyMission: dailyMission,
        );
      case 2:
        return TrainingProgressView(
          progress: progress,
          isEs: isEs,
          onStartTraining: () {
            _changeTab(1);
          },
        );
      case 3:
        return RecordingsView(
          isEs: isEs,
          recordingEnabled: config.videoEnabled,
          onRecordingChanged: (enabled) {
            unawaited(
              _setRecordingEnabled(enabled, isEs: isEs, isPro: isPro),
            );
          },
          onStartRecordedDrill: () {
            unawaited(_startRecordedDrill(isEs: isEs, isPro: isPro));
          },
        );
      default:
        return const SettingsScreen();
    }
  }

  Widget _buildTrainTab({
    required DrillConfig config,
    required bool engineRunning,
    required AsyncValue<List<Callout>> calloutsAsync,
    required bool isEs,
    required bool isPro,
    required WorkoutPreset dailyMission,
  }) {
    final notifier = ref.read(drillConfigProvider.notifier);
    final isFreeRecordingLocked = config.videoEnabled && !isPro;
    final selectedDurationMinutes =
        isFreeRecordingLocked ? 1 : (config.totalDurationSeconds / 60).round();
    final durationSliderMaxMinutes = config.videoEnabled && isPro ? 10 : 15;
    final durationSliderValue = isFreeRecordingLocked
        ? 1.0
        : selectedDurationMinutes.clamp(1, durationSliderMaxMinutes).toDouble();
    final showFreeVideoDurationHint =
        isFreeRecordingLocked && _showFreeVideoDurationHint;

    return Column(
      children: [
        _TrainControlDock(
          isEs: isEs,
          isPro: isPro,
          engineRunning: engineRunning,
          recordingEnabled: config.videoEnabled,
          adLibsEnabled: config.adLibsEnabled,
          durationMinutes: durationSliderValue,
          durationMaxMinutes: durationSliderMaxMinutes,
          durationLocked: isFreeRecordingLocked,
          showFreeVideoDurationHint: showFreeVideoDurationHint,
          difficultyValue: _difficultyValue,
          difficultyLabel: _difficultyLevels[_difficultyValue.round()].$1,
          config: config,
          onStart: () => unawaited(_startConfiguredDrill(isEs: isEs)),
          onRecordingTap: () {
            unawaited(
              _setRecordingEnabled(
                !ref.read(drillConfigProvider).videoEnabled,
                isEs: isEs,
                isPro: isPro,
              ),
            );
          },
          onDurationLocked: () {
            _showFreeVideoDurationLockMessage(context, isEs: isEs);
          },
          onDurationChanged: (val) {
            final requestedSeconds = (val * 60).round();
            notifier.setTotalDurationSeconds(requestedSeconds);
            if (_showFreeVideoDurationHint) {
              setState(() {
                _showFreeVideoDurationHint = false;
              });
            }
          },
          onDifficultyChanged: _updateDifficulty,
          onAdLibsChanged: (enabled) => notifier.setAdLibsEnabled(enabled),
          onAdLibSlotTap: (slot) => _showAdLibSheet(slot, isPro: isPro),
        ),
        Expanded(
          child: calloutsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) => _CalloutToggleScroller(
              callouts: list,
              isEs: isEs,
              config: config,
              dailyMission: dailyMission,
              onWorkoutsTap: () => _showWorkoutPresetSheet(isEs: isEs),
              onToggle: (callout, enabled) {
                notifier.toggleCallout(callout.id, enabled: enabled);
              },
              onRecordTapped: (callout) => _showRecordingSheet(
                context,
                callout.id,
                isEs ? callout.nameEs : callout.nameEn,
                initialAudioPath: callout.audioUrl,
              ),
              onAddNewTapped: () => _showAddCalloutSheet(isPro: isPro),
            ),
          ),
        ),
      ],
    );
  }
}
