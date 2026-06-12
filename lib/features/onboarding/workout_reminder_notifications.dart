import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'onboarding.dart';

const int workoutReminderFinalDay = 7;
const String workoutReminderFinalBody =
    "These reminders don't seem to be working. We'll stop sending them for now.";

final workoutReminderNotificationsProvider =
    Provider<WorkoutReminderNotifications>((_) {
  return WorkoutReminderNotifications.instance;
});

@immutable
class WorkoutReminderNotificationCopy {
  final String title;
  final String body;

  const WorkoutReminderNotificationCopy({
    required this.title,
    required this.body,
  });
}

@visibleForTesting
WorkoutReminderNotificationCopy workoutReminderCopyFor({
  required OnboardingProfile profile,
  required int reminderDay,
}) {
  if (reminderDay >= workoutReminderFinalDay) {
    return const WorkoutReminderNotificationCopy(
      title: "We'll pause reminders",
      body: workoutReminderFinalBody,
    );
  }

  final title = switch (profile.focus) {
    OnboardingFocus.offense => 'Sharpen your attacks',
    OnboardingFocus.defense => 'Build the wall',
    OnboardingFocus.conditioning => 'Gas tank check',
    OnboardingFocus.handfight => 'Win the ties',
  };

  final roleLine = switch (profile.role) {
    OnboardingRole.wrestler =>
      'You chose ${profile.focus.label.toLowerCase()}.',
    OnboardingRole.coach => 'Keep the room moving.',
    OnboardingRole.parent => 'Help your wrestler get one short session in.',
  };

  final goalLine = switch (profile.goal) {
    OnboardingGoal.dailyPractice => 'One short drill keeps the habit alive.',
    OnboardingGoal.tournament =>
      'Tournament prep is built one clean rep at a time.',
    OnboardingGoal.season => 'Season goals are built on today\'s reps.',
  };

  final pushLine = switch (profile.pushLevel) {
    OnboardingPushLevel.build => 'Smooth first, then speed.',
    OnboardingPushLevel.hard => 'Push hard for a few focused minutes.',
    OnboardingPushLevel.max => 'Max intensity: move first and keep pressure.',
  };

  return WorkoutReminderNotificationCopy(
    title: title,
    body: '$roleLine $goalLine $pushLine',
  );
}

@visibleForTesting
DateTime workoutReminderScheduledAt({
  required DateTime completedAt,
  required int reminderDay,
}) {
  return _sameLocalTimeDaysAfter(completedAt, reminderDay);
}

class WorkoutReminderNotifications {
  WorkoutReminderNotifications({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final WorkoutReminderNotifications instance =
      WorkoutReminderNotifications();

  static const int _firstReminderId = 780100;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'snap_go_workout_reminders',
      'Workout reminders',
      channelDescription:
          'Daily Snap & Go workout reminders after your last workout.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _timeZoneInitialized = false;

  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      await _configureLocalTimezone();
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings: initializationSettings);
      _initialized = true;
      return true;
    } catch (error, stackTrace) {
      debugPrint('[notifications] Unable to initialize reminders: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> scheduleAfterWorkoutCompletion({
    required OnboardingProfile profile,
    required DateTime completedAt,
  }) async {
    if (!profile.workoutRemindersEnabled) {
      await cancelWorkoutReminders();
      return;
    }

    final ready = await initialize();
    if (!ready) return;

    try {
      await _cancelWorkoutRemindersInternal();
      final now = DateTime.now();

      for (var day = 1; day <= workoutReminderFinalDay; day++) {
        final scheduledAt = workoutReminderScheduledAt(
          completedAt: completedAt,
          reminderDay: day,
        );
        if (!scheduledAt.isAfter(now)) {
          continue;
        }

        final copy = workoutReminderCopyFor(
          profile: profile,
          reminderDay: day,
        );
        await _plugin.zonedSchedule(
          id: _firstReminderId + day,
          title: copy.title,
          body: copy.body,
          scheduledDate: tz.TZDateTime(
            tz.local,
            scheduledAt.year,
            scheduledAt.month,
            scheduledAt.day,
            scheduledAt.hour,
            scheduledAt.minute,
            scheduledAt.second,
          ),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'workout-reminder:$day',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[notifications] Unable to schedule reminders: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> cancelWorkoutReminders() async {
    final ready = await initialize();
    if (!ready) return;

    try {
      await _cancelWorkoutRemindersInternal();
    } catch (error, stackTrace) {
      debugPrint('[notifications] Unable to cancel reminders: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _cancelWorkoutRemindersInternal() async {
    for (var day = 1; day <= workoutReminderFinalDay; day++) {
      await _plugin.cancel(id: _firstReminderId + day);
    }
  }

  Future<void> _configureLocalTimezone() async {
    if (_timeZoneInitialized) return;

    tzdata.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (error) {
      debugPrint('[notifications] Falling back to default timezone: $error');
    }
    _timeZoneInitialized = true;
  }
}

DateTime _sameLocalTimeDaysAfter(DateTime source, int days) {
  final targetDate =
      DateTime(source.year, source.month, source.day).add(Duration(days: days));
  return DateTime(
    targetDate.year,
    targetDate.month,
    targetDate.day,
    source.hour,
    source.minute,
    source.second,
  );
}
