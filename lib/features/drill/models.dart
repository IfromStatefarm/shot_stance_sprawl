// models.dart
import 'package:flutter/foundation.dart';
import 'dart:convert';

@immutable
class UserProfile {
  final String id;
  final String? activeVoicePackId;
  final double weightLbs;
  final int age;
  final String? teamName;
  final String? profileImageUrl;

  const UserProfile({
    required this.id,
    this.activeVoicePackId,
    this.weightLbs = 150.0,
    this.age = 18,
    this.teamName,
    this.profileImageUrl,
  });

  UserProfile copyWith({
    String? id,
    String? activeVoicePackId,
    double? weightLbs,
    int? age,
    String? teamName,
    String? profileImageUrl,
  }) {
    return UserProfile(
      id: id ?? this.id,
      activeVoicePackId: activeVoicePackId ?? this.activeVoicePackId,
      weightLbs: weightLbs ?? this.weightLbs,
      age: age ?? this.age,
      teamName: teamName ?? this.teamName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  double get weightKg => weightLbs * 0.453592;

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      activeVoicePackId: data['activeVoicePackId'] as String?,
      weightLbs: (data['weightLbs'] as num?)?.toDouble() ?? 150.0,
      age: (data['age'] as num?)?.toInt() ?? 18,
      teamName: data['teamName'] as String?,
      profileImageUrl: data['profileImageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'activeVoicePackId': activeVoicePackId,
      'weightLbs': weightLbs,
      'age': age,
      'teamName': teamName,
      'profileImageUrl': profileImageUrl,
    };
  }
}

@immutable
class VoicePack {
  final String id;
  final String name;
  final String languageCode;
  final String languageName;
  final String attribution;
  final String ownerId;
  final bool isCustom;
  final Map<String, String> calloutAssets;
  final Map<String, String> adLibAssets;
  final String whistleAsset;

  const VoicePack({
    required this.id,
    required this.name,
    required this.languageCode,
    required this.languageName,
    this.attribution = '',
    this.ownerId = '',
    this.isCustom = false,
    required this.calloutAssets,
    required this.adLibAssets,
    required this.whistleAsset,
  });

  factory VoicePack.fromMap(String id, Map<String, dynamic> data) {
    Map<String, String> stringMap(Object? value) => value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value.toString()))
        : const {};

    return VoicePack(
      id: id,
      name: (data['name'] as String?) ?? 'Untitled',
      languageCode: (data['languageCode'] as String?) ?? 'en',
      languageName: (data['languageName'] as String?) ?? 'English',
      attribution: (data['attribution'] as String?) ?? '',
      ownerId: (data['ownerId'] as String?) ?? '',
      isCustom: (data['isCustom'] as bool?) ?? false,
      calloutAssets: stringMap(data['callouts']),
      adLibAssets: stringMap(data['adLibs']),
      whistleAsset: (data['whistle'] as String?) ?? '',
    );
  }
}

@immutable
class Callout {
  final String id;
  final String nameEn;
  final String nameEs;
  final String type;
  final int defaultDurationSeconds;
  final String? audioUrl;
  final bool isCustom;
  final String? audioAssetAlias;

  const Callout({
    required this.id,
    required this.nameEn,
    required this.nameEs,
    required this.type,
    this.defaultDurationSeconds = 0,
    this.audioUrl,
    this.isCustom = false,
    this.audioAssetAlias,
  });

  // ADDED: copyWith to allow renaming custom callouts
  Callout copyWith({
    String? id,
    String? nameEn,
    String? nameEs,
    String? type,
    int? defaultDurationSeconds,
    String? audioUrl,
    bool? isCustom,
    String? audioAssetAlias,
  }) {
    return Callout(
      id: id ?? this.id,
      nameEn: nameEn ?? this.nameEn,
      nameEs: nameEs ?? this.nameEs,
      type: type ?? this.type,
      defaultDurationSeconds:
          defaultDurationSeconds ?? this.defaultDurationSeconds,
      audioUrl: audioUrl ?? this.audioUrl,
      isCustom: isCustom ?? this.isCustom,
      audioAssetAlias: audioAssetAlias ?? this.audioAssetAlias,
    );
  }

  String get name => nameEn;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nameEn': nameEn,
      'nameEs': nameEs,
      'type': type,
      'defaultDurationSeconds': defaultDurationSeconds,
      'audioUrl': audioUrl,
      'isCustom': isCustom,
      'audioAssetAlias': audioAssetAlias,
    };
  }

  factory Callout.fromMap(String id, Map<String, dynamic> data) {
    final rawDur = data['defaultDurationSeconds'] ?? data['durationSeconds'];

    return Callout(
      id: data['id'] ?? id,
      nameEn:
          (data['nameEn'] as String?) ?? (data['name'] as String?) ?? 'Callout',
      nameEs:
          (data['nameEs'] as String?) ?? (data['name'] as String?) ?? 'Comando',
      type: (data['type'] as String?) ?? 'Movement',
      defaultDurationSeconds: (rawDur as num?)?.toInt() ?? 0,
      audioUrl: data['audioUrl'] as String?,
      isCustom: (data['isCustom'] as bool?) ?? false,
      audioAssetAlias: data['audioAssetAlias'] as String?,
    );
  }

  factory Callout.fromJson(Map<String, dynamic> json) =>
      Callout.fromMap(json['id'] ?? 'unknown', json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Callout && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class TrainingProgress {
  final Map<String, int> calloutCounts;
  final int stanceSeconds;
  final Map<String, int> repsByDate;
  final Map<String, int> sessionsByDate;
  final DateTime? stateDate;

  const TrainingProgress({
    this.calloutCounts = const {},
    this.stanceSeconds = 0,
    this.repsByDate = const {},
    this.sessionsByDate = const {},
    this.stateDate,
  });

  factory TrainingProgress.initial({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return TrainingProgress(
      stateDate: today.add(const Duration(days: 90)),
    );
  }

  TrainingProgress copyWith({
    Map<String, int>? calloutCounts,
    int? stanceSeconds,
    Map<String, int>? repsByDate,
    Map<String, int>? sessionsByDate,
    DateTime? stateDate,
  }) {
    return TrainingProgress(
      calloutCounts: calloutCounts ?? this.calloutCounts,
      stanceSeconds: stanceSeconds ?? this.stanceSeconds,
      repsByDate: repsByDate ?? this.repsByDate,
      sessionsByDate: sessionsByDate ?? this.sessionsByDate,
      stateDate: stateDate ?? this.stateDate,
    );
  }

  int calloutCount(String id) => calloutCounts[id] ?? 0;

  int get stanceMinutes => stanceSeconds ~/ 60;

  int get totalCallouts =>
      calloutCounts.values.fold<int>(0, (sum, value) => sum + value);

  int repsForDate(DateTime date) => repsByDate[dateKey(date)] ?? 0;

  int sessionsForDate(DateTime date) {
    final key = dateKey(date);
    return sessionsByDate[key] ?? (repsForDate(date) > 0 ? 1 : 0);
  }

  int currentStreak({DateTime? today}) {
    if (sessionsByDate.isEmpty && repsByDate.isEmpty) return 0;

    var cursor = _dateOnly(today ?? DateTime.now());
    if (sessionsForDate(cursor) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (sessionsForDate(cursor) == 0) return 0;
    }

    var streak = 0;
    while (sessionsForDate(cursor) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  int? daysUntilState({DateTime? today}) {
    final target = stateDate;
    if (target == null) return null;

    final start = _dateOnly(today ?? DateTime.now());
    final finish = _dateOnly(target);
    final days = finish.difference(start).inDays;
    return days < 0 ? 0 : days;
  }

  TrainingProgress addSession({
    required Map<String, int> callouts,
    required int stanceSeconds,
    DateTime? at,
  }) {
    final nextCalloutCounts = Map<String, int>.from(calloutCounts);
    var sessionReps = 0;

    for (final entry in callouts.entries) {
      if (entry.value <= 0) continue;
      nextCalloutCounts[entry.key] =
          (nextCalloutCounts[entry.key] ?? 0) + entry.value;
      sessionReps += entry.value;
    }

    final nextRepsByDate = Map<String, int>.from(repsByDate);
    if (sessionReps > 0) {
      final key = dateKey(at ?? DateTime.now());
      nextRepsByDate[key] = (nextRepsByDate[key] ?? 0) + sessionReps;
    }
    final nextSessionsByDate = Map<String, int>.from(sessionsByDate);
    final key = dateKey(at ?? DateTime.now());
    nextSessionsByDate[key] = (nextSessionsByDate[key] ?? 0) + 1;

    return copyWith(
      calloutCounts: nextCalloutCounts,
      stanceSeconds: this.stanceSeconds + stanceSeconds,
      repsByDate: nextRepsByDate,
      sessionsByDate: nextSessionsByDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'calloutCounts': calloutCounts,
      'stanceSeconds': stanceSeconds,
      'repsByDate': repsByDate,
      'sessionsByDate': sessionsByDate,
      'stateDate': stateDate == null ? null : dateKey(stateDate!),
    };
  }

  String toJson() => json.encode(toMap());

  factory TrainingProgress.fromJson(String source) =>
      TrainingProgress.fromMap(json.decode(source) as Map<String, dynamic>);

  factory TrainingProgress.fromMap(Map<String, dynamic> map) {
    final rawStateDate = map['stateDate'] as String?;
    final parsedStateDate =
        rawStateDate == null ? null : DateTime.tryParse(rawStateDate);

    return TrainingProgress(
      calloutCounts: _decodeIntMap(map['calloutCounts']),
      stanceSeconds: (map['stanceSeconds'] as num?)?.toInt() ?? 0,
      repsByDate: _decodeIntMap(map['repsByDate']),
      sessionsByDate: _decodeIntMap(map['sessionsByDate']),
      stateDate: parsedStateDate == null ? null : _dateOnly(parsedStateDate),
    );
  }

  static String dateKey(DateTime date) {
    final local = _dateOnly(date);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static Map<String, int> _decodeIntMap(Object? source) {
    if (source is! Map) return {};

    return source.map(
      (key, value) => MapEntry(
        key.toString(),
        (value as num?)?.toInt() ?? 0,
      ),
    );
  }
}

const Map<String, int> _legacyHandFightDurations = {
  'hand_fight_15': 15,
  'hand_fight_30': 30,
  'hand_fight_45': 45,
  'hand_fight_60': 60,
};

const Object _drillConfigUnset = Object();

@immutable
class DrillConfig {
  static const defaultVoicePackId = 'default_en';

  final int totalDurationSeconds;
  final double minIntervalSeconds;
  final double maxIntervalSeconds;
  final Set<String> enabledCalloutIds;
  final Map<String, String> customAudioPaths;
  final Map<String, String> customAdLibAudioPaths;
  final Map<String, int> calloutOverrideDurations;
  final bool videoEnabled;
  final bool adLibsEnabled;
  final String? activeWorkoutPresetId;
  final String voicePackId;

  const DrillConfig({
    this.totalDurationSeconds = 60,
    this.minIntervalSeconds = 2.0,
    this.maxIntervalSeconds = 4.0,
    this.enabledCalloutIds = const {},
    this.customAudioPaths = const {},
    this.customAdLibAudioPaths = const {},
    this.calloutOverrideDurations = const {},
    this.videoEnabled = false,
    this.adLibsEnabled = false,
    this.activeWorkoutPresetId,
    this.voicePackId = defaultVoicePackId,
  });

  /// Creates a detached, deeply immutable copy for one running session.
  ///
  /// `DrillConfig` is immutable at the field level, but callers may supply
  /// mutable sets and maps. Capturing them here prevents later settings edits
  /// from changing the workout recorded for a completed session.
  factory DrillConfig.immutableSnapshot(DrillConfig source) {
    return DrillConfig(
      totalDurationSeconds: source.totalDurationSeconds,
      minIntervalSeconds: source.minIntervalSeconds,
      maxIntervalSeconds: source.maxIntervalSeconds,
      enabledCalloutIds: Set<String>.unmodifiable(source.enabledCalloutIds),
      customAudioPaths:
          Map<String, String>.unmodifiable(source.customAudioPaths),
      customAdLibAudioPaths:
          Map<String, String>.unmodifiable(source.customAdLibAudioPaths),
      calloutOverrideDurations:
          Map<String, int>.unmodifiable(source.calloutOverrideDurations),
      videoEnabled: source.videoEnabled,
      adLibsEnabled: source.adLibsEnabled,
      activeWorkoutPresetId: source.activeWorkoutPresetId,
      voicePackId: source.voicePackId,
    );
  }

  double get metValue {
    if (maxIntervalSeconds <= 2.0) return 11.5;
    if (maxIntervalSeconds <= 4.0) return 8.5;
    return 6.0;
  }

  DrillConfig copyWith({
    int? totalDurationSeconds,
    double? minIntervalSeconds,
    double? maxIntervalSeconds,
    Set<String>? enabledCalloutIds,
    Map<String, String>? customAudioPaths,
    Map<String, String>? customAdLibAudioPaths,
    Map<String, int>? calloutOverrideDurations,
    bool? videoEnabled,
    bool? adLibsEnabled,
    Object? activeWorkoutPresetId = _drillConfigUnset,
    String? voicePackId,
  }) {
    return DrillConfig(
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      minIntervalSeconds: minIntervalSeconds ?? this.minIntervalSeconds,
      maxIntervalSeconds: maxIntervalSeconds ?? this.maxIntervalSeconds,
      enabledCalloutIds: enabledCalloutIds ?? this.enabledCalloutIds,
      customAudioPaths: customAudioPaths ?? this.customAudioPaths,
      customAdLibAudioPaths:
          customAdLibAudioPaths ?? this.customAdLibAudioPaths,
      calloutOverrideDurations:
          calloutOverrideDurations ?? this.calloutOverrideDurations,
      videoEnabled: videoEnabled ?? this.videoEnabled,
      adLibsEnabled: adLibsEnabled ?? this.adLibsEnabled,
      activeWorkoutPresetId: identical(activeWorkoutPresetId, _drillConfigUnset)
          ? this.activeWorkoutPresetId
          : activeWorkoutPresetId as String?,
      voicePackId: voicePackId ?? this.voicePackId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalDurationSeconds': totalDurationSeconds,
      'minIntervalSeconds': minIntervalSeconds,
      'maxIntervalSeconds': maxIntervalSeconds,
      'enabledCalloutIds': enabledCalloutIds.toList(),
      'customAudioPaths': customAudioPaths,
      'customAdLibAudioPaths': customAdLibAudioPaths,
      'calloutOverrideDurations': calloutOverrideDurations,
      'videoEnabled': videoEnabled,
      'adLibsEnabled': adLibsEnabled,
      'activeWorkoutPresetId': activeWorkoutPresetId,
      'voicePackId': voicePackId,
    };
  }

  factory DrillConfig.fromMap(Map<String, dynamic> map) {
    final enabledCalloutIds = Set<String>.from(map['enabledCalloutIds'] ?? []);
    final customAudioPaths =
        Map<String, String>.from(map['customAudioPaths'] ?? {});
    final calloutOverrideDurations =
        Map<String, int>.from(map['calloutOverrideDurations'] ?? {});

    int? migratedHandFightDuration;
    for (final entry in _legacyHandFightDurations.entries) {
      final oldId = entry.key;
      if (enabledCalloutIds.remove(oldId)) {
        enabledCalloutIds.add('hand_fight');
        migratedHandFightDuration =
            calloutOverrideDurations[oldId] ?? entry.value;
      }

      if (customAudioPaths.containsKey(oldId) &&
          !customAudioPaths.containsKey('hand_fight')) {
        customAudioPaths['hand_fight'] = customAudioPaths[oldId]!;
      }

      calloutOverrideDurations.remove(oldId);
      customAudioPaths.remove(oldId);
    }

    if (migratedHandFightDuration != null &&
        !calloutOverrideDurations.containsKey('hand_fight')) {
      calloutOverrideDurations['hand_fight'] = migratedHandFightDuration;
    }

    return DrillConfig(
      totalDurationSeconds: map['totalDurationSeconds']?.toInt() ?? 60,
      minIntervalSeconds: map['minIntervalSeconds']?.toDouble() ?? 2.0,
      maxIntervalSeconds: map['maxIntervalSeconds']?.toDouble() ?? 4.0,
      enabledCalloutIds: enabledCalloutIds,
      customAudioPaths: customAudioPaths,
      customAdLibAudioPaths:
          Map<String, String>.from(map['customAdLibAudioPaths'] ?? {}),
      calloutOverrideDurations: calloutOverrideDurations,
      videoEnabled: map['videoEnabled'] ?? false,
      adLibsEnabled: map['adLibsEnabled'] ?? false,
      activeWorkoutPresetId: map['activeWorkoutPresetId'] as String?,
      voicePackId:
          map['voicePackId'] as String? ?? DrillConfig.defaultVoicePackId,
    );
  }

  String toJson() => json.encode(toMap());

  factory DrillConfig.fromJson(String source) =>
      DrillConfig.fromMap(json.decode(source));
}
