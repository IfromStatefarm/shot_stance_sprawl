import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/features/drill/models.dart';
import 'package:shot_stance_sprawl/features/drill/presentation/training_dashboard.dart';
import 'package:shot_stance_sprawl/features/drill/workout_presets.dart';
import 'package:shot_stance_sprawl/features/social/social_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('progress screen lays out at narrow widths and larger text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final today = DateTime.now();
    final progress = TrainingProgress(
      repsByDate: {TrainingProgress.dateKey(today): 17},
    );

    for (final (size, scale, isEs) in [
      (const Size(390, 844), 1.0, false),
      (const Size(320, 640), 1.0, false),
      (const Size(320, 640), 2.0, false),
      (const Size(320, 640), 2.0, true),
      (const Size(320, 640), 3.0, false),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                  size: size, textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: TrainingProgressView(
                  progress: progress,
                  isEs: isEs,
                  onStartTraining: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      while (scrollable.position.pixels < scrollable.position.maxScrollExtent) {
        scrollable.position.jumpTo(
          (scrollable.position.pixels + 300)
              .clamp(0, scrollable.position.maxScrollExtent),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'size: $size, scale: $scale, Spanish: $isEs');
      }
    }
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  testWidgets('home dashboard lays out with larger text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const size = Size(320, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final isEs in [false, true]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialProfileProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(3),
              ),
              child: Scaffold(
                body: TrainingDashboard(
                  progress: TrainingProgress.initial(),
                  isEs: isEs,
                  missionLoading: false,
                  onStartMission: () {},
                  dailyMission: const WorkoutPreset(
                    id: 'layout_test',
                    titleEn: 'Daily workout',
                    titleEs: 'Entrenamiento diario',
                    category: WorkoutPresetCategory.quick,
                    calloutIds: ['shot', 'sprawl'],
                    minMinutes: 5,
                    maxMinutes: 5,
                    minDifficulty: 1,
                    maxDifficulty: 1,
                    purposeEn: 'Practice your moves',
                    purposeEs: 'Practica tus movimientos',
                  ),
                  onBrowseWorkouts: () {},
                  onCustomizeDrill: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      while (scrollable.position.pixels < scrollable.position.maxScrollExtent) {
        scrollable.position.jumpTo(
          (scrollable.position.pixels + 300)
              .clamp(0, scrollable.position.maxScrollExtent),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Spanish: $isEs');
      }
    }
  });
}
