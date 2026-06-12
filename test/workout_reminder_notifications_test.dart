import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/onboarding/onboarding.dart';
import 'package:shot_stance_sprawl/features/onboarding/workout_reminder_notifications.dart';

void main() {
  OnboardingProfile profile({
    OnboardingRole role = OnboardingRole.wrestler,
    OnboardingGoal goal = OnboardingGoal.dailyPractice,
    OnboardingFocus focus = OnboardingFocus.offense,
    OnboardingPushLevel pushLevel = OnboardingPushLevel.hard,
  }) {
    return OnboardingProfile(
      role: role,
      goal: goal,
      focus: focus,
      pushLevel: pushLevel,
      workoutRemindersEnabled: true,
      completedAt: DateTime(2026, 6, 12, 8),
    );
  }

  test('day seven reminder uses the stop message', () {
    final copy = workoutReminderCopyFor(
      profile: profile(),
      reminderDay: 7,
    );

    expect(copy.title, "We'll pause reminders");
    expect(copy.body, workoutReminderFinalBody);
  });

  test('reminders keep the workout completion time of day', () {
    final scheduledAt = workoutReminderScheduledAt(
      completedAt: DateTime(2026, 6, 12, 20, 8, 30),
      reminderDay: 4,
    );

    expect(scheduledAt, DateTime(2026, 6, 16, 20, 8, 30));
  });

  test('reminder copy reflects onboarding answers', () {
    final copy = workoutReminderCopyFor(
      profile: profile(
        role: OnboardingRole.parent,
        goal: OnboardingGoal.tournament,
        focus: OnboardingFocus.conditioning,
        pushLevel: OnboardingPushLevel.max,
      ),
      reminderDay: 3,
    );

    expect(copy.title, 'Gas tank check');
    expect(copy.body, contains('Help your wrestler'));
    expect(copy.body, contains('Tournament prep'));
    expect(copy.body, contains('Max intensity'));
  });
}
