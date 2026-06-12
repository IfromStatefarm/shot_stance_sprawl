import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final savedRecordingsProvider =
    AsyncNotifierProvider<SavedRecordingsNotifier, List<SavedWorkoutVideo>>(
  SavedRecordingsNotifier.new,
);

@immutable
class SavedWorkoutVideo {
  final String id;
  final String path;
  final DateTime createdAt;
  final int durationSeconds;
  final int calloutsCompleted;

  const SavedWorkoutVideo({
    required this.id,
    required this.path,
    required this.createdAt,
    required this.durationSeconds,
    required this.calloutsCompleted,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'createdAt': createdAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'calloutsCompleted': calloutsCompleted,
    };
  }

  factory SavedWorkoutVideo.fromMap(Map<String, dynamic> map) {
    final rawDate = map['createdAt'] as String?;
    return SavedWorkoutVideo(
      id: map['id'] as String? ?? '',
      path: map['path'] as String? ?? '',
      createdAt: rawDate == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse(rawDate) ??
              DateTime.fromMillisecondsSinceEpoch(0),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      calloutsCompleted: (map['calloutsCompleted'] as num?)?.toInt() ?? 0,
    );
  }
}

class SavedRecordingsNotifier extends AsyncNotifier<List<SavedWorkoutVideo>> {
  static const _keySavedRecordings = 'saved_workout_videos_v1';

  @override
  Future<List<SavedWorkoutVideo>> build() async {
    return _loadVideos();
  }

  Future<SavedWorkoutVideo?> saveWorkoutVideo({
    required String sourcePath,
    required Duration duration,
    required int calloutsCompleted,
    String? userName,
    DateTime? createdAt,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final savedAt = createdAt ?? DateTime.now();
    final id = savedAt.microsecondsSinceEpoch.toString();
    final destination = await _recordingFileFor(
      savedAt,
      userName: userName,
      calloutsCompleted: calloutsCompleted,
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);

    final video = SavedWorkoutVideo(
      id: id,
      path: destination.path,
      createdAt: savedAt,
      durationSeconds: duration.inSeconds,
      calloutsCompleted: calloutsCompleted,
    );
    final current = [...(state.value ?? await _loadVideos())];
    final next = [video, ...current]..sort(_newestFirst);
    state = AsyncValue.data(next);
    await _saveVideos(next);
    return video;
  }

  Future<void> deleteVideo(String id) async {
    final current = [...(state.value ?? await _loadVideos())];
    final target = current.where((video) => video.id == id).firstOrNull;
    if (target != null) {
      try {
        final file = File(target.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting saved workout video: $e');
      }
    }

    final next = current.where((video) => video.id != id).toList();
    state = AsyncValue.data(next);
    await _saveVideos(next);
  }

  Future<void> refreshLibrary() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _loadVideos());
  }

  Future<List<SavedWorkoutVideo>> _loadVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySavedRecordings);
      if (raw == null) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final videos = decoded
          .whereType<Map>()
          .map((map) => SavedWorkoutVideo.fromMap(
                Map<String, dynamic>.from(map),
              ))
          .where((video) => video.id.isNotEmpty && video.path.isNotEmpty)
          .toList();
      final existing = <SavedWorkoutVideo>[];
      for (final video in videos) {
        if (await File(video.path).exists()) {
          existing.add(video);
        }
      }
      existing.sort(_newestFirst);
      if (existing.length != videos.length) {
        await _saveVideos(existing);
      }
      return existing;
    } catch (e) {
      debugPrint('Error loading saved workout videos: $e');
      return [];
    }
  }

  Future<void> _saveVideos(List<SavedWorkoutVideo> videos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keySavedRecordings,
      jsonEncode(videos.map((video) => video.toMap()).toList()),
    );
  }

  Future<File> _recordingFileFor(
    DateTime savedAt, {
    required String? userName,
    required int calloutsCompleted,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}recordings');
    final baseName = SavedWorkoutVideoFileNames.fileName(
      userName: userName,
      calloutsCompleted: calloutsCompleted,
      savedAt: savedAt,
    );
    var candidate = File('${dir.path}${Platform.pathSeparator}$baseName');
    var suffix = 2;
    while (await candidate.exists()) {
      candidate = File(
        '${dir.path}${Platform.pathSeparator}'
        '${baseName.replaceFirst('.mp4', '_$suffix.mp4')}',
      );
      suffix++;
    }
    return candidate;
  }

  static int _newestFirst(SavedWorkoutVideo a, SavedWorkoutVideo b) {
    return b.createdAt.compareTo(a.createdAt);
  }
}

class SavedWorkoutVideoFileNames {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  const SavedWorkoutVideoFileNames._();

  static String fileName({
    required String? userName,
    required int calloutsCompleted,
    required DateTime savedAt,
  }) {
    final name = safeFileComponent(userName, fallback: 'Wrestler');
    final month = _months[savedAt.month - 1];
    final day = _two(savedAt.day);
    final year = savedAt.year.toString();
    final time = _time(savedAt);
    final calloutTotal = calloutsCompleted < 0 ? 0 : calloutsCompleted;

    return 'Snap_go_${name}_${calloutTotal}_callouts_'
        '${month}_${day}_${year}_$time.mp4';
  }

  static String safeFileComponent(String? value, {required String fallback}) {
    final sanitized = (value ?? '')
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return sanitized.isEmpty ? fallback : sanitized;
  }

  static String _time(DateTime date) {
    final isPm = date.hour >= 12;
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '$hour-${_two(date.minute)}-${_two(date.second)}_'
        '${isPm ? 'PM' : 'AM'}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
