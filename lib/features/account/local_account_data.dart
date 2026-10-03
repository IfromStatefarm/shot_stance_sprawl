import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAccountData {
  static const linkedUidKey = 'account_local_progress_linked_uid_v1';

  static const _exportedKeys = <String>{
    'language_code',
    'callout_button_style',
    'drill_config_v1',
    'user_weight',
    'user_team',
    'user_age',
    'training_progress_v1',
    'badge_progress_v1',
    'onboarding_profile_v1',
    'custom_callouts_v1',
    'saved_workout_videos_v1',
  };

  final SharedPreferences prefs;

  const LocalAccountData(this.prefs);

  bool isLinkedTo(String uid) => prefs.getString(linkedUidKey) == uid;

  Future<void> markLinkedTo(String uid) => prefs.setString(linkedUidKey, uid);

  Map<String, dynamic> snapshot() {
    final data = <String, dynamic>{};
    for (final key in _exportedKeys) {
      if (!prefs.containsKey(key)) continue;
      final value = prefs.get(key);
      data[key] = value is String ? _decodeIfJson(value) : value;
    }

    return {
      'schemaVersion': 1,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
  }

  /// A cloud-safe subset used to attach existing progress to an account.
  /// Device file paths, recordings, custom audio, and purchases stay local.
  Map<String, dynamic> progressSnapshot() {
    const progressKeys = <String>{
      'user_weight',
      'user_team',
      'user_age',
      'training_progress_v1',
      'badge_progress_v1',
      'onboarding_profile_v1',
    };
    final data = <String, dynamic>{};
    for (final key in progressKeys) {
      if (!prefs.containsKey(key)) continue;
      final value = prefs.get(key);
      data[key] = value is String ? _decodeIfJson(value) : value;
    }
    return data;
  }

  Future<File> writeExportFile(Map<String, dynamic> remoteData) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final file = File('${directory.path}/snap-and-go-export-$timestamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'local': snapshot(),
        'account': remoteData,
      }),
      flush: true,
    );
    return file;
  }

  static dynamic _decodeIfJson(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }
}
