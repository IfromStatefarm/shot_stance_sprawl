import 'package:shared_preferences/shared_preferences.dart';

import '../badge_models.dart';

class BadgeProgressRepository {
  static const keyBadgeProgress = 'badge_progress_v1';

  final SharedPreferences prefs;

  const BadgeProgressRepository(this.prefs);

  BadgeProgressState? loadProgress() {
    final jsonString = prefs.getString(keyBadgeProgress);
    return jsonString == null ? null : BadgeProgressState.fromJson(jsonString);
  }

  Future<void> saveProgress(BadgeProgressState progress) {
    return prefs.setString(keyBadgeProgress, progress.toJson());
  }
}
