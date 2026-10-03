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

  test('friend workout notification IDs are stable per share', () {
    expect(
      sharedWorkoutNotificationId('share-a'),
      sharedWorkoutNotificationId('share-a'),
    );
    expect(
      sharedWorkoutNotificationId('share-a'),
      isNot(sharedWorkoutNotificationId('share-b')),
    );
  });

  test('friend workout reminder uses a ten-minute lead when possible', () {
    final now = DateTime(2026, 8, 11, 17);
    expect(
      sharedWorkoutReminderAt(
        DateTime(2026, 8, 11, 18),
        now: now,
      ),
      DateTime(2026, 8, 11, 17, 50),
    );
    expect(
      sharedWorkoutReminderAt(
        DateTime(2026, 8, 11, 17, 5),
        now: now,
      ),
      DateTime(2026, 8, 11, 17, 5),
    );
  });

  test('friend workout reminder identifies the workout and sender', () {
    final copy = sharedWorkoutReminderCopy(
      workoutTitle: 'Shot chain',
      senderName: 'Jordan',
      isEs: false,
    );

    expect(copy.title, 'Your workout starts soon');
    expect(copy.body, contains('Shot chain'));
    expect(copy.body, contains('Jordan'));
  });

  test('friend reminder taps carry a view-only payload', () {
    expect(
      sharedWorkoutNotificationPayload('share-a'),
      'shared-workout:view:share-a',
    );
    expect(
      sharedWorkoutIdFromNotificationPayload(
        sharedWorkoutNotificationPayload('share-a'),
      ),
      'share-a',
    );
    expect(
        sharedWorkoutIdFromNotificationPayload('workout-reminder:1'), isNull);
  });
}
