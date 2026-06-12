import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/drill/models.dart';

/// Stores user-created callout metadata locally.
class LocalCalloutRepository {
  static const _keyCustomCallouts = 'custom_callouts_v1';
  final SharedPreferences prefs;

  LocalCalloutRepository(this.prefs);

  /// Retrieves the list of custom callouts saved locally
  List<Callout> getCustomCallouts() {
    final jsonString = prefs.getString(_keyCustomCallouts);
    if (jsonString == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((e) => Callout.fromJson(e)).toList();
    } catch (e) {
      // Return empty gracefully if local data is corrupted
      return [];
    }
  }

  /// Persists the custom callouts to device storage.
  Future<void> saveCustomCallouts(List<Callout> callouts) async {
    // Ensure we only save the custom ones, not the hardcoded defaults
    final customOnly = callouts.where((c) => c.isCustom).toList();
    final jsonString = jsonEncode(customOnly.map((c) => c.toMap()).toList());

    await prefs.setString(_keyCustomCallouts, jsonString);
  }
}

