import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/recordings/saved_recordings_provider.dart';

void main() {
  test('review video file names include user, callouts, date, and time', () {
    final name = SavedWorkoutVideoFileNames.fileName(
      userName: 'Jordan Smith',
      calloutsCompleted: 17,
      savedAt: DateTime(2026, 4, 5, 20, 8, 30),
    );

    expect(name, 'Snap_go_Jordan_Smith_17_callouts_Apr_05_2026_8-08-30_PM.mp4');
  });

  test('review video file names sanitize missing or unsafe names', () {
    final name = SavedWorkoutVideoFileNames.fileName(
      userName: 'Team: A/B',
      calloutsCompleted: -4,
      savedAt: DateTime(2026, 12, 1, 0, 3, 2),
    );

    expect(name, 'Snap_go_Team_A_B_0_callouts_Dec_01_2026_12-03-02_AM.mp4');
  });
}
