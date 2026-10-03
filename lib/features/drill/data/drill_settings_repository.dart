import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class LanguageRepository {
  static const keyLanguage = 'language_code';

  final SharedPreferences prefs;

  const LanguageRepository(this.prefs);

  String? loadLanguage() => prefs.getString(keyLanguage);

  Future<void> saveLanguage(String languageCode) {
    return prefs.setString(keyLanguage, languageCode);
  }
}

class CalloutButtonStyleRepository {
  static const keyCalloutButtonStyle = 'callout_button_style';

  final SharedPreferences prefs;

  const CalloutButtonStyleRepository(this.prefs);

  String? loadStyleName() => prefs.getString(keyCalloutButtonStyle);

  Future<void> saveStyleName(String styleName) {
    return prefs.setString(keyCalloutButtonStyle, styleName);
  }
}

class DrillConfigRepository {
  static const keyConfig = 'drill_config_v1';

  final SharedPreferences prefs;

  const DrillConfigRepository(this.prefs);

  DrillConfig? loadConfig() {
    final jsonString = prefs.getString(keyConfig);
    return jsonString == null ? null : DrillConfig.fromJson(jsonString);
  }

  Future<void> saveConfig(DrillConfig config) {
    return prefs.setString(keyConfig, config.toJson());
  }
}

class UserProfileRepository {
  static const keyWeight = 'user_weight';
  static const keyTeam = 'user_team';
  static const keyAge = 'user_age';
  static const keyImage = 'user_profile_image';

  final SharedPreferences prefs;

  const UserProfileRepository(this.prefs);

  UserProfile loadProfile({
    UserProfile fallback = const UserProfile(
      id: 'local_user',
      weightLbs: 150.0,
    ),
  }) {
    return fallback.copyWith(
      weightLbs: prefs.getDouble(keyWeight) ?? 150.0,
      teamName: prefs.getString(keyTeam),
      age: prefs.getInt(keyAge) ?? 18,
      profileImageUrl: prefs.getString(keyImage),
    );
  }

  Future<void> saveWeight(double weightLbs) {
    return prefs.setDouble(keyWeight, weightLbs);
  }

  Future<void> saveTeam(String teamName) {
    return prefs.setString(keyTeam, teamName);
  }

  Future<void> saveAge(int age) {
    return prefs.setInt(keyAge, age);
  }

  Future<void> saveProfileImage(String path) {
    return prefs.setString(keyImage, path);
  }
}
