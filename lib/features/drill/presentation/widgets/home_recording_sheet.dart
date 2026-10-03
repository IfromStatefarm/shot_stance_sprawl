import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_theme.dart';
import '../../providers.dart';
import '../../services/shared_audio_recording_service.dart';

class HomeRecordingSheetContent extends ConsumerStatefulWidget {
  final String calloutId;
  final String calloutName;
  final String? initialAudioPath;

  const HomeRecordingSheetContent({
    super.key,
    required this.calloutId,
    required this.calloutName,
    this.initialAudioPath,
  });

  @override
  ConsumerState<HomeRecordingSheetContent> createState() =>
      _HomeRecordingSheetContentState();
}

class _HomeRecordingSheetContentState
    extends ConsumerState<HomeRecordingSheetContent> {
  final _audio = SharedAudioRecordingService();
  bool isRecording = false;
  String? recordedPath;

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
    if (await _audio.hasPermission()) {
      final path = await _audio.timestampedDocumentAudioPath(widget.calloutId);

      await _audio.startAacRecording(path);

      setState(() => isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await _audio.stopRecording();
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
      await _audio.stopPlayer();
      await _audio.playDeviceFile(path);
    } catch (e) {
      debugPrint('Could not play custom callout preview: $e');
    }
  }

  Future<void> _deleteOverrideRecording(String path) async {
    await _audio.stopPlayer();
    ref.read(drillConfigProvider.notifier).removeCalloutAudio(widget.calloutId);

    setState(() {
      recordedPath = null;
      isRecording = false;
    });

    await _audio.deleteFileIfExists(
      path,
      debugLabel: 'Could not delete custom callout audio',
    );
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
              borderRadius: BorderRadius.circular(2),
            ),
          ),
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
                      child: Icon(
                        isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(isRecording ? 'STOP' : 'REC'),
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
