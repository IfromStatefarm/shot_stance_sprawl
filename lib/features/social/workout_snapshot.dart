import 'package:flutter/foundation.dart';

import '../drill/models.dart';
import '../drill/workout_presets.dart';

enum WorkoutSnapshotSourceType {
  preset,
  custom;

  static WorkoutSnapshotSourceType fromFirestore(Object? value) {
    return values.firstWhere(
      (sourceType) => sourceType.name == value,
      orElse: () => WorkoutSnapshotSourceType.custom,
    );
  }
}

/// Portable custom-workout choices that should follow the workout to a friend.
///
/// Most runnable configuration lives in the snapshot's strongly typed timing
/// and callout fields. This nested object is intentionally allowlisted so a
/// future `DrillConfig` field cannot accidentally expose device-local data.
@immutable
class CustomWorkoutConfiguration {
  const CustomWorkoutConfiguration({this.adLibsEnabled = false});

  final bool adLibsEnabled;

  factory CustomWorkoutConfiguration.fromFirestore(Object? value) {
    final map = _stringMap(value);
    return CustomWorkoutConfiguration(
      adLibsEnabled: map['adLibsEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'adLibsEnabled': adLibsEnabled,
      };
}

/// An immutable, versioned workout definition embedded in a workout share.
///
/// Version 2 is the canonical shape. [fromFirestore] migrates both the
/// unversioned prototype and Step 4's version 1 documents before constructing
/// this model. Local paths, recordings, video, and device preferences are
/// never read into or written from this type.
@immutable
class WorkoutSnapshot {
  const WorkoutSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.titleEn,
    required this.titleEs,
    required this.sourceType,
    this.presetId,
    required this.durationSeconds,
    required this.difficulty,
    required this.minIntervalSeconds,
    required this.maxIntervalSeconds,
    required this.enabledCalloutIds,
    required this.timedCalloutDurations,
    this.customWorkoutConfiguration,
    this.purposeEn = '',
    this.purposeEs = '',
    this.category = 'custom',
  });

  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final String titleEn;
  final String titleEs;
  final WorkoutSnapshotSourceType sourceType;
  final String? presetId;
  final int durationSeconds;
  final int difficulty;
  final double minIntervalSeconds;
  final double maxIntervalSeconds;
  final List<String> enabledCalloutIds;
  final Map<String, int> timedCalloutDurations;
  final CustomWorkoutConfiguration? customWorkoutConfiguration;
  final String purposeEn;
  final String purposeEs;
  final String category;

  /// Captures a preset and resolves timed callout ranges once, making the
  /// shared workout deterministic for every recipient.
  factory WorkoutSnapshot.fromPreset(
    WorkoutPreset preset, {
    DrillConfig? config,
    Map<String, int>? timedCalloutDurations,
  }) {
    final calloutIds = (config?.enabledCalloutIds ?? preset.calloutIds)
        .toList(growable: false);
    final resolvedDurations = timedCalloutDurations ??
        (config == null
            ? preset.resolveTimedCalloutDurations()
            : config.calloutOverrideDurations);
    return WorkoutSnapshot(
      titleEn: preset.titleEn,
      titleEs: preset.titleEs,
      sourceType: WorkoutSnapshotSourceType.preset,
      presetId: preset.id,
      durationSeconds:
          config?.totalDurationSeconds ?? preset.recommendedDurationSeconds,
      difficulty: preset.recommendedDifficulty,
      minIntervalSeconds: config?.minIntervalSeconds ?? 2,
      maxIntervalSeconds: config?.maxIntervalSeconds ?? 4,
      enabledCalloutIds: List<String>.unmodifiable(calloutIds),
      timedCalloutDurations: Map<String, int>.unmodifiable({
        for (final entry in resolvedDurations.entries)
          if (calloutIds.contains(entry.key)) entry.key: entry.value,
      }),
      purposeEn: preset.purposeEn,
      purposeEs: preset.purposeEs,
      category: preset.category.name,
    );
  }

  /// Captures the portable portion of a completed or custom drill.
  factory WorkoutSnapshot.fromDrillConfig(
    DrillConfig drillConfig, {
    required String title,
    String? titleEs,
    String purposeEn = 'Shared custom workout',
    String purposeEs = 'Entrenamiento personalizado compartido',
    String category = 'custom',
    int? difficulty,
  }) {
    final calloutIds = drillConfig.enabledCalloutIds.toList(growable: false);
    final presetId = _nonEmptyString(drillConfig.activeWorkoutPresetId);
    final sourceType = presetId == null
        ? WorkoutSnapshotSourceType.custom
        : WorkoutSnapshotSourceType.preset;
    return WorkoutSnapshot(
      titleEn: title.trim(),
      titleEs: (titleEs ?? title).trim(),
      sourceType: sourceType,
      presetId: presetId,
      durationSeconds: drillConfig.totalDurationSeconds,
      difficulty:
          difficulty ?? _difficultyForIntervals(drillConfig.maxIntervalSeconds),
      minIntervalSeconds: drillConfig.minIntervalSeconds,
      maxIntervalSeconds: drillConfig.maxIntervalSeconds,
      enabledCalloutIds: List<String>.unmodifiable(calloutIds),
      timedCalloutDurations: Map<String, int>.unmodifiable({
        for (final entry in drillConfig.calloutOverrideDurations.entries)
          if (calloutIds.contains(entry.key)) entry.key: entry.value,
      }),
      customWorkoutConfiguration: sourceType == WorkoutSnapshotSourceType.custom
          ? CustomWorkoutConfiguration(
              adLibsEnabled: drillConfig.adLibsEnabled,
            )
          : null,
      purposeEn: purposeEn.trim(),
      purposeEs: purposeEs.trim(),
      category: category.trim(),
    );
  }

  /// Reads and migrates an embedded Firestore workout map.
  factory WorkoutSnapshot.fromFirestore(Object? value) {
    final migrated = _WorkoutSnapshotMigration.toCurrent(_stringMap(value));
    final title = _stringMap(migrated['title']);
    final purpose = _stringMap(migrated['purpose']);
    final intervalRange = _stringMap(migrated['intervalRange']);
    final sourceType = WorkoutSnapshotSourceType.fromFirestore(
      migrated['sourceType'],
    );
    final customConfiguration = migrated['customWorkoutConfiguration'];
    return WorkoutSnapshot(
      titleEn: title['en'] as String? ?? 'Shared workout',
      titleEs: title['es'] as String? ??
          title['en'] as String? ??
          'Entrenamiento compartido',
      sourceType: sourceType,
      presetId: sourceType == WorkoutSnapshotSourceType.preset
          ? _nonEmptyString(migrated['presetId'])
          : null,
      durationSeconds: (migrated['durationSeconds'] as num?)?.toInt() ?? 60,
      difficulty: (migrated['difficulty'] as num?)?.toInt() ?? 5,
      minIntervalSeconds:
          (intervalRange['minSeconds'] as num?)?.toDouble() ?? 2,
      maxIntervalSeconds:
          (intervalRange['maxSeconds'] as num?)?.toDouble() ?? 4,
      enabledCalloutIds: List<String>.unmodifiable(
        _stringList(migrated['enabledCalloutIds']),
      ),
      timedCalloutDurations: Map<String, int>.unmodifiable(
        _intMap(migrated['timedCalloutDurations']),
      ),
      customWorkoutConfiguration: sourceType == WorkoutSnapshotSourceType.custom
          ? CustomWorkoutConfiguration.fromFirestore(customConfiguration)
          : null,
      purposeEn: purpose['en'] as String? ?? '',
      purposeEs: purpose['es'] as String? ?? purpose['en'] as String? ?? '',
      category: migrated['category'] as String? ?? 'custom',
    );
  }

  /// Compatibility name for callers created with the Step 4 model.
  factory WorkoutSnapshot.fromMap(Object? value) =>
      WorkoutSnapshot.fromFirestore(value);

  /// Compatibility constructor for the Step 4 custom-workout API.
  factory WorkoutSnapshot.fromCustom({
    required DrillConfig config,
    required String title,
    String? purpose,
  }) {
    return WorkoutSnapshot.fromDrillConfig(
      config,
      title: title,
      purposeEn: purpose ?? 'Shared custom workout',
      purposeEs: purpose ?? 'Entrenamiento personalizado compartido',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'schemaVersion': currentSchemaVersion,
        'title': {'en': titleEn, 'es': titleEs},
        'sourceType': sourceType.name,
        if (presetId != null) 'presetId': presetId,
        'durationSeconds': durationSeconds,
        'difficulty': difficulty,
        'intervalRange': {
          'minSeconds': minIntervalSeconds,
          'maxSeconds': maxIntervalSeconds,
        },
        'enabledCalloutIds': enabledCalloutIds,
        'timedCalloutDurations': timedCalloutDurations,
        if (customWorkoutConfiguration != null)
          'customWorkoutConfiguration':
              customWorkoutConfiguration!.toFirestore(),
        'purpose': {'en': purposeEn, 'es': purposeEs},
        'category': category,
      };

  /// Compatibility name retained for the Step 4 repository API.
  Map<String, dynamic> toMap() => toFirestore();

  /// Rebuilds a runnable config using only portable fields.
  DrillConfig toDrillConfig() => DrillConfig(
        totalDurationSeconds: durationSeconds,
        minIntervalSeconds: minIntervalSeconds,
        maxIntervalSeconds: maxIntervalSeconds,
        enabledCalloutIds: enabledCalloutIds.toSet(),
        calloutOverrideDurations: Map<String, int>.from(timedCalloutDurations),
        adLibsEnabled: customWorkoutConfiguration?.adLibsEnabled ?? false,
        activeWorkoutPresetId: presetId,
      );

  // Step 4 field aliases keep downstream UI code source compatible.
  int get totalDurationSeconds => durationSeconds;
  List<String> get calloutIds => enabledCalloutIds;
  Map<String, int> get calloutOverrideDurations => timedCalloutDurations;
}

abstract final class _WorkoutSnapshotMigration {
  static Map<String, dynamic> toCurrent(Map<String, dynamic> source) {
    final version = (source['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > WorkoutSnapshot.currentSchemaVersion) {
      throw FormatException('Unsupported workout snapshot version $version.');
    }
    var migrated = Map<String, dynamic>.from(source);
    if (version < 1) migrated = _unversionedToV1(migrated);
    if (version < 2) migrated = _v1ToV2(migrated);
    migrated['schemaVersion'] = WorkoutSnapshot.currentSchemaVersion;
    return migrated;
  }

  static Map<String, dynamic> _unversionedToV1(Map<String, dynamic> source) {
    final intervalRange = _stringMap(source['intervalRange']);
    return {
      'schemaVersion': 1,
      'titleEn': source['titleEn'] ?? source['workoutTitle'] ?? source['title'],
      'titleEs': source['titleEs'],
      'purposeEn': source['purposeEn'] ?? source['purpose'],
      'purposeEs': source['purposeEs'],
      'category': source['category'] ?? 'custom',
      'presetId': source['presetId'] ?? source['activeWorkoutPresetId'],
      'totalDurationSeconds':
          source['totalDurationSeconds'] ?? source['durationSeconds'],
      'minIntervalSeconds':
          source['minIntervalSeconds'] ?? intervalRange['minSeconds'],
      'maxIntervalSeconds':
          source['maxIntervalSeconds'] ?? intervalRange['maxSeconds'],
      'calloutIds': source['calloutIds'] ?? source['enabledCalloutIds'],
      'calloutOverrideDurations':
          source['calloutOverrideDurations'] ?? source['timedCalloutDurations'],
      'difficulty': source['difficulty'],
      'adLibsEnabled': source['adLibsEnabled'],
      'customWorkoutConfiguration': source['customWorkoutConfiguration'],
    };
  }

  static Map<String, dynamic> _v1ToV2(Map<String, dynamic> source) {
    final category = source['category'] as String? ?? 'custom';
    final presetId = _nonEmptyString(
      source['presetId'] ?? source['activeWorkoutPresetId'],
    );
    final sourceType = source['sourceType'] as String? ??
        (presetId != null || category != 'custom' ? 'preset' : 'custom');
    final customConfiguration = source['customWorkoutConfiguration'] ??
        source['customConfiguration'] ??
        {'adLibsEnabled': source['adLibsEnabled'] as bool? ?? false};
    return {
      'schemaVersion': 2,
      'title': {
        'en': source['titleEn'] as String? ?? 'Shared workout',
        'es': source['titleEs'] as String? ??
            source['titleEn'] as String? ??
            'Entrenamiento compartido',
      },
      'sourceType': sourceType,
      if (presetId != null) 'presetId': presetId,
      'durationSeconds': source['totalDurationSeconds'] ?? 60,
      'difficulty': source['difficulty'] ?? 5,
      'intervalRange': {
        'minSeconds': source['minIntervalSeconds'] ?? 2,
        'maxSeconds': source['maxIntervalSeconds'] ?? 4,
      },
      'enabledCalloutIds': source['calloutIds'] ?? const <String>[],
      'timedCalloutDurations':
          source['calloutOverrideDurations'] ?? const <String, int>{},
      if (sourceType == 'custom')
        'customWorkoutConfiguration': customConfiguration,
      'purpose': {
        'en': source['purposeEn'] as String? ?? '',
        'es': source['purposeEs'] as String? ??
            source['purposeEn'] as String? ??
            '',
      },
      'category': category,
    };
  }
}

String workoutSourceKeyForPreset(WorkoutPreset preset) => 'preset:${preset.id}';

String newCustomWorkoutSourceKey(DateTime createdAt) =>
    'custom:${createdAt.toUtc().microsecondsSinceEpoch}';

int _difficultyForIntervals(double maxIntervalSeconds) {
  if (maxIntervalSeconds <= 1.5) return 10;
  if (maxIntervalSeconds <= 2) return 8;
  if (maxIntervalSeconds <= 4) return 5;
  return 2;
}

String? _nonEmptyString(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<String> _stringList(Object? value) => value is Iterable
    ? value.whereType<String>().toList(growable: false)
    : const [];

Map<String, int> _intMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
  );
}
