import 'package:flutter/foundation.dart';

enum SocialPushNotificationType {
  workoutReceived('workout_received'),
  workoutAccepted('workout_accepted'),
  workoutCompleted('workout_completed'),
  fistBump('fist_bump'),
  scheduledWorkoutReminder('scheduled_workout_reminder');

  const SocialPushNotificationType(this.wireName);

  final String wireName;

  static SocialPushNotificationType? fromWireName(Object? value) {
    final name = value?.toString().trim();
    for (final type in values) {
      if (type.wireName == name) return type;
    }
    // Accept the Step 10 prototype payload during the rollout.
    if (name == 'workout_share') return workoutReceived;
    return null;
  }
}

@immutable
class SocialPushNotification {
  const SocialPushNotification({
    required this.type,
    required this.shareId,
  });

  final SocialPushNotificationType type;
  final String shareId;

  Uri get deepLink => Uri(
        scheme: 'snapandgo',
        host: 'workout',
        pathSegments: [shareId],
      );

  static SocialPushNotification? fromData(Map<String, dynamic> data) {
    final type = SocialPushNotificationType.fromWireName(data['type']);
    final shareId = data['shareId']?.toString().trim() ?? '';
    if (type == null || shareId.isEmpty || shareId.length > 128) return null;
    return SocialPushNotification(type: type, shareId: shareId);
  }

  static SocialPushNotification? fromUri(Uri uri) {
    if (uri.scheme != 'snapandgo' || uri.host != 'workout') return null;
    if (uri.pathSegments.length != 1) return null;
    final shareId = uri.pathSegments.single.trim();
    if (shareId.isEmpty || shareId.length > 128) return null;
    // A URI identifies the destination. The originating push type does not
    // affect navigation or mutate the workout lifecycle.
    return SocialPushNotification(
      type: SocialPushNotificationType.workoutReceived,
      shareId: shareId,
    );
  }
}
