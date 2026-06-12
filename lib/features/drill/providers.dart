import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../billing/pro_purchase.dart';
import '../../data/repositories.dart';
import 'models.dart';
import 'drill_engine.dart';

export 'models.dart';
export 'drill_engine.dart';
export '../billing/pro_purchase.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

final languageProvider = StateProvider<String>((ref) => 'en');

final proPurchaseProvider =
    NotifierProvider<ProPurchaseController, ProPurchaseState>(() {
  return ProPurchaseController();
});

final isProProvider = Provider<bool>((ref) {
  return ref.watch(proPurchaseProvider.select((state) => state.isPro));
});

final drillConfigProvider = NotifierProvider<DrillConfigNotifier, DrillConfig>(() {
  return DrillConfigNotifier();
});

class DrillConfigNotifier extends Notifier<DrillConfig> {
  static const _keyConfig = 'drill_config_v1';

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

  Future<void> _load() async {
    try {
      final prefs = await ref.read(sharedPrefsProvider.future);
      final jsonString = prefs.getString(_keyConfig);
      
      if (jsonString != null) {
        state = DrillConfig.fromJson(jsonString);
      }
    } catch (e) {
      debugPrint("Error loading drill config: $e");
    }
  }

  Future<void> _save() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyConfig, state.toJson());
  }
  
  void setCalloutDuration(String id, int duration) {
    final map = Map<String, int>.from(state.calloutOverrideDurations);
    map[id] = duration;
    state = state.copyWith(calloutOverrideDurations: map);
    _save();
  }
  
  void toggleCallout(String id, {required bool enabled}) {
    final ids = Set<String>.from(state.enabledCalloutIds);
    if (enabled) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    state = state.copyWith(enabledCalloutIds: ids);
    _save();
  }

  void setIntervalRange({required double minSeconds, required double maxSeconds}) {
    state = state.copyWith(minIntervalSeconds: minSeconds, maxIntervalSeconds: maxSeconds);
    _save();
  }

  void setTotalDurationSeconds(int seconds) {
    state = state.copyWith(totalDurationSeconds: seconds);
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

final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});

class UserProfileNotifier extends Notifier<UserProfile> {
  static const _keyWeight = 'user_weight';
  static const _keyTeam = 'user_team';
  static const _keyAge = 'user_age';
  static const _keyImage = 'user_profile_image';

  @override
  UserProfile build() {
    _loadPersistence();
    return const UserProfile(id: 'local_user', weightLbs: 150.0);
  }

  Future<void> _loadPersistence() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    final savedWeight = prefs.getDouble(_keyWeight) ?? 150.0;
    final savedTeam = prefs.getString(_keyTeam);
    final savedAge = prefs.getInt(_keyAge) ?? 18;
    final savedImage = prefs.getString(_keyImage);
    
    state = state.copyWith(
      weightLbs: savedWeight,
      teamName: savedTeam,
      age: savedAge,
      profileImageUrl: savedImage,
    );
  }

  Future<void> updateWeight(double newWeight) async {
    state = state.copyWith(weightLbs: newWeight);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setDouble(_keyWeight, newWeight);
  }

  Future<void> updateTeam(String teamName) async {
    state = state.copyWith(teamName: teamName);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyTeam, teamName);
  }

  Future<void> updateAge(int newAge) async {
    state = state.copyWith(age: newAge);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setInt(_keyAge, newAge);
  }

  Future<void> updateProfileImage(String path) async {
    state = state.copyWith(profileImageUrl: path);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyImage, path);
  }
}

final drillEngineProvider = NotifierProvider<DrillEngineNotifier, DrillState>(() {
  return DrillEngineNotifier();
});

final calloutsProvider = AsyncNotifierProvider<CalloutsNotifier, List<Callout>>(() {
  return CalloutsNotifier();
});

class CalloutsNotifier extends AsyncNotifier<List<Callout>> {
  final List<Callout> _defaults = [
    const Callout(id: 'shot', nameEn: 'Shot', nameEs: 'Tiro', type: 'Movement', audioAssetAlias: 'Shot'),
    const Callout(id: 'sprawl', nameEn: 'Sprawl', nameEs: 'Sprawl', type: 'Movement', audioAssetAlias: 'Sprawl'),
    const Callout(id: 'stance', nameEn: 'Stance', nameEs: 'Postura', type: 'Duration', defaultDurationSeconds: 15, audioAssetAlias: 'Stance'),
    const Callout(id: 'circle', nameEn: 'Circle/Spin', nameEs: 'Círculo/Giro', type: 'Movement', audioAssetAlias: 'Circle'), 
    const Callout(id: 'down_block', nameEn: 'Down Block', nameEs: 'Bloqueo Abajo', type: 'Movement', audioAssetAlias: 'Down_Block'),
    const Callout(id: 'fake', nameEn: 'Fake', nameEs: 'Finta', type: 'Movement', audioAssetAlias: 'Fake'),
    const Callout(id: 'level_change', nameEn: 'Level Change', nameEs: 'Cambio de Nivel', type: 'Movement', audioAssetAlias: 'Level_Change'),
    const Callout(id: 'snap_down', nameEn: 'Snap Down', nameEs: 'Jalón', type: 'Movement', audioAssetAlias: 'Snap_Down'),
    const Callout(id: 'high_knees', nameEn: 'High Knees', nameEs: 'Rodillas Altas', type: 'Duration', defaultDurationSeconds: 15, audioAssetAlias: 'High_Knees'),
    const Callout(id: 'foot_fire', nameEn: 'Foot Fire', nameEs: 'Fuego Pies', type: 'Duration', defaultDurationSeconds: 5, audioAssetAlias: 'Foot_Fire'),
    const Callout(id: 'hand_fight', nameEn: 'Hand Fight', nameEs: 'Manos', type: 'Duration', defaultDurationSeconds: 15, audioAssetAlias: 'Hand_Fight'),
  ];

  @override
  Future<List<Callout>> build() async {
    final prefs = await ref.watch(sharedPrefsProvider.future);
    
    // Utilize the newly unified repository
    final repo = LocalCalloutRepository(prefs);
    final customCallouts = repo.getCustomCallouts();

    return [..._defaults, ...customCallouts];
  }

  Future<void> addCustomCallout(Callout newCallout) async {
    final currentList = state.value ?? _defaults;
    state = AsyncValue.data([...currentList, newCallout]);
    await _saveToDisk();
  }

  Future<void> deleteCallout(String id) async {
    final currentList = state.value ?? _defaults;
    final updatedList = currentList.where((c) => c.id != id).toList();
    state = AsyncValue.data(updatedList);
    await _saveToDisk();
  }

  Future<void> updateCalloutName(String id, String newName) async {
    final currentList = state.value ?? _defaults;
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

final calloutsForActivePackProvider = FutureProvider<List<Callout>>((ref) async {
  return ref.watch(calloutsProvider.future);
});
