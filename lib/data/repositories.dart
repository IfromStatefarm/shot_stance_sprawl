// lib/data/repositories.dart
import 'dart:io';

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:firebase_auth/firebase_auth.dart';


import '../features/drill/models.dart';


/// Local Repository replacing the redundant Firebase Firestore/Storage implementation.
/// Unifies the "Split Brain" by keeping all custom audio and metadata local.
/// This prevents exorbitant Firebase bandwidth costs for a Freemium app, 
/// allows the app to work offline in gyms with poor cell service, and keeps 
/// the architecture decoupled from the state management providers.
class LocalCalloutRepository {
  static const _keyCustomCallouts = 'custom_callouts_v1';
  final SharedPreferences prefs;

  LocalCalloutRepository(this.prefs);

  /// Retrieves the list of custom callouts saved locally
  List<Callout> getCustomCallouts() {
    final jsonString = prefs.getString(_keyCustomCallouts);
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((e) => Callout.fromJson(e)).toList();
    } catch (e) {
      // Return empty gracefully if local data is corrupted
      return [];
    }
  }

  /// Persists the custom callouts to the device storage, ensuring only user-created callouts are saved
  Future<void> saveCustomCallouts(List<Callout> callouts) async {
    // Ensure we only save the custom ones, not the hardcoded defaults
    final customOnly = callouts.where((c) => c.isCustom).toList();
    final jsonString = jsonEncode(customOnly.map((c) => c.toMap()).toList());
    
    await prefs.setString(_keyCustomCallouts, jsonString);
  }
}

class UserRepository {
  final FirebaseFirestore db;
  UserRepository(this.db);

  Stream<UserProfile> watchProfile(String uid) {
    final doc = db.collection('users').doc(uid);
    return doc.snapshots().map((s) {
      final data = s.data() ?? {};
      return UserProfile.fromMap(s.id, data);
    });
  }

  Future<void> setActiveVoicePack(String uid, String packId) async {
    await db.collection('users').doc(uid).set(
      {'activeVoicePackId': packId},
      SetOptions(merge: true),
    );
  }
}

class VoicePackRepository {
  final FirebaseFirestore db;
  VoicePackRepository(this.db);

  Stream<List<VoicePack>> watchPacks(String uid) {
    return db
        .collection('users')
        .doc(uid)
        .collection('voicePacks')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => VoicePack.fromMap(d.id, d.data())).toList());
  }

  Future<String> createCustomPack({
    required String ownerId,
    required String name,
  }) async {
    final ref =
        db.collection('users').doc(ownerId).collection('voicePacks').doc();
    await ref.set({
      'name': name,
      'ownerId': ownerId,
      'isCustom': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }
}

class CalloutRepository {
  final FirebaseFirestore db;
  CalloutRepository(this.db);

  Stream<List<Callout>> watchCallouts(String uid, String packId) {
    return db
        .collection('users')
        .doc(uid)
        .collection('voicePacks')
        .doc(packId)
        .collection('callouts')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Callout.fromMap(d.id, d.data())).toList());
  }

  Future<String> createCalloutWithUpload({
    required String ownerId,
    required String packId,
    required String name,
    required String type, // 'Movement' | 'Duration'
    int? durationSeconds,
    required File audioFile,
    required StorageRepository storageRepo,
  }) async {
    // 1) Upload audio
    final fileName =
        'callouts/${DateTime.now().millisecondsSinceEpoch}_${audioFile.path.split('/').last}';
    final audioUrl = await storageRepo.uploadFileAndGetUrl(
      ownerId: ownerId,
      packId: packId,
      localFile: audioFile,
      storagePath: fileName,
    );

    // 2) Save doc
    final ref = db
        .collection('users')
        .doc(ownerId)
        .collection('voicePacks')
        .doc(packId)
        .collection('callouts')
        .doc();

    await ref.set({
      'name': name,
      'type': type,
      'durationSeconds': durationSeconds,
      'audioUrl': audioUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }
}

class StorageRepository {
  final FirebaseStorage storage;
  StorageRepository(this.storage);

  Future<String> uploadFileAndGetUrl({
    required String ownerId,
    required String packId,
    required File localFile,
    required String storagePath, // e.g. 'callouts/12345_name.m4a'
  }) async {
    final ref = storage
        .ref()
        .child('users')
        .child(ownerId)
        .child('voicePacks')
        .child(packId)
        .child(storagePath);

    await ref.putFile(localFile);
    return await ref.getDownloadURL();
  }
}


