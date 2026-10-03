import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

enum FirebaseEnvironment {
  development,
  production,
}

abstract final class FirebaseEnvironmentConfig {
  static const _configuredEnvironment = String.fromEnvironment(
    'FIREBASE_ENV',
    defaultValue: '',
  );

  static const _emulatorsEnabled = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  static const _configuredEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '',
  );

  static const _appCheckDebugToken = String.fromEnvironment(
    'FIREBASE_APP_CHECK_DEBUG_TOKEN',
    defaultValue: '',
  );

  static FirebaseEnvironment get current {
    const nativeFlavor = appFlavor;
    if (nativeFlavor != null && nativeFlavor.isNotEmpty) {
      return environmentForFlavor(nativeFlavor);
    }

    if (_configuredEnvironment.isNotEmpty) {
      return environmentForFlavor(_configuredEnvironment);
    }

    // iOS uses the standard Runner scheme: debug/profile builds package the
    // development plist, while release archives package production. Keep the
    // Dart selection in lockstep without requiring a custom scheme.
    return kReleaseMode
        ? FirebaseEnvironment.production
        : FirebaseEnvironment.development;
  }

  static FirebaseEnvironment environmentForFlavor(String flavor) {
    switch (flavor.toLowerCase()) {
      case 'prod':
      case 'production':
        return FirebaseEnvironment.production;
      case 'dev':
      case 'development':
        return FirebaseEnvironment.development;
      default:
        throw StateError(
          'Unsupported Firebase build flavor "$flavor". '
          'Use the "dev" or "prod" flavor.',
        );
    }
  }

  static String get expectedProjectId {
    return switch (current) {
      FirebaseEnvironment.development => 'snap-and-go-dev',
      FirebaseEnvironment.production => 'snap-and-go-prod',
    };
  }

  static bool get useDebugAppCheck {
    return current == FirebaseEnvironment.development && !kReleaseMode;
  }

  static String? get appCheckDebugToken {
    return _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken;
  }

  static bool get useEmulators {
    return current == FirebaseEnvironment.development &&
        !kReleaseMode &&
        _emulatorsEnabled;
  }

  static String get emulatorHost {
    if (_configuredEmulatorHost.isNotEmpty) {
      return _configuredEmulatorHost;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }

    return '127.0.0.1';
  }

  static void validateProjectId(String projectId) {
    final expected = expectedProjectId;
    if (projectId == expected) {
      return;
    }

    throw StateError(
      'Firebase environment mismatch: flavor "${appFlavor ?? 'unflavored'}" expects '
      'project "$expected", but the bundled Firebase configuration points '
      'to "$projectId".',
    );
  }
}
