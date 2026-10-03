import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/features/compliance/compliance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('age selection is persisted locally', () async {
    expect(await AgeEligibilityStorage.load(), isNull);

    await AgeEligibilityStorage.save(AgeEligibility.under13);

    expect(await AgeEligibilityStorage.load(), AgeEligibility.under13);
  });

  testWidgets('neutral age screen offers both ranges and saves the choice',
      (tester) async {
    AgeEligibility? selected;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AgeEligibilityScreen(
            onFinished: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Under 13'), findsOneWidget);
    expect(find.text('13 or older'), findsOneWidget);

    await tester.tap(find.text('Under 13'));
    await tester.pumpAndSettle();

    expect(selected, AgeEligibility.under13);
    expect(await AgeEligibilityStorage.load(), AgeEligibility.under13);
  });

  testWidgets('under-13 restriction explains which features remain local',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
          home: Scaffold(body: ConnectedFeaturesRestrictedView())),
    );

    expect(find.text('Local training mode'), findsOneWidget);
    expect(find.textContaining('purchases are available only'), findsOneWidget);
    expect(find.textContaining('Local workouts'), findsOneWidget);
  });
}
