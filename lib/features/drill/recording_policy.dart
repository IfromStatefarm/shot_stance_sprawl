import 'models.dart';

class RecordingPolicy {
  static const int freeRecordingLimitSeconds = 60;
  static const int proRecordingLimitSeconds = 600;
  static const int unrestrictedUiLimitSeconds = 900;

  static int recordingLimitSeconds({required bool isPro}) {
    return isPro ? proRecordingLimitSeconds : freeRecordingLimitSeconds;
  }

  static int effectiveTotalDurationSeconds({
    required DrillConfig config,
    required bool isPro,
  }) {
    if (!config.videoEnabled) return config.totalDurationSeconds;

    final limit = recordingLimitSeconds(isPro: isPro);
    if (config.totalDurationSeconds <= limit) {
      return config.totalDurationSeconds;
    }
    return limit;
  }

  static DrillConfig effectiveConfig({
    required DrillConfig config,
    required bool isPro,
  }) {
    return config.copyWith(
      totalDurationSeconds: effectiveTotalDurationSeconds(
        config: config,
        isPro: isPro,
      ),
    );
  }

  static bool isDurationLimited({
    required DrillConfig config,
    required bool isPro,
  }) {
    return effectiveTotalDurationSeconds(config: config, isPro: isPro) <
        config.totalDurationSeconds;
  }
}
