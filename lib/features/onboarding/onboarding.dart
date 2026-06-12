import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../drill/providers.dart';

enum OnboardingRole {
  wrestler,
  coach,
  parent,
}

enum OnboardingGoal {
  dailyPractice,
  tournament,
  season,
}

enum OnboardingFocus {
  offense,
  defense,
  conditioning,
  handfight,
}

enum OnboardingPushLevel {
  build,
  hard,
  max,
}

extension OnboardingRoleText on OnboardingRole {
  String get label {
    switch (this) {
      case OnboardingRole.wrestler:
        return 'Wrestler';
      case OnboardingRole.coach:
        return 'Coach';
      case OnboardingRole.parent:
        return 'Parent';
    }
  }
}

extension OnboardingGoalText on OnboardingGoal {
  String get label {
    switch (this) {
      case OnboardingGoal.dailyPractice:
        return 'Daily practice';
      case OnboardingGoal.tournament:
        return 'Tournament';
      case OnboardingGoal.season:
        return 'Season goal';
    }
  }
}

extension OnboardingFocusText on OnboardingFocus {
  String get label {
    switch (this) {
      case OnboardingFocus.offense:
        return 'Shots and attacks';
      case OnboardingFocus.defense:
        return 'Defense';
      case OnboardingFocus.conditioning:
        return 'Gas tank';
      case OnboardingFocus.handfight:
        return 'Handfight';
    }
  }
}

extension OnboardingPushLevelText on OnboardingPushLevel {
  String get label {
    switch (this) {
      case OnboardingPushLevel.build:
        return 'Build me up';
      case OnboardingPushLevel.hard:
        return 'Push hard';
      case OnboardingPushLevel.max:
        return 'Max intensity';
    }
  }
}

@immutable
class OnboardingProfile {
  final OnboardingRole role;
  final OnboardingGoal goal;
  final OnboardingFocus focus;
  final OnboardingPushLevel pushLevel;
  final bool workoutRemindersEnabled;
  final DateTime completedAt;
  final DateTime? lastWorkoutCompletedAt;

  const OnboardingProfile({
    required this.role,
    required this.goal,
    required this.focus,
    required this.pushLevel,
    required this.workoutRemindersEnabled,
    required this.completedAt,
    this.lastWorkoutCompletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role.name,
      'goal': goal.name,
      'focus': focus.name,
      'pushLevel': pushLevel.name,
      'workoutRemindersEnabled': workoutRemindersEnabled,
      'completedAt': completedAt.toIso8601String(),
      'lastWorkoutCompletedAt': lastWorkoutCompletedAt?.toIso8601String(),
    };
  }

  String toJson() => jsonEncode(toMap());

  factory OnboardingProfile.fromMap(Map<String, dynamic> map) {
    return OnboardingProfile(
      role: _enumFromName(
        OnboardingRole.values,
        map['role'] as String?,
        OnboardingRole.wrestler,
      ),
      goal: _enumFromName(
        OnboardingGoal.values,
        map['goal'] as String?,
        OnboardingGoal.dailyPractice,
      ),
      focus: _enumFromName(
        OnboardingFocus.values,
        map['focus'] as String?,
        OnboardingFocus.offense,
      ),
      pushLevel: _enumFromName(
        OnboardingPushLevel.values,
        map['pushLevel'] as String?,
        OnboardingPushLevel.hard,
      ),
      workoutRemindersEnabled: map['workoutRemindersEnabled'] == true,
      completedAt: DateTime.tryParse(map['completedAt'] as String? ?? '') ??
          DateTime.now(),
      lastWorkoutCompletedAt: DateTime.tryParse(
        map['lastWorkoutCompletedAt'] as String? ?? '',
      ),
    );
  }

  factory OnboardingProfile.fromJson(String source) {
    return OnboardingProfile.fromMap(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  OnboardingProfile copyWith({
    bool? workoutRemindersEnabled,
    Object? lastWorkoutCompletedAt = _dateTimeUnset,
  }) {
    return OnboardingProfile(
      role: role,
      goal: goal,
      focus: focus,
      pushLevel: pushLevel,
      workoutRemindersEnabled:
          workoutRemindersEnabled ?? this.workoutRemindersEnabled,
      completedAt: completedAt,
      lastWorkoutCompletedAt: identical(lastWorkoutCompletedAt, _dateTimeUnset)
          ? this.lastWorkoutCompletedAt
          : lastWorkoutCompletedAt as DateTime?,
    );
  }
}

@immutable
class OnboardingState {
  final bool loaded;
  final OnboardingProfile? profile;

  const OnboardingState({
    this.loaded = false,
    this.profile,
  });

  bool get completed => profile != null;

  bool get workoutRemindersEnabled => profile?.workoutRemindersEnabled ?? false;

  DateTime? get lastWorkoutCompletedAt => profile?.lastWorkoutCompletedAt;

  OnboardingState copyWith({
    bool? loaded,
    Object? profile = _profileUnset,
  }) {
    return OnboardingState(
      loaded: loaded ?? this.loaded,
      profile: identical(profile, _profileUnset)
          ? this.profile
          : profile as OnboardingProfile?,
    );
  }
}

const _profileUnset = Object();
const _dateTimeUnset = Object();

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(() {
  return OnboardingNotifier();
});

class OnboardingNotifier extends Notifier<OnboardingState> {
  static const _keyOnboardingProfile = 'onboarding_profile_v1';

  @override
  OnboardingState build() {
    unawaited(load());
    return const OnboardingState();
  }

  Future<OnboardingState> load() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    final jsonString = prefs.getString(_keyOnboardingProfile);
    final profile =
        jsonString == null ? null : OnboardingProfile.fromJson(jsonString);

    state = OnboardingState(loaded: true, profile: profile);
    return state;
  }

  Future<OnboardingState> ensureLoaded() async {
    if (state.loaded) return state;
    return load();
  }

  Future<void> complete(OnboardingProfile profile) async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_keyOnboardingProfile, profile.toJson());
    state = OnboardingState(loaded: true, profile: profile);
  }

  Future<OnboardingProfile> setWorkoutRemindersEnabled(bool enabled) async {
    final current = state.profile ??
        OnboardingProfile(
          role: OnboardingRole.wrestler,
          goal: OnboardingGoal.dailyPractice,
          focus: OnboardingFocus.offense,
          pushLevel: OnboardingPushLevel.hard,
          workoutRemindersEnabled: enabled,
          completedAt: DateTime.now(),
        );
    final next = current.copyWith(workoutRemindersEnabled: enabled);
    await complete(next);
    return next;
  }

  Future<OnboardingProfile> recordWorkoutCompleted(DateTime completedAt) async {
    final loadedState = state.loaded ? state : await load();
    final current = loadedState.profile ??
        OnboardingProfile(
          role: OnboardingRole.wrestler,
          goal: OnboardingGoal.dailyPractice,
          focus: OnboardingFocus.offense,
          pushLevel: OnboardingPushLevel.hard,
          workoutRemindersEnabled: false,
          completedAt: DateTime.now(),
        );
    final next = current.copyWith(lastWorkoutCompletedAt: completedAt);
    await complete(next);
    return next;
  }
}

class NotificationPermissionPrompter {
  const NotificationPermissionPrompter();

  Future<bool> requestWorkoutReminderPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  }
}

T _enumFromName<T extends Enum>(
  List<T> values,
  String? name,
  T fallback,
) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
