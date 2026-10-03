import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/social/social.dart';

void main() {
  test('all social push types route to their workout share', () {
    for (final type in SocialPushNotificationType.values) {
      final notification = SocialPushNotification.fromData({
        'type': type.wireName,
        'shareId': 'share-123',
      });

      expect(notification, isNotNull);
      expect(notification!.type, type);
      expect(notification.shareId, 'share-123');
      expect(
        notification.deepLink.toString(),
        'snapandgo://workout/share-123',
      );
    }
  });

  test('prototype workout-share pushes remain routable', () {
    final notification = SocialPushNotification.fromData({
      'type': 'workout_share',
      'shareId': 'legacy-share',
    });

    expect(notification?.type, SocialPushNotificationType.workoutReceived);
  });

  test('workout app links parse without accepting the workout', () {
    final notification = SocialPushNotification.fromUri(
      Uri.parse('snapandgo://workout/share-123'),
    );

    expect(notification?.shareId, 'share-123');
    expect(
      SocialPushNotification.fromUri(
        Uri.parse('snapandgo://friend/jordan'),
      ),
      isNull,
    );
  });

  test('malformed notification data is ignored', () {
    expect(
      SocialPushNotification.fromData({
        'type': 'unknown',
        'shareId': 'share-123',
      }),
      isNull,
    );
    expect(
      SocialPushNotification.fromData({
        'type': 'workout_completed',
        'shareId': '',
      }),
      isNull,
    );
  });
}
