import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_theme.dart';
import '../../ad_libs.dart';
import '../../providers.dart';
import '../../services/shared_audio_recording_service.dart';

class SettingsAdLibSlotsManager extends ConsumerWidget {
  final bool isPro;
  final VoidCallback onUpgradeTap;

  const SettingsAdLibSlotsManager({
    super.key,
    required this.isPro,
    required this.onUpgradeTap,
  });

  void _showCustomizeSheet(BuildContext context, AdLibSlot slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AdLibRecordingSheet(slot: slot),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(drillConfigProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          for (final slot in AdLibSlots.all)
            _AdLibSlotTile(
              slot: slot,
              available: slot.isUnlocked(isPro: isPro),
              customizable: slot.canCustomize(isPro: isPro),
              hasCustomAudio: slot.canCustomize(isPro: isPro) &&
                  config.customAdLibAudioPaths.containsKey(slot.id),
              onTap: () {
                if (!slot.isUnlocked(isPro: isPro)) {
                  onUpgradeTap();
                  return;
                }
                if (!slot.canCustomize(isPro: isPro)) {
                  onUpgradeTap();
                  return;
                }
                _showCustomizeSheet(context, slot);
              },
            ),
        ],
      ),
    );
  }
}

class _AdLibSlotTile extends ConsumerWidget {
  final AdLibSlot slot;
  final bool available;
  final bool customizable;
  final bool hasCustomAudio;
  final VoidCallback onTap;

  const _AdLibSlotTile({
    required this.slot,
    required this.available,
    required this.customizable,
    required this.hasCustomAudio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: available ? 1 : 0,
      color: available ? scheme.surface : scheme.surfaceContainerHighest,
      child: ListTile(
        enabled: available,
        leading: Icon(
          available
              ? (hasCustomAudio ? Icons.mic : Icons.graphic_eq)
              : Icons.lock,
          color: available
              ? (hasCustomAudio ? AppBrandColors.blue : scheme.primary)
              : AppBrandColors.gold,
        ),
        title: Text(slot.label),
        subtitle: Text(
          !available
              ? (lang == 'es'
                  ? 'Bloqueado para Coach Mode'
                  : 'Locked for Coach Mode')
              : !customizable
                  ? (lang == 'es'
                      ? 'Audio predeterminado - Coach Mode para personalizar'
                      : 'Default audio - Coach Mode to customize')
                  : hasCustomAudio
                      ? (lang == 'es' ? 'Audio personalizado' : 'Custom audio')
                      : (lang == 'es'
                          ? 'Audio predeterminado'
                          : 'Default audio'),
        ),
        trailing: Icon(
          customizable ? Icons.chevron_right : Icons.lock_outline,
          color: customizable ? null : AppBrandColors.gold,
        ),
        onTap: onTap,
      ),
    );
  }
}

class AdLibRecordingSheet extends ConsumerStatefulWidget {
  final AdLibSlot slot;
  final bool allowCustomization;
  final VoidCallback? onUpgradeTap;

  const AdLibRecordingSheet({
    super.key,
    required this.slot,
    this.allowCustomization = true,
    this.onUpgradeTap,
  });

  @override
  ConsumerState<AdLibRecordingSheet> createState() =>
      _AdLibRecordingSheetState();
}

class _AdLibRecordingSheetState extends ConsumerState<AdLibRecordingSheet> {
  final _audio = SharedAudioRecordingService();
  bool _isRecording = false;
  String? _recordedPath;

  @override
  void initState() {
    super.initState();
    _audio.configurePreviewPlayer();
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!widget.allowCustomization) return;
    if (!await _audio.hasPermission()) return;

    await _audio.stopPlayer();
    final path = await _audio.timestampedDocumentAudioPath(widget.slot.id);

    await _audio.startAacRecording(path);

    if (mounted) {
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await _audio.stopRecording();
    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _recordedPath = path;
    });

    if (path != null) {
      ref
          .read(drillConfigProvider.notifier)
          .updateAdLibAudio(widget.slot.id, path);
    }
  }

  Future<void> _playPreview(String path) async {
    try {
      await _audio.playPreviewPath(path);
    } catch (e) {
      debugPrint('Could not play ad lib preview: $e');
    }
  }

  Future<void> _deleteCustomAudio(String path) async {
    if (!widget.allowCustomization) return;
    await _audio.stopPlayer();
    ref.read(drillConfigProvider.notifier).removeAdLibAudio(widget.slot.id);

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordedPath = null;
      });
    }

    await _audio.deleteFileIfExists(
      path,
      debugLabel: 'Could not delete ad lib audio',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final config = ref.watch(drillConfigProvider);
    final customPath =
        _recordedPath ?? config.customAdLibAudioPaths[widget.slot.id];
    final packPath = ref.watch(voicePacksProvider).whenOrNull(
      data: (packs) {
        for (final pack in packs) {
          if (pack.id == config.voicePackId) {
            return pack.adLibAssets[widget.slot.id];
          }
        }
        return null;
      },
    );
    final activePath = customPath ?? packPath ?? widget.slot.defaultAssetPath;

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
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isRecording
                ? (lang == 'es' ? 'Grabando...' : 'Recording...')
                : !widget.allowCustomization
                    ? widget.slot.label
                    : (lang == 'es'
                        ? 'Personalizar ${widget.slot.label}'
                        : 'Customize ${widget.slot.label}'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (!_isRecording)
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _playPreview(activePath),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: AppBrandColors.blue,
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('PLAY'),
                  ],
                ),
              if (widget.allowCustomization)
                Column(
                  children: [
                    GestureDetector(
                      onTap: _isRecording ? _stopRecording : _startRecording,
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor:
                            _isRecording ? Colors.red : Colors.redAccent,
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_isRecording ? 'STOP' : 'REC'),
                  ],
                )
              else
                Column(
                  children: [
                    GestureDetector(
                      onTap: widget.onUpgradeTap,
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: AppBrandColors.goldDark,
                        child: Icon(
                          Icons.lock,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(lang == 'es' ? 'PRO' : 'PRO'),
                  ],
                ),
              if (customPath != null &&
                  !_isRecording &&
                  widget.allowCustomization)
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _deleteCustomAudio(customPath),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: AppBrandColors.goldDark,
                        child: Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(lang == 'es' ? 'BORRAR' : 'DELETE'),
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
