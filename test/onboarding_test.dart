import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/compliance/compliance.dart';
import 'package:shot_stance_sprawl/features/onboarding/onboarding.dart';
import 'package:shot_stance_sprawl/features/onboarding/season_schedule.dart';

void main() {
  test('age eligibility keeps connected features behind the 13+ selection', () {
    expect(AgeEligibility.under13.allowsConnectedFeatures, isFalse);
    expect(AgeEligibility.thirteenOrOlder.allowsConnectedFeatures, isTrue);
    expect(
      AgeEligibility.values.map((value) => value.label),
      containsAll(<String>['Under 13', '13 or older']),
    );
  });

  test('onboarding profile serializes selected answers', () {
    final profile = OnboardingProfile(
      stateName: 'Iowa',
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
    expect(restored.stateName, 'Iowa');
    expect(restored.goal, OnboardingGoal.tournament);
    expect(restored.focus, OnboardingFocus.defense);
    expect(restored.pushLevel, OnboardingPushLevel.max);
    expect(restored.workoutRemindersEnabled, isTrue);
    expect(restored.completedAt, DateTime(2026, 6, 12, 9));
    expect(restored.lastWorkoutCompletedAt, DateTime(2026, 6, 13, 19, 30));
  });

  test('season calendar includes all states and rolls through the year', () {
    expect(seasonDatesByState.length, 50);
    expect(seasonDatesByState['Vermont']!.seasonStart, DateTime(2026, 12, 6));
    for (final dates in seasonDatesByState.values) {
      expect(dates.seasonStart.isBefore(dates.postseasonStart), isTrue,
          reason: dates.state);
      expect(
          dates.postseasonStart.add(const Duration(days: 21)).isBefore(DateTime(
              dates.seasonStart.year + 1,
              dates.seasonStart.month,
              dates.seasonStart.day)),
          isTrue,
          reason: dates.state);
    }

    SeasonCountdown at(DateTime day) => countdownForState('Iowa', day);
    expect(at(DateTime(2026, 11, 29)).phase, SeasonCountdownPhase.seasonStart);
    expect(at(DateTime(2026, 11, 29)).daysRemaining, 1);
    expect(at(DateTime(2026, 11, 30)).isToday, isTrue);
    expect(
        at(DateTime(2026, 12, 1)).phase, SeasonCountdownPhase.postseasonStart);
    expect(at(DateTime(2027, 2, 13)).isToday, isTrue);
    expect(at(DateTime(2027, 2, 14)).phase, SeasonCountdownPhase.postseasonEnd);
    expect(at(DateTime(2027, 2, 14)).daysRemaining, 20);
    expect(at(DateTime(2027, 3, 6)).isToday, isTrue);
    expect(at(DateTime(2027, 3, 7)).targetDate, DateTime.utc(2027, 11, 30));
    expect(
        at(DateTime(2028, 2, 13)).phase, SeasonCountdownPhase.postseasonStart);
  });

  test('same-calendar-year postseason and local calendar days work', () {
    expect(countdownForState('Alaska', DateTime(2026, 12, 12)).isToday, isTrue);
    expect(countdownForState('Alaska', DateTime(2027, 1, 2)).phase,
        SeasonCountdownPhase.postseasonEnd);
    expect(countdownForState('Alaska', DateTime(2027, 1, 3)).targetDate,
        DateTime.utc(2027, 10, 15));
    expect(
        countdownForState('Iowa', DateTime(2026, 11, 29, 23, 59)).daysRemaining,
        1);
  });
}
