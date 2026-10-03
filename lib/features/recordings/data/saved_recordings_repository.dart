part of '../saved_recordings_provider.dart';

class SavedRecordingsRepository {
  static const keySavedRecordings = 'saved_workout_videos_v1';

  final SharedPreferences prefs;

  const SavedRecordingsRepository(this.prefs);

  List<SavedWorkoutVideo> loadVideos() {
    final raw = prefs.getString(keySavedRecordings);
    if (raw == null) return [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((map) => SavedWorkoutVideo.fromMap(
              Map<String, dynamic>.from(map),
            ))
        .where((video) => video.id.isNotEmpty && video.path.isNotEmpty)
        .toList();
  }

  Future<void> saveVideos(List<SavedWorkoutVideo> videos) {
    return prefs.setString(
      keySavedRecordings,
      jsonEncode(videos.map((video) => video.toMap()).toList()),
    );
  }
}
