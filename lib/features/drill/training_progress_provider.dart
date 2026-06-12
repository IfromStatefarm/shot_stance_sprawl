import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../badges/badge_progress_provider.dart';
import 'models.dart';

final trainingProgressProvider =
    NotifierProvider<TrainingProgressNotifier, TrainingProgress>(() {
  return TrainingProgressNotifier();
});

class TrainingProgressNotifier extends Notifier<TrainingProgress> {
  static const _keyTrainingProgress = 'training_progress_v1';

  @override
  TrainingProgress build() {
    _load();
    return TrainingProgress.initial();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_keyTrainingProgress);

      if (jsonString != null) {
        state = TrainingProgress.fromJson(jsonString);
      } else {
        await prefs.setString(_keyTrainingProgress, state.toJson());
      }
    } catch (e) {
      debugPrint('Error loading training progress: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTrainingProgress, state.toJson());
  }

  Future<void> addSession({
    required Map<String, int> callouts,
    required int stanceSeconds,
    DateTime? at,
  }) async {
    state = state.addSession(
      callouts: callouts,
      stanceSeconds: stanceSeconds,
      at: at,
    );
    await _save();
  }

  Future<void> setStateDate(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    state = state.copyWith(
      stateDate: targetDate,
    );
    await _save();
    await ref.read(badgeProgressProvider.notifier).markSeasonTargetSet(
          targetDate,
        );
  }
}
