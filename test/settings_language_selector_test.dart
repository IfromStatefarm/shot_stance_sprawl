import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/widgets/settings_voice_pack_section.dart';
import 'package:shot_stance_sprawl/features/drill/providers.dart';

void main() {
  testWidgets('language dropdown updates interface and voice-pack language',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const packs = [
      VoicePack(
        id: 'default_en',
        name: 'English Coach',
        languageCode: 'en',
        languageName: 'English',
        calloutAssets: {},
        adLibAssets: {},
        whistleAsset: '',
      ),
      VoicePack(
        id: 'coach_es',
        name: 'Entrenador',
        languageCode: 'es',
        languageName: 'Español',
        calloutAssets: {},
        adLibAssets: {},
        whistleAsset: '',
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        voicePacksProvider.overrideWith((ref) async => packs),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPrefsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SettingsLanguageSelector()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    expect(container.read(languageProvider), 'es');
    expect(container.read(drillConfigProvider).voicePackId, 'coach_es');
    expect(find.text('Idioma de la aplicación'), findsOneWidget);
  });
}
