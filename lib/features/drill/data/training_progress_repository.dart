import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class TrainingProgressRepository {
  static const keyTrainingProgress = 'training_progress_v1';

  final SharedPreferences prefs;

  const TrainingProgressRepository(this.prefs);

  TrainingProgress? loadProgress() {
    final jsonString = prefs.getString(keyTrainingProgress);
    return jsonString == null ? null : TrainingProgress.fromJson(jsonString);
  }

  Future<void> saveProgress(TrainingProgress progress) {
    return prefs.setString(keyTrainingProgress, progress.toJson());
  }
}
