part of '../onboarding.dart';

class OnboardingRepository {
  static const keyOnboardingProfile = 'onboarding_profile_v1';

  final SharedPreferences prefs;

  const OnboardingRepository(this.prefs);

  OnboardingProfile? loadProfile() {
    final jsonString = prefs.getString(keyOnboardingProfile);
    return jsonString == null ? null : OnboardingProfile.fromJson(jsonString);
  }

  Future<void> saveProfile(OnboardingProfile profile) {
    return prefs.setString(keyOnboardingProfile, profile.toJson());
  }
}
