import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../billing/pro_purchase.dart';
import '../badges/badge_progress_provider.dart';
import '../../data/repositories.dart';
import 'data/default_callouts.dart';
import 'data/drill_settings_repository.dart';
import 'languages.dart';
import 'models.dart';
import 'drill_engine.dart';
import 'workout_presets.dart';
import 'voice_packs.dart';

export 'models.dart';
export 'languages.dart';
export 'drill_engine.dart';
export 'training_progress_provider.dart';
export 'workout_presets.dart';
export 'voice_packs.dart';
export '../badges/badge_progress_provider.dart';
export '../billing/pro_purchase.dart';

const _presetTimedCalloutIds = {
  'stance',
  'hand_fight',
  'high_knees',
  'foot_fire',
};

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

final languageProvider = NotifierProvider<LanguageNotifier, String>(() {
  return LanguageNotifier();
});

class LanguageNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'en';
  }

  Future<LanguageRepository> _repository() async {
    return LanguageRepository(await ref.read(sharedPrefsProvider.future));
  }

  Future<void> _load() async {
    try {
      final saved = (await _repository()).loadLanguage();
      if (saved != null && isSupportedAppLanguage(saved)) {
        state = saved;
      }
    } catch (e) {
      debugPrint('Error loading language: $e');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (!isSupportedAppLanguage(languageCode)) {
      return;
    }

    state = languageCode;
    await (await _repository()).saveLanguage(languageCode);
  }
}

enum CalloutButtonStyle {
  classic,
  modern,
}

final calloutButtonStyleProvider =
    NotifierProvider<CalloutButtonStyleNotifier, CalloutButtonStyle>(() {
  return CalloutButtonStyleNotifier();
});

class CalloutButtonStyleNotifier extends Notifier<CalloutButtonStyle> {
  @override
  CalloutButtonStyle build() {
    _load();
    return CalloutButtonStyle.modern;
  }

  Future<CalloutButtonStyleRepository> _repository() async {
    return CalloutButtonStyleRepository(
      await ref.read(sharedPrefsProvider.future),
    );
  }

  Future<void> _load() async {
    try {
      final saved = (await _repository()).loadStyleName();
      if (saved == CalloutButtonStyle.classic.name) {
        state = CalloutButtonStyle.classic;
      } else if (saved == CalloutButtonStyle.modern.name) {
        state = CalloutButtonStyle.modern;
      }
    } catch (e) {
      debugPrint('Error loading callout button style: $e');
    }
  }

  Future<void> setStyle(CalloutButtonStyle style) async {
    state = style;
    await (await _repository()).saveStyleName(style.name);
  }
}

final proPurchaseProvider =
    NotifierProvider<ProPurchaseController, ProPurchaseState>(() {
  return ProPurchaseController();
});

final dailyMissionProvider = Provider<WorkoutPreset>((ref) {
  return workoutPresetForDate(DateTime.now());
});

final isProProvider = Provider<bool>((ref) {
  return ref.watch(proPurchaseProvider.select((state) => state.isPro));
});

final voicePacksProvider = FutureProvider<List<VoicePack>>((ref) {
  return const VoicePackCatalog().load();
});

final drillConfigProvider =
    NotifierProvider<DrillConfigNotifier, DrillConfig>(() {
  return DrillConfigNotifier();
});

class DrillConfigNotifier extends Notifier<DrillConfig> {
  @override
  DrillConfig build() {
    _load();
    return const DrillConfig(
      totalDurationSeconds: 60,
      minIntervalSeconds: 2.0,
      maxIntervalSeconds: 4.0,
      enabledCalloutIds: {'shot', 'stance', 'sprawl'},
      videoEnabled: false,
    );
  }

  Future<DrillConfigRepository> _repository() async {
    return DrillConfigRepository(await ref.read(sharedPrefsProvider.future));
  }

  Future<void> _load() async {
    try {
      final config = (await _repository()).loadConfig();
      if (config != null) state = config;
    } catch (e) {
      debugPrint("Error loading drill config: $e");
    }
  }

  Future<void> _save() async {
    await (await _repository()).saveConfig(state);
  }

  void applySharedWorkout(DrillConfig workout) {
    state = DrillConfig.immutableSnapshot(
      workout.copyWith(
        customAudioPaths: state.customAudioPaths,
        customAdLibAudioPaths: state.customAdLibAudioPaths,
        videoEnabled: state.videoEnabled,
        voicePackId: state.voicePackId,
      ),
    );
    _save();
  }

  void setCalloutDuration(String id, int duration) {
    final map = Map<String, int>.from(state.calloutOverrideDurations);
    map[id] = duration;
    state = state.copyWith(
      calloutOverrideDurations: map,
      activeWorkoutPresetId: null,
    );
    _save();
  }

  void toggleCallout(String id, {required bool enabled}) {
    final ids = Set<String>.from(state.enabledCalloutIds);
    if (enabled) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    state = state.copyWith(
      enabledCalloutIds: ids,
      activeWorkoutPresetId: null,
    );
    _save();
  }

  void setEnabledCalloutIds(Set<String> ids) {
    state = state.copyWith(
      enabledCalloutIds: Set<String>.from(ids),
      activeWorkoutPresetId: null,
    );
    _save();
  }

  void applyWorkoutPreset(
    WorkoutPreset preset, {
    required int totalDurationSeconds,
    required double minIntervalSeconds,
    required double maxIntervalSeconds,
    bool? videoEnabled,
  }) {
    final calloutDurations = Map<String, int>.from(
      state.calloutOverrideDurations,
    )..removeWhere((id, _) => _presetTimedCalloutIds.contains(id));

    calloutDurations.addAll(preset.resolveTimedCalloutDurations());

    state = state.copyWith(
      enabledCalloutIds: preset.calloutIds.toSet(),
      totalDurationSeconds: totalDurationSeconds,
      minIntervalSeconds: minIntervalSeconds,
      maxIntervalSeconds: maxIntervalSeconds,
      calloutOverrideDurations: calloutDurations,
      videoEnabled: videoEnabled,
      activeWorkoutPresetId: preset.id,
    );
    _save();
  }

  void setIntervalRange(
      {required double minSeconds, required double maxSeconds}) {
    state = state.copyWith(
      minIntervalSeconds: minSeconds,
      maxIntervalSeconds: maxSeconds,
      activeWorkoutPresetId: null,
    );
    _save();
  }

  void setTotalDurationSeconds(int seconds) {
    state = state.copyWith(
      totalDurationSeconds: seconds,
      activeWorkoutPresetId: null,
    );
    _save();
  }

  void toggleVideo() {
    state = state.copyWith(videoEnabled: !state.videoEnabled);
    _save();
  }

  void setVideoEnabled(bool enabled) {
    state = state.copyWith(videoEnabled: enabled);
    _save();
  }

  void setAdLibsEnabled(bool enabled) {
    state = state.copyWith(adLibsEnabled: enabled);
    _save();
  }

  void setVoicePack(String voicePackId) {
    state = state.copyWith(voicePackId: voicePackId);
    _save();
  }

  void updateCalloutAudio(String id, String path) {
    final paths = Map<String, String>.from(state.customAudioPaths);
    paths[id] = path;
    state = state.copyWith(customAudioPaths: paths);
    _save();
  }

  void removeCalloutAudio(String id) {
    final paths = Map<String, String>.from(state.customAudioPaths);
    paths.remove(id);
    state = state.copyWith(customAudioPaths: paths);
    _save();
  }

  void updateAdLibAudio(String id, String path) {
    final paths = Map<String, String>.from(state.customAdLibAudioPaths);
    paths[id] = path;
    state = state.copyWith(customAdLibAudioPaths: paths);
    _save();
  }

  void removeAdLibAudio(String id) {
    final paths = Map<String, String>.from(state.customAdLibAudioPaths);
    paths.remove(id);
    state = state.copyWith(customAdLibAudioPaths: paths);
    _save();
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    _loadPersistence();
    return const UserProfile(id: 'local_user', weightLbs: 150.0);
  }

  Future<UserProfileRepository> _repository() async {
    return UserProfileRepository(await ref.read(sharedPrefsProvider.future));
  }

  Future<void> _loadPersistence() async {
    state = (await _repository()).loadProfile(fallback: state);
  }

  Future<void> updateWeight(double newWeight) async {
    state = state.copyWith(weightLbs: newWeight);
    await (await _repository()).saveWeight(newWeight);
  }

  Future<void> updateTeam(String teamName) async {
    state = state.copyWith(teamName: teamName);
    await (await _repository()).saveTeam(teamName);
  }

  Future<void> updateAge(int newAge) async {
    state = state.copyWith(age: newAge);
    await (await _repository()).saveAge(newAge);
  }

  Future<void> updateProfileImage(String path) async {
    state = state.copyWith(profileImageUrl: path);
    await (await _repository()).saveProfileImage(path);
  }
}

final drillEngineProvider =
    NotifierProvider<DrillEngineNotifier, DrillState>(() {
  return DrillEngineNotifier();
});

final calloutsProvider =
    AsyncNotifierProvider<CalloutsNotifier, List<Callout>>(() {
  return CalloutsNotifier();
});

class CalloutsNotifier extends AsyncNotifier<List<Callout>> {
  @override
  Future<List<Callout>> build() async {
    final prefs = await ref.watch(sharedPrefsProvider.future);

    // Utilize the newly unified repository
    final repo = LocalCalloutRepository(prefs);
    final customCallouts = repo.getCustomCallouts();

    return [...defaultCallouts, ...customCallouts];
  }

  Future<void> addCustomCallout(Callout newCallout) async {
    final currentList = state.value ?? defaultCallouts;
    final nextList = [...currentList, newCallout];
    state = AsyncValue.data(nextList);
    await _saveToDisk();
    final customCount = nextList.where((callout) => callout.isCustom).length;
    await ref
        .read(badgeProgressProvider.notifier)
        .recordCustomCalloutCreated(customCount);
  }

  Future<void> deleteCallout(String id) async {
    final currentList = state.value ?? defaultCallouts;
    final updatedList = currentList.where((c) => c.id != id).toList();
    state = AsyncValue.data(updatedList);
    await _saveToDisk();
  }

  Future<void> updateCalloutName(String id, String newName) async {
    final currentList = state.value ?? defaultCallouts;
    final updatedList = currentList.map((c) {
      if (c.id == id && c.isCustom) {
        return c.copyWith(nameEn: newName, nameEs: newName);
      }
      return c;
    }).toList();

    state = AsyncValue.data(updatedList);
    await _saveToDisk();
  }

  Future<void> _saveToDisk() async {
    final prefs = await ref.read(sharedPrefsProvider.future);

    // Utilize the unified repository to save
    final repo = LocalCalloutRepository(prefs);
    await repo.saveCustomCallouts(state.value ?? []);
  }
}

final calloutsForActivePackProvider =
    FutureProvider<List<Callout>>((ref) async {
  return ref.watch(calloutsProvider.future);
});
