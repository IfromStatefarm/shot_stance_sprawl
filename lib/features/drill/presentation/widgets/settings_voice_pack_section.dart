import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

class SettingsLanguageSelector extends ConsumerWidget {
  const SettingsLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLanguage = ref.watch(languageProvider);
    final isEs = currentLanguage == 'es';
    final availablePacks = ref.watch(voicePacksProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('app-language-$currentLanguage'),
        initialValue: currentLanguage,
        decoration: InputDecoration(
          labelText: isEs ? 'Idioma de la aplicación' : 'App language',
          helperText: isEs
              ? 'Cambia el texto y el audio de entrenamiento'
              : 'Changes interface text and training audio',
          prefixIcon: const Icon(Icons.language),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final language in supportedAppLanguages)
            DropdownMenuItem(
              value: language.code,
              child: Text(language.name),
            ),
        ],
        onChanged: (languageCode) async {
          if (languageCode == null || languageCode == currentLanguage) return;

          await ref
              .read(languageProvider.notifier)
              .setLanguage(languageCode);

          final matchingPacks = availablePacks
                  ?.where((pack) => pack.languageCode == languageCode)
                  .toList() ??
              const [];
          if (matchingPacks.isNotEmpty) {
            ref
                .read(drillConfigProvider.notifier)
                .setVoicePack(matchingPacks.first.id);
          }
        },
      ),
    );
  }
}

class SettingsVoicePackSelector extends ConsumerWidget {
  const SettingsVoicePackSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEs = ref.watch(languageProvider) == 'es';
    final selectedId = ref.watch(
      drillConfigProvider.select((config) => config.voicePackId),
    );
    final packs = ref.watch(voicePacksProvider);

    return packs.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(isEs
            ? 'Paquetes de voz no disponibles'
            : 'Voice packs unavailable'),
        subtitle: Text('$error'),
        trailing: IconButton(
          tooltip: isEs ? 'Reintentar' : 'Retry',
          onPressed: () => ref.invalidate(voicePacksProvider),
          icon: const Icon(Icons.refresh),
        ),
      ),
      data: (availablePacks) {
        if (availablePacks.isEmpty) {
          return ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: Text(isEs ? 'Sin paquetes de voz' : 'No voice packs found'),
          );
        }

        final selected = availablePacks.firstWhere(
          (pack) => pack.id == selectedId,
          orElse: () => availablePacks.first,
        );
        final appLanguage = ref.watch(languageProvider);
        final packsForAppLanguage = availablePacks
            .where((pack) => pack.languageCode == appLanguage)
            .toList();
        final sameLanguage = packsForAppLanguage.isEmpty
            ? availablePacks
                .where((pack) => pack.languageCode == selected.languageCode)
                .toList()
            : packsForAppLanguage;
        final selectedForLanguage = sameLanguage.any(
          (pack) => pack.id == selected.id,
        )
            ? selected
            : sameLanguage.first;

        if (selectedForLanguage.id != selectedId) {
          scheduleMicrotask(
            () => ref
                .read(drillConfigProvider.notifier)
                .setVoicePack(selectedForLanguage.id),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('voice-pack-${selectedForLanguage.id}'),
                initialValue: selectedForLanguage.id,
                decoration: InputDecoration(
                  labelText: isEs ? 'Voz del entrenador' : 'Coach voice',
                  prefixIcon: const Icon(Icons.record_voice_over),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final pack in sameLanguage)
                    DropdownMenuItem(
                      value: pack.id,
                      child: Text(pack.name),
                    ),
                ],
                onChanged: (packId) {
                  if (packId == null) return;
                  ref.read(drillConfigProvider.notifier).setVoicePack(packId);
                },
              ),
              if (selectedForLanguage.attribution.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  selectedForLanguage.attribution,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (ref.watch(drillConfigProvider).customAudioPaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    isEs
                        ? 'Tus grabaciones personalizadas reemplazan la voz seleccionada.'
                        : 'Your custom recordings override the selected voice.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
