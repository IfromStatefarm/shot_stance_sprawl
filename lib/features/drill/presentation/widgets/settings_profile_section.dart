import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app_theme.dart';
import '../../providers.dart';
import '../../../social/social_providers.dart';
import '../../../social/team_sheet.dart';

class SettingsProfileHeader extends ConsumerWidget {
  const SettingsProfileHeader({super.key});

  Future<void> _pickImage(WidgetRef ref) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      ref.read(userProfileProvider.notifier).updateProfileImage(image.path);
    }
  }

  void _editField(
    BuildContext context,
    WidgetRef ref,
    String label,
    String currentVal,
    void Function(String) onSave, {
    bool isNumber = false,
  }) {
    final controller = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              ref.read(languageProvider) == 'es' ? 'Cancelar' : 'Cancel',
            ),
          ),
          FilledButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(ctx);
            },
            child:
                Text(ref.read(languageProvider) == 'es' ? 'Guardar' : 'Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final user = ref.watch(userProfileProvider);
    final team = ref.watch(currentTeamProvider).asData?.value;
    final isEs = lang == 'es';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      child: Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ProfileSetupTile(
            icon: Icons.monitor_weight_outlined,
            label: isEs ? 'Peso' : 'Weight',
            value: '${user.weightLbs.toStringAsFixed(0)} lb',
            onTap: () => _editField(
              context,
              ref,
              isEs ? 'Peso' : 'Weight',
              user.weightLbs.toStringAsFixed(0),
              (val) {
                final d = double.tryParse(val);
                if (d != null && d > 0) {
                  ref.read(userProfileProvider.notifier).updateWeight(d);
                }
              },
              isNumber: true,
            ),
          ),
          const SizedBox(height: 8),
          _ProfileSetupTile(
            icon: Icons.groups_outlined,
            label: isEs ? 'Mi equipo' : 'My Team',
            value: team?.name ?? (isEs ? 'Crear o unirme' : 'Create or join'),
            onTap: () => showTeamSheet(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ProfileSetupTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ProfileSetupTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        leading: Icon(icon, color: AppBrandColors.red),
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
      ),
    );
  }
}
