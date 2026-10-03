import 'dart:async';

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

@immutable
class SharedWorkoutReminderCopy {
  const SharedWorkoutReminderCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

@visibleForTesting
int sharedWorkoutNotificationId(String shareId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in shareId.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
  }
  return 900000000 + (hash % 100000000);
}

@visibleForTesting
DateTime sharedWorkoutReminderAt(
  DateTime scheduledFor, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final advance = scheduledFor.subtract(const Duration(minutes: 10));
  return advance.isAfter(current) ? advance : scheduledFor;
}

@visibleForTesting
SharedWorkoutReminderCopy sharedWorkoutReminderCopy({
  required String workoutTitle,
  String? senderName,
  required bool isEs,
}) {
  final sender = senderName?.trim();
  return SharedWorkoutReminderCopy(
    title: isEs ? 'Tu workout empieza pronto' : 'Your workout starts soon',
    body: isEs
        ? '$workoutTitle${sender?.isNotEmpty == true ? ' de $sender' : ''} esta listo.'
        : '$workoutTitle${sender?.isNotEmpty == true ? ' from $sender' : ''} is ready.',
  );
}

@visibleForTesting
String sharedWorkoutNotificationPayload(String shareId) =>
    'shared-workout:view:$shareId';

@visibleForTesting
String? sharedWorkoutIdFromNotificationPayload(String? payload) {
  const prefix = 'shared-workout:view:';
  if (payload == null || !payload.startsWith(prefix)) return null;
  final shareId = payload.substring(prefix.length).trim();
  return shareId.isEmpty || shareId.length > 128 ? null : shareId;
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

  static const NotificationDetails _sharedWorkoutDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'snap_go_shared_workouts',
      'Scheduled friend workouts',
      channelDescription: 'Reminders for workouts scheduled with friends.',
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

  static const AndroidNotificationChannel _socialNotificationChannel =
      AndroidNotificationChannel(
    'snap_go_social_notifications',
    'Friend workout updates',
    description: 'Workout shares, completions, and friend reactions.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _friendWorkoutTapController =
      StreamController<String>.broadcast();
  bool _initialized = false;
  bool _timeZoneInitialized = false;
  String? _initialFriendWorkoutShareId;

  Stream<String> get friendWorkoutNotificationTaps =>
      _friendWorkoutTapController.stream;

  String? takeInitialFriendWorkoutShareId() {
    final shareId = _initialFriendWorkoutShareId;
    _initialFriendWorkoutShareId = null;
    return shareId;
  }

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
      await _plugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_socialNotificationChannel);
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _initialFriendWorkoutShareId = sharedWorkoutIdFromNotificationPayload(
          launchDetails?.notificationResponse?.payload,
        );
      }
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

  Future<bool> scheduleFriendWorkout({
    required String shareId,
    required String workoutTitle,
    required DateTime scheduledFor,
    String? senderName,
    required bool isEs,
  }) async {
    final now = DateTime.now();
    if (!scheduledFor.isAfter(now)) return false;
    final ready = await initialize();
    if (!ready) return false;

    try {
      final reminderAt = sharedWorkoutReminderAt(scheduledFor, now: now);
      final copy = sharedWorkoutReminderCopy(
        workoutTitle: workoutTitle,
        senderName: senderName,
        isEs: isEs,
      );
      await _plugin.zonedSchedule(
        id: sharedWorkoutNotificationId(shareId),
        title: copy.title,
        body: copy.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          reminderAt.year,
          reminderAt.month,
          reminderAt.day,
          reminderAt.hour,
          reminderAt.minute,
          reminderAt.second,
        ),
        notificationDetails: _sharedWorkoutDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: sharedWorkoutNotificationPayload(shareId),
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('[notifications] Unable to schedule friend workout: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> cancelFriendWorkout(String shareId) async {
    final ready = await initialize();
    if (!ready) return;

    try {
      await _plugin.cancel(id: sharedWorkoutNotificationId(shareId));
    } catch (error, stackTrace) {
      debugPrint('[notifications] Unable to cancel friend workout: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _cancelWorkoutRemindersInternal() async {
    for (var day = 1; day <= workoutReminderFinalDay; day++) {
      await _plugin.cancel(id: _firstReminderId + day);
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final shareId = sharedWorkoutIdFromNotificationPayload(response.payload);
    if (shareId == null) return;
    // Notification responses only navigate. Accepting a workout remains an
    // explicit inbox action backed by an authenticated callable.
    _friendWorkoutTapController.add(shareId);
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
