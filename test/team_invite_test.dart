import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/social/team_sheet.dart';

void main() {
  test('team text invite includes the supplied copy, app URL, and code', () {
    final message = teamInviteMessage('ABCD-1234-5678');
    expect(message, startsWith('You say you want to get better. Prove it.'));
    expect(
        message,
        contains(
            'Train your stance, shots, sprawls, and wrestling skills anywhere...'));
    expect(
      message,
      contains('https://keepkidswrestling.com/Snap-and-go/'),
    );
    expect(message, contains('Enter team code: ABCD-1234-5678'));
    expect(message, endsWith('No excuses. No spectators. Get better.'));
  });
}
