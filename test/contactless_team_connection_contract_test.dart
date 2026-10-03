import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team connections do not ship contact matching or contacts access', () {
    final accountRepository =
        File('lib/features/account/account_repository.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final androidManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final iosPodfile = File('ios/Podfile').readAsStringSync();

    expect(accountRepository, isNot(contains('registerVerifiedPhone')));
    expect(accountRepository, isNot(contains('matchContacts')));
    expect(pubspec, isNot(contains('flutter_contacts')));
    expect(androidManifest, isNot(contains('android.permission.READ_CONTACTS')));
    expect(iosInfo, isNot(contains('NSContactsUsageDescription')));
    expect(iosPodfile, isNot(contains('PERMISSION_CONTACTS=1')));
  });
}
