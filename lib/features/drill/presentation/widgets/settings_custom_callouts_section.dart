import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_theme.dart';
import '../../providers.dart';
import '../../services/shared_audio_recording_service.dart';

class SettingsCustomCalloutsManager extends ConsumerWidget {
  const SettingsCustomCalloutsManager({super.key});

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const AddCalloutSheet(),
      ),
    );
  }

  // BUG FIX: Added Rename Dialog for existing custom callouts
  void _showRenameDialog(BuildContext context, WidgetRef ref, Callout c) {
    final ctrl = TextEditingController(text: c.nameEn);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Callout'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                ref
                    .read(calloutsProvider.notifier)
                    .updateCalloutName(c.id, ctrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calloutsAsync = ref.watch(calloutsProvider);
    final lang = ref.watch(languageProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.add_circle, color: AppBrandColors.blue),
          title:
              Text(lang == 'es' ? 'Agregar Nuevo Comando' : 'Add New Callout'),
          onTap: () => _showAddDialog(context),
        ),
        calloutsAsync.when(
          data: (list) {
            final customs = list.where((c) => c.isCustom).toList();
            if (customs.isEmpty) return const SizedBox.shrink();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: customs.length,
              itemBuilder: (context, index) {
                final c = customs[index];
                return ListTile(
                  leading: const Icon(Icons.mic, color: Colors.grey),
                  title: Text(c.name),
                  // Appended Edit capability along with delete
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon:
                            const Icon(Icons.edit, color: AppBrandColors.blue),
                        onPressed: () => _showRenameDialog(context, ref, c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          ref
                              .read(calloutsProvider.notifier)
                              .deleteCallout(c.id);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

class AddCalloutSheet extends ConsumerStatefulWidget {
  final bool autoEnableOnSave;

  const AddCalloutSheet({
    super.key,
    this.autoEnableOnSave = false,
  });

  @override
  ConsumerState<AddCalloutSheet> createState() => _AddCalloutSheetState();
}

class _AddCalloutSheetState extends ConsumerState<AddCalloutSheet> {
  final TextEditingController _nameController = TextEditingController();
  final SharedAudioRecordingService _audio = SharedAudioRecordingService();

  bool _isRecording = false;
  String? _tempPath;
  int _selectedDuration = 0;

  @override
  void dispose() {
    _audio.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audio.stopRecording();
      setState(() {
        _isRecording = false;
        _tempPath = path;
      });
    } else {
      if (await _audio.hasPermission()) {
        final path = await _audio.timestampedDocumentAudioPath('temp');

        await _audio.startDefaultRecording(path);
        setState(() => _isRecording = true);
      }
    }
  }

  Future<void> _save(WidgetRef ref) async {
    if (_nameController.text.isEmpty || _tempPath == null) return;
    final audioPath = _tempPath!;

    final newCallout = Callout(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      nameEn: _nameController.text,
      nameEs: _nameController.text,
      type: _selectedDuration > 0
          ? 'Duration'
          : 'Movement', // Set type based on whether duration was specified
      defaultDurationSeconds: _selectedDuration, // Store duration if set
      audioUrl: audioPath,
      isCustom: true,
    );

    await ref.read(calloutsProvider.notifier).addCustomCallout(newCallout);
    ref.read(drillConfigProvider.notifier).updateCalloutAudio(
          newCallout.id,
          audioPath,
        );
    if (widget.autoEnableOnSave) {
      ref
          .read(drillConfigProvider.notifier)
          .toggleCallout(newCallout.id, enabled: true);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final isEs = lang == 'es';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEs ? 'Nuevo Comando' : 'New Callout',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: isEs ? 'Nombre del comando' : 'Callout Name',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(isEs ? 'Tipo de Comando' : 'Callout Type',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Action')),
                ButtonSegment(value: 15, label: Text('15s')),
                ButtonSegment(value: 30, label: Text('30s')),
                ButtonSegment(value: 45, label: Text('45s')),
                ButtonSegment(value: 60, label: Text('60s')),
              ],
              selected: {_selectedDuration},
              onSelectionChanged: (newSelection) =>
                  setState(() => _selectedDuration = newSelection.first),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _toggleRecording,
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: _isRecording ? Colors.red : Colors.grey[200],
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: _isRecording ? Colors.white : Colors.black,
                    size: 30,
                  ),
                ),
              ),
              if (_tempPath != null && !_isRecording) ...[
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.play_arrow,
                      size: 40, color: AppBrandColors.blue),
                  onPressed: () => _audio.playDeviceFile(_tempPath!),
                ),
              ]
            ],
          ),
          const SizedBox(height: 10),
          Center(
              child: Text(_isRecording
                  ? "Recording..."
                  : (_tempPath != null ? "Audio Recorded" : "Tap to Record"))),
          const SizedBox(height: 30),
          FilledButton(
            onPressed: (_tempPath != null && _nameController.text.isNotEmpty)
                ? () => _save(ref)
                : null,
            child: Text(isEs ? 'Guardar' : 'Save Callout'),
          ),
        ],
      ),
    );
  }
}
