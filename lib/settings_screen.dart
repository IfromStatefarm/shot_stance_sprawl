import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'features/drill/ad_libs.dart';
import 'features/drill/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _proSubtitle(String lang, ProPurchaseState purchaseState) {
    if (purchaseState.isPro) {
      return lang == 'es' ? 'Activo' : 'Active';
    }
    if (purchaseState.loading) {
      return lang == 'es'
          ? 'Cargando opciones de compra'
          : 'Loading purchase options';
    }
    if (purchaseState.errorMessage != null) {
      return purchaseState.errorMessage!;
    }
    final product = purchaseState.primaryProduct;
    if (product == null) {
      return lang == 'es'
          ? 'Producto Pro no disponible'
          : 'Pro product is unavailable';
    }
    return lang == 'es'
        ? 'Desbloquea videos largos y comandos personalizados por ${product.price}'
        : 'Unlock long videos and custom cues for ${product.price}';
  }

  void _buyPro(WidgetRef ref) {
    unawaited(ref.read(proPurchaseProvider.notifier).buyPro());
  }

  void _restorePurchases(WidgetRef ref) {
    unawaited(ref.read(proPurchaseProvider.notifier).restorePurchases());
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch $urlString: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(languageProvider);
    final isPro = ref.watch(isProProvider);
    final proPurchase = ref.watch(proPurchaseProvider);
    final user = ref.watch(userProfileProvider);
    final config = ref.watch(drillConfigProvider);
    final proProduct = proPurchase.primaryProduct;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentLang == 'es' ? 'Ajustes' : 'Settings'),
      ),
      body: ListView(
        children: [
          _SectionHeader(title: currentLang == 'es' ? 'Perfil' : 'Profile'),
          _ProfileHeader(user: user),
          const Divider(),
          _SectionHeader(
              title: currentLang == 'es' ? 'Preferencias' : 'Preferences'),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(currentLang == 'es' ? 'Idioma' : 'Language'),
            subtitle: Text(currentLang == 'es' ? 'Español' : 'English'),
            trailing: Switch(
              value: currentLang == 'es',
              activeThumbColor: AppBrandColors.red,
              onChanged: (val) {
                ref.read(languageProvider.notifier).state = val ? 'es' : 'en';
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over),
            title:
                Text(currentLang == 'es' ? 'Agregar Ad libs' : 'Add Ad libs'),
            subtitle: Text(currentLang == 'es'
                ? 'Reproduce una frase extra en comandos largos'
                : 'Play an extra cue during long callouts'),
            value: config.adLibsEnabled,
            onChanged: (v) =>
                ref.read(drillConfigProvider.notifier).setAdLibsEnabled(v),
          ),
          if (config.adLibsEnabled)
            _AdLibSlotsManager(
              isPro: isPro,
              onUpgradeTap: () => _buyPro(ref),
            ),
          const Divider(),
          _SectionHeader(
              title: currentLang == 'es'
                  ? 'Comandos Personalizados'
                  : 'Custom Callouts'),
          if (isPro)
            const _CustomCalloutsManager()
          else
            ListTile(
              leading: const Icon(Icons.lock, color: AppBrandColors.gold),
              title: const Text('Snap&Go Pro'),
              subtitle: Text(currentLang == 'es'
                  ? 'Suscríbete para agregar tus propios comandos'
                  : 'Subscribe to add your own audio cues'),
              trailing: FilledButton(
                onPressed: proPurchase.canBuy ? () => _buyPro(ref) : null,
                child: Text(
                  proPurchase.purchasePending
                      ? '...'
                      : (proProduct?.price ?? 'GO PRO'),
                ),
              ),
            ),
          if (!isPro)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                _proSubtitle(currentLang, proPurchase),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!isPro)
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(currentLang == 'es'
                  ? 'Restaurar compras'
                  : 'Restore Purchases'),
              subtitle: Text(currentLang == 'es'
                  ? 'Recupera Pro en este dispositivo'
                  : 'Recover Pro on this device'),
              trailing: proPurchase.restorePending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: proPurchase.restorePending
                  ? null
                  : () => _restorePurchases(ref),
            ),
          if (kDebugMode) ...[
            const Divider(),
            _SectionHeader(
                title: currentLang == 'es' ? 'Suscripción' : 'Subscription'),
            SwitchListTile(
              title: const Text('Simulate Pro Mode'),
              subtitle: const Text('Debug only: local entitlement override'),
              secondary: Icon(Icons.stars,
                  color: isPro ? AppBrandColors.gold : Colors.grey),
              value: isPro,
              onChanged: (val) {
                ref.read(proPurchaseProvider.notifier).setDebugOverride(val);
              },
            ),
          ],
          const Divider(),
          _SectionHeader(title: currentLang == 'es' ? 'Soporte' : 'Support'),
          ListTile(
            leading: const Icon(Icons.volunteer_activism, color: Colors.red),
            title: const Text('Keep Kids Wrestling'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchURL("https://youtu.be/8rUsjXm799A"),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(currentLang == 'es' ? 'Privacidad' : 'Privacy Policy'),
            onTap: () => _launchURL("https://keepkidswrestling.com/privacy"),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _AdLibSlotsManager extends ConsumerWidget {
  final bool isPro;
  final VoidCallback onUpgradeTap;
  const _AdLibSlotsManager({
    required this.isPro,
    required this.onUpgradeTap,
  });

  void _showCustomizeSheet(BuildContext context, AdLibSlot slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AdLibRecordingSheet(slot: slot),
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
              ? (lang == 'es' ? 'Bloqueado para Pro' : 'Locked for Pro')
              : !customizable
                  ? (lang == 'es'
                      ? 'Audio predeterminado - Pro para personalizar'
                      : 'Default audio - Pro to customize')
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

class _AdLibRecordingSheet extends ConsumerStatefulWidget {
  final AdLibSlot slot;

  const _AdLibRecordingSheet({required this.slot});

  @override
  ConsumerState<_AdLibRecordingSheet> createState() =>
      _AdLibRecordingSheetState();
}

class _AdLibRecordingSheetState extends ConsumerState<_AdLibRecordingSheet> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _isRecording = false;
  String? _recordedPath;

  @override
  void initState() {
    super.initState();
    unawaited(_player.setPlayerMode(PlayerMode.mediaPlayer));
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;

    await _player.stop();
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/${widget.slot.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    if (mounted) {
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
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
      await _player.stop();
      if (path.startsWith('assets/')) {
        await _player.play(AssetSource(path.replaceFirst('assets/', '')));
      } else {
        await _player.play(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint('Could not play ad lib preview: $e');
    }
  }

  Future<void> _deleteCustomAudio(String path) async {
    await _player.stop();
    ref.read(drillConfigProvider.notifier).removeAdLibAudio(widget.slot.id);

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordedPath = null;
      });
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Could not delete ad lib audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final config = ref.watch(drillConfigProvider);
    final customPath =
        _recordedPath ?? config.customAdLibAudioPaths[widget.slot.id];
    final activePath = customPath ?? widget.slot.defaultAssetPath;

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
              ),
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
              if (customPath != null && !_isRecording)
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

class _ProfileHeader extends ConsumerWidget {
  final UserProfile user;
  const _ProfileHeader({required this.user});

  Future<void> _pickImage(WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      ref.read(userProfileProvider.notifier).updateProfileImage(image.path);
    }
  }

  void _editField(BuildContext context, WidgetRef ref, String label,
      String currentVal, Function(String) onSave,
      {bool isNumber = false}) {
    final controller = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              onSave(controller.text);
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
    final lang = ref.watch(languageProvider);
    final isEs = lang == 'es';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: user.profileImageUrl != null
                      ? FileImage(File(user.profileImageUrl!))
                      : null,
                  child: user.profileImageUrl == null
                      ? const Icon(Icons.person, size: 50, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _pickImage(ref),
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: AppBrandColors.blue,
                      child:
                          Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ProfileStatTile(
                  label: isEs ? 'Peso (lbs)' : 'Weight',
                  value: user.weightLbs.toStringAsFixed(0),
                  onTap: () => _editField(
                      context, ref, 'Weight', user.weightLbs.toString(), (val) {
                    final d = double.tryParse(val);
                    if (d != null) {
                      ref.read(userProfileProvider.notifier).updateWeight(d);
                    }
                  }, isNumber: true),
                ),
              ),
              Expanded(
                child: _ProfileStatTile(
                  label: isEs ? 'Edad' : 'Age',
                  value: user.age.toString(),
                  onTap: () => _editField(
                      context, ref, 'Age', user.age.toString(), (val) {
                    final i = int.tryParse(val);
                    if (i != null) {
                      ref.read(userProfileProvider.notifier).updateAge(i);
                    }
                  }, isNumber: true),
                ),
              ),
              Expanded(
                child: _ProfileStatTile(
                  label: isEs ? 'Equipo' : 'Team',
                  value: user.teamName ?? '-',
                  onTap: () => _editField(
                      context, ref, 'Team', user.teamName ?? '', (val) {
                    ref.read(userProfileProvider.notifier).updateTeam(val);
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ProfileStatTile(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Card(
        elevation: 0,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomCalloutsManager extends ConsumerWidget {
  const _CustomCalloutsManager();

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const _AddCalloutSheet(),
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

class _AddCalloutSheet extends ConsumerStatefulWidget {
  const _AddCalloutSheet();

  @override
  ConsumerState<_AddCalloutSheet> createState() => _AddCalloutSheetState();
}

class _AddCalloutSheetState extends ConsumerState<_AddCalloutSheet> {
  final TextEditingController _nameController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  String? _tempPath;
  int _selectedDuration = 0;

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _tempPath = path;
      });
    } else {
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path =
            '${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(const RecordConfig(), path: path);
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
                  onPressed: () => _player.play(DeviceFileSource(_tempPath!)),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
