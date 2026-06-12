import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/onboarding/onboarding.dart';

void main() {
  test('onboarding profile serializes selected answers', () {
    final profile = OnboardingProfile(
      role: OnboardingRole.coach,
      goal: OnboardingGoal.tournament,
      focus: OnboardingFocus.defense,
      pushLevel: OnboardingPushLevel.max,
      workoutRemindersEnabled: true,
      completedAt: DateTime(2026, 6, 12, 9),
      lastWorkoutCompletedAt: DateTime(2026, 6, 13, 19, 30),
    );

    final restored = OnboardingProfile.fromJson(profile.toJson());

    expect(restored.role, OnboardingRole.coach);
    expect(restored.goal, OnboardingGoal.tournament);
    expect(restored.focus, OnboardingFocus.defense);
    expect(restored.pushLevel, OnboardingPushLevel.max);
    expect(restored.workoutRemindersEnabled, isTrue);
    expect(restored.completedAt, DateTime(2026, 6, 12, 9));
    expect(restored.lastWorkoutCompletedAt, DateTime(2026, 6, 13, 19, 30));
  });
}
