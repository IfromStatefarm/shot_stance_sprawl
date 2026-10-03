import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shot_stance_sprawl/features/account/account.dart';

void main() {
  group('account error messages', () {
    test('identifies Google Android configuration failures', () {
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
      );

      expect(
        accountErrorMessage(error),
        'Google sign-in is not configured for this Android build.',
      );
    });

    test('identifies profile permission failures', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );

      expect(
        accountErrorMessage(error),
        'Your account connected, but its profile could not be created.',
      );
    });
  });

  group('username validation', () {
    test('normalizes case and surrounding whitespace', () {
      expect(normalizeUsername('  Snap_Wrestler  '), 'snap_wrestler');
    });

    test('accepts the public username format', () {
      expect(isValidUsername('snap_go_24'), isTrue);
      expect(isValidUsername('abc'), isTrue);
    });

    test('rejects unsafe or ambiguous usernames', () {
      expect(isValidUsername('ab'), isFalse);
      expect(isValidUsername('has spaces'), isFalse);
      expect(isValidUsername('phone+15551234'), isFalse);
      expect(isValidUsername('this_username_is_too_long'), isFalse);
    });
  });

  group('friend invite links', () {
    test('parses QR app links', () {
      final uri = AccountInviteLinks.appLink('Snap_Wrestler');
      expect(AccountInviteLinks.usernameFromUri(uri), 'snap_wrestler');
    });

    test('parses shared web links', () {
      final uri = AccountInviteLinks.webLink('snap_go_24');
      expect(
        uri.toString(),
        'https://keepkidswrestling.com/Snap-and-go/invite?username=snap_go_24',
      );
      expect(AccountInviteLinks.usernameFromUri(uri), 'snap_go_24');
    });

    test('ignores unrelated or malformed links', () {
      expect(
        AccountInviteLinks.usernameFromUri(Uri.parse('https://example.com/x')),
        isNull,
      );
      expect(
        AccountInviteLinks.usernameFromUri(Uri.parse('snapandgo://friend/a!')),
        isNull,
      );
    });
  });
}
