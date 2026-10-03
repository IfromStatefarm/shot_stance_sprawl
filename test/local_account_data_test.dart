import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/features/account/local_account_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud progress snapshot excludes device files and purchases', () async {
    SharedPreferences.setMockInitialValues({
      'user_weight': 142.5,
      'training_progress_v1': '{"sessions":3}',
      'saved_workout_videos_v1': '[{"path":"private/device/path.mp4"}]',
      'drill_config_v1': '{"customAudioPaths":{"shot":"secret.m4a"}}',
      'snap_go_store_entitlement_v1': true,
    });
    final data = LocalAccountData(await SharedPreferences.getInstance());

    final snapshot = data.progressSnapshot();

    expect(snapshot['user_weight'], 142.5);
    expect(snapshot['training_progress_v1'], {'sessions': 3});
    expect(snapshot, isNot(contains('saved_workout_videos_v1')));
    expect(snapshot, isNot(contains('drill_config_v1')));
    expect(snapshot, isNot(contains('snap_go_store_entitlement_v1')));
  });

  test('tracks which account received the local progress snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final data = LocalAccountData(await SharedPreferences.getInstance());

    expect(data.isLinkedTo('first-user'), isFalse);
    await data.markLinkedTo('first-user');
    expect(data.isLinkedTo('first-user'), isTrue);
    expect(data.isLinkedTo('second-user'), isFalse);
  });
}
