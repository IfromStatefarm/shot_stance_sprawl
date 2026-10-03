import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../badges/badge_progress_provider.dart';
import 'data/training_progress_repository.dart';
import 'models.dart';

final trainingProgressProvider =
    NotifierProvider<TrainingProgressNotifier, TrainingProgress>(() {
  return TrainingProgressNotifier();
});

class TrainingProgressNotifier extends Notifier<TrainingProgress> {
  @override
  TrainingProgress build() {
    _load();
    return TrainingProgress.initial();
  }

  Future<TrainingProgressRepository> _repository() async {
    return TrainingProgressRepository(await SharedPreferences.getInstance());
  }

  Future<void> _load() async {
    try {
      final repository = await _repository();
      final progress = repository.loadProgress();

      if (progress != null) {
        state = progress;
      } else {
        await repository.saveProgress(state);
      }
    } catch (e) {
      debugPrint('Error loading training progress: $e');
    }
  }

  Future<void> _save() async {
    await (await _repository()).saveProgress(state);
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
