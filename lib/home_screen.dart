import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shot_stance_sprawl/drill_runner.dart';
import 'package:shot_stance_sprawl/features/drill/ad_libs.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/training_dashboard.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/widgets/home_callout_tile.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/widgets/home_recording_sheet.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/widgets/settings_ad_lib_section.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/widgets/settings_custom_callouts_section.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/widgets/workout_preset_sheet.dart';
import 'package:shot_stance_sprawl/features/drill/providers.dart';
import 'package:shot_stance_sprawl/features/drill/recording_policy.dart';

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
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 330),
        reverseDuration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
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
          final slideDirection =
              isIncoming ? _tabTransitionDirection : -_tabTransitionDirection;
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(slideDirection * 0.18, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
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

class _TrainControlDock extends StatelessWidget {
  final bool isEs;
  final bool isPro;
  final bool engineRunning;
  final bool recordingEnabled;
  final bool adLibsEnabled;
  final double durationMinutes;
  final int durationMaxMinutes;
  final bool durationLocked;
  final bool showFreeVideoDurationHint;
  final double difficultyValue;
  final String difficultyLabel;
  final DrillConfig config;
  final VoidCallback onStart;
  final VoidCallback onRecordingTap;
  final VoidCallback onDurationLocked;
  final ValueChanged<double> onDurationChanged;
  final ValueChanged<double> onDifficultyChanged;
  final ValueChanged<bool> onAdLibsChanged;
  final ValueChanged<AdLibSlot> onAdLibSlotTap;

  const _TrainControlDock({
    required this.isEs,
    required this.isPro,
    required this.engineRunning,
    required this.recordingEnabled,
    required this.adLibsEnabled,
    required this.durationMinutes,
    required this.durationMaxMinutes,
    required this.durationLocked,
    required this.showFreeVideoDurationHint,
    required this.difficultyValue,
    required this.difficultyLabel,
    required this.config,
    required this.onStart,
    required this.onRecordingTap,
    required this.onDurationLocked,
    required this.onDurationChanged,
    required this.onDifficultyChanged,
    required this.onAdLibsChanged,
    required this.onAdLibSlotTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: Icon(
                        engineRunning ? Icons.stop : Icons.play_arrow,
                        size: 26,
                      ),
                      label: Text(
                        engineRunning
                            ? (isEs ? 'DETENER' : 'STOP')
                            : (isEs ? 'INICIAR' : 'START'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor:
                            engineRunning ? Colors.red : Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RecordToggleButton(
                    enabled: recordingEnabled,
                    onTap: onRecordingTap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _CompactSliderControl(
                icon: Icons.timer,
                label: isEs ? 'Duracion' : 'Duration',
                valueLabel: '${durationMinutes.round()} min',
                value: durationMinutes,
                min: 1,
                max: durationMaxMinutes.toDouble(),
                divisions: durationMaxMinutes - 1,
                isLocked: durationLocked,
                onLockedInteraction: onDurationLocked,
                onChanged: onDurationChanged,
              ),
              if (showFreeVideoDurationHint)
                const Padding(
                  padding: EdgeInsets.only(left: 28, bottom: 4),
                  child: Text(
                    'Coach Mode unlocks longer videos, or toggle recording off',
                    style: TextStyle(
                      color: AppBrandColors.goldDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              _CompactSliderControl(
                icon: Icons.speed,
                label: isEs ? 'Dificultad' : 'Difficulty',
                valueLabel: difficultyLabel,
                value: difficultyValue,
                min: 0,
                max: 3,
                divisions: 3,
                onChanged: onDifficultyChanged,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.record_voice_over,
                      size: 18, color: AppBrandColors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEs ? 'Ad libs' : 'Ad libs',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Switch(
                    value: adLibsEnabled,
                    onChanged: onAdLibsChanged,
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: adLibsEnabled
                    ? Padding(
                        key: const ValueKey('ad-lib-row'),
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            for (final slot in AdLibSlots.all) ...[
                              Expanded(
                                child: _AdLibBox(
                                  slot: slot,
                                  isUnlocked: slot.isUnlocked(isPro: isPro),
                                  canCustomize: slot.canCustomize(isPro: isPro),
                                  hasCustomAudio:
                                      slot.canCustomize(isPro: isPro) &&
                                          config.customAdLibAudioPaths
                                              .containsKey(slot.id),
                                  onTap: () => onAdLibSlotTap(slot),
                                ),
                              ),
                              if (slot != AdLibSlots.all.last)
                                const SizedBox(width: 7),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactSliderControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool isLocked;
  final VoidCallback? onLockedInteraction;
  final ValueChanged<double> onChanged;

  const _CompactSliderControl({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.isLocked = false,
    this.onLockedInteraction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChangeStart: (_) {
                if (isLocked) onLockedInteraction?.call();
              },
              onChanged: (next) {
                if (isLocked) {
                  onLockedInteraction?.call();
                  return;
                }

                onChanged(next);
              },
            ),
          ),
        ),
        SizedBox(
          width: 72,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              valueLabel,
              maxLines: 1,
              style: const TextStyle(
                color: AppBrandColors.blue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordToggleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _RecordToggleButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? AppBrandColors.red : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppBrandColors.red.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              enabled ? Icons.videocam : Icons.videocam_off,
              color: enabled ? Colors.white : Colors.grey[700],
              size: 20,
            ),
            Text(
              'REC',
              style: TextStyle(
                color: enabled ? Colors.white : Colors.grey[700],
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdLibBox extends StatelessWidget {
  final AdLibSlot slot;
  final bool isUnlocked;
  final bool canCustomize;
  final bool hasCustomAudio;
  final VoidCallback onTap;

  const _AdLibBox({
    required this.slot,
    required this.isUnlocked,
    required this.canCustomize,
    required this.hasCustomAudio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = !isUnlocked
        ? Colors.grey
        : hasCustomAudio
            ? AppBrandColors.blue
            : AppBrandColors.goldDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: isUnlocked
              ? color.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isUnlocked ? color : Colors.grey.withValues(alpha: 0.35),
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${slot.number}',
                style: TextStyle(
                  color: isUnlocked ? color : Colors.grey,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            if (!isUnlocked || !canCustomize)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.lock,
                  size: 12,
                  color: isUnlocked ? AppBrandColors.goldDark : Colors.grey,
                ),
              ),
            if (hasCustomAudio)
              const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(
                  Icons.mic,
                  size: 12,
                  color: AppBrandColors.blue,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalloutToggleScroller extends StatelessWidget {
  final List<Callout> callouts;
  final DrillConfig config;
  final WorkoutPreset dailyMission;
  final bool isEs;
  final VoidCallback onWorkoutsTap;
  final void Function(Callout callout, bool enabled) onToggle;
  final ValueChanged<Callout> onRecordTapped;
  final VoidCallback onAddNewTapped;

  const _CalloutToggleScroller({
    required this.callouts,
    required this.config,
    required this.dailyMission,
    required this.isEs,
    required this.onWorkoutsTap,
    required this.onToggle,
    required this.onRecordTapped,
    required this.onAddNewTapped,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        _TrainWorkoutAccessCard(
          isEs: isEs,
          dailyMission: dailyMission,
          onTap: onWorkoutsTap,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              isEs ? 'Comandos' : 'Move toggles',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppBrandColors.blueLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Options',
                style: TextStyle(
                  color: AppBrandColors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _CalloutGridWithCue(
          callouts: callouts,
          config: config,
          onToggle: onToggle,
          onRecordTapped: onRecordTapped,
          onAddNewTapped: onAddNewTapped,
        ),
      ],
    );
  }
}

class _TrainWorkoutAccessCard extends StatelessWidget {
  final bool isEs;
  final WorkoutPreset dailyMission;
  final VoidCallback onTap;

  const _TrainWorkoutAccessCard({
    required this.isEs,
    required this.dailyMission,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppBrandColors.black,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppBrandColors.gold.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: AppBrandColors.red.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  child: const Icon(
                    Icons.view_carousel,
                    color: AppBrandColors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEs ? 'Workouts' : 'Workouts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppBrandColors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEs
                            ? 'Presets listos para entrenar'
                            : 'Ready-made training presets',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppBrandColors.white.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppBrandColors.gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isEs ? 'Abrir' : 'Open',
                        style: const TextStyle(
                          color: AppBrandColors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppBrandColors.black,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppBrandColors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppBrandColors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
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
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          dailyMission.title(isEs: isEs),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppBrandColors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _TrainWorkoutPill(
                        icon: Icons.timer,
                        text: dailyMission.durationLabel(isEs: isEs),
                      ),
                      _TrainWorkoutPill(
                        icon: Icons.apps,
                        text: isEs ? '40 presets' : '40 presets',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainWorkoutPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrainWorkoutPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppBrandColors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppBrandColors.gold),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: AppBrandColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalloutGridWithCue extends StatelessWidget {
  final List<Callout> callouts;
  final DrillConfig config;
  final void Function(Callout callout, bool enabled) onToggle;
  final ValueChanged<Callout> onRecordTapped;
  final VoidCallback onAddNewTapped;

  const _CalloutGridWithCue({
    required this.callouts,
    required this.config,
    required this.onToggle,
    required this.onRecordTapped,
    required this.onAddNewTapped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const cueWidth = 26.0;
        const spacing = 8.0;
        const aspectRatio = 0.92;
        final columns = constraints.maxWidth >= 560 ? 4 : 3;
        final gridWidth = constraints.maxWidth - cueWidth;
        final tileWidth = (gridWidth - spacing * (columns - 1)) / columns;
        final tileHeight = tileWidth / aspectRatio;
        final totalTiles = callouts.length + 1;
        final rows = (totalTiles / columns).ceil();
        final gridHeight =
            rows * tileHeight + (rows > 0 ? (rows - 1) * spacing : 0);

        return SizedBox(
          height: gridHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: gridWidth,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: totalTiles,
                  itemBuilder: (context, index) {
                    if (index == callouts.length) {
                      return AddNewCalloutTile(
                        compact: true,
                        onTap: onAddNewTapped,
                      );
                    }

                    final callout = callouts[index];
                    return HomeCalloutTile(
                      compact: true,
                      callout: callout,
                      enabled: config.enabledCalloutIds.contains(callout.id),
                      onChanged: (enabled) => onToggle(callout, enabled),
                      onRecordTapped: () => onRecordTapped(callout),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 18,
                child: CustomPaint(
                  painter: _ScrollCueRailPainter(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScrollCueRailPainter extends CustomPainter {
  const _ScrollCueRailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final linePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final markerPaint = Paint()
      ..color = AppBrandColors.red
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(centerX, 4),
      Offset(centerX, centerY - 18),
      linePaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY + 18),
      Offset(centerX, size.height - 4),
      linePaint,
    );
    canvas.drawCircle(Offset(centerX, centerY), 3.5, markerPaint);
    canvas.drawLine(
      Offset(centerX - 5, centerY + 11),
      Offset(centerX + 5, centerY - 11),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
