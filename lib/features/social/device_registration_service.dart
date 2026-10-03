import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceRegistrationService {
  DeviceRegistrationService({
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _messaging = messaging ?? FirebaseMessaging.instance;

  static const _deviceIdKey = 'firebase_device_document_id_v1';
  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokenSubscription;
  DocumentReference<Map<String, dynamic>>? _deviceReference;
  bool _disposed = false;

  Future<void> start(String uid) async {
    if (!_supportsMessaging) return;
    await _messaging.setAutoInitEnabled(true);
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (error) {
      // Token refresh remains useful if permission changes in system settings.
      debugPrint('FCM notification permission is unavailable: $error');
    }
    final preferences = await SharedPreferences.getInstance();
    if (_disposed) return;
    final tokenId = preferences.getString(_deviceIdKey) ?? _newDeviceId();
    await preferences.setString(_deviceIdKey, tokenId);
    if (_disposed) return;
    _deviceReference = _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(tokenId);

    final token = await _messaging.getToken();
    if (_disposed) return;
    if (token != null && token.isNotEmpty) await _saveToken(token);
    if (_disposed) return;
    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_saveToken(token)),
      onError: (Object error) {
        debugPrint('FCM token refresh failed: $error');
      },
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    final reference = _deviceReference;
    _deviceReference = null;
    if (reference != null) {
      try {
        await reference.delete();
      } catch (error) {
        debugPrint('Could not unregister this FCM device: $error');
      }
    }
  }

  Future<void> _saveToken(String token) async {
    final reference = _deviceReference;
    if (reference == null) return;
    await reference.set({
      'fcmToken': token,
      'platform': defaultTargetPlatform.name,
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool get _supportsMessaging =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  String _newDeviceId() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
