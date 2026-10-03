import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'firebase_environment.dart';
import '../features/compliance/age_eligibility.dart';

abstract final class FirebaseBootstrap {
  static const _authEmulatorPort = 9099;
  static const _firestoreEmulatorPort = 8080;
  static const _functionsEmulatorPort = 5001;
  static const _storageEmulatorPort = 9199;

  static Future<void>? _initialization;
  static bool _isAvailable = false;
  static Object? _lastError;

  /// Whether Firebase completed startup for this process.
  ///
  /// The workout experience intentionally does not depend on this value. Only
  /// account and social features should be disabled while it is false.
  static bool get isAvailable => _isAvailable;
  static Object? get lastError => _lastError;

  static Future<void> initialize() async {
    final activeInitialization = _initialization;
    if (activeInitialization != null) {
      return activeInitialization;
    }

    final initialization = _initialize();
    _initialization = initialization;

    await initialization;
  }

  static Future<void> _initialize() async {
    try {
      final app = Firebase.apps.isEmpty
          ? await Firebase.initializeApp()
          : Firebase.app();

      FirebaseEnvironmentConfig.validateProjectId(app.options.projectId);

      if (FirebaseEnvironmentConfig.useEmulators) {
        await _connectToEmulators();
      }

      await _activateAppCheck();
      _isAvailable = true;
      _lastError = null;
    } catch (error, stackTrace) {
      _isAvailable = false;
      _lastError = error;
      debugPrint(
        'Firebase is unavailable; Snap & Go is continuing in local mode: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Retries Firebase without restarting the local workout experience.
  static Future<bool> retry() async {
    _initialization = null;
    await initialize();
    return _isAvailable;
  }

  static Future<void> _connectToEmulators() async {
    final host = FirebaseEnvironmentConfig.emulatorHost;

    await FirebaseAuth.instance.useAuthEmulator(host, _authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      _firestoreEmulatorPort,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      host,
      _functionsEmulatorPort,
    );
    await FirebaseStorage.instance.useStorageEmulator(
      host,
      _storageEmulatorPort,
    );
  }

  static Future<void> _activateAppCheck() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return;
    }

    final useDebugProvider = FirebaseEnvironmentConfig.useDebugAppCheck;
    final debugToken = FirebaseEnvironmentConfig.appCheckDebugToken;

    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebugProvider
          ? AndroidDebugProvider(debugToken: debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebugProvider
          ? AppleDebugProvider(debugToken: debugToken)
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final ageEligibility = await AgeEligibilityStorage.load();
  if (ageEligibility?.allowsConnectedFeatures != true) return;
  await FirebaseBootstrap.initialize();
}
