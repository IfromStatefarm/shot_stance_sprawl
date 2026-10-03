import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../account/account_models.dart';

class TeamMembership {
  const TeamMembership({required this.teamId, required this.role});

  final String teamId;
  final String role;
  bool get isOwner => role == 'owner';

  factory TeamMembership.fromMap(Map<String, dynamic> data) => TeamMembership(
        teamId: data['teamId'] as String? ?? '',
        role: data['role'] as String? ?? 'member',
      );
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.state,
    required this.photoPath,
    required this.ownerUid,
    required this.status,
  });

  final String id;
  final String name;
  final String state;
  final String photoPath;
  final String ownerUid;
  final String status;

  factory Team.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Team(
      id: doc.id,
      name: data['name'] as String? ?? '',
      state: data['state'] as String? ?? '',
      photoPath: data['photoPath'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      status: data['status'] as String? ?? '',
    );
  }
}

class TeamRepository {
  TeamRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AccountException('Sign in first.');
    return uid;
  }

  Stream<TeamMembership?> watchMembership() => _firestore
      .collection('users')
      .doc(_uid)
      .collection('privateData')
      .doc('team')
      .snapshots()
      .map((doc) => doc.exists ? TeamMembership.fromMap(doc.data()!) : null);

  Stream<Team?> watchTeam(String teamId) => _firestore
      .collection('teams')
      .doc(teamId)
      .snapshots()
      .map((doc) => doc.exists ? Team.fromFirestore(doc) : null);

  Stream<List<String>> watchMemberIds(String teamId) => _firestore
      .collection('teams')
      .doc(teamId)
      .collection('members')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());

  Stream<String?> watchAccessCode(String teamId) => _firestore
      .collection('teams')
      .doc(teamId)
      .collection('private')
      .doc('access')
      .snapshots()
      .map((doc) => doc.data()?['code'] as String?);

  Future<String> photoUrl(String photoPath) =>
      _storage.ref(photoPath).getDownloadURL();

  Future<String> _uploadPhoto(XFile image) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const AccountException('Choose a team photo under 5 MB.');
    }
    final lowerName = image.name.toLowerCase();
    final contentType = lowerName.endsWith('.png')
        ? 'image/png'
        : lowerName.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    final id = '${DateTime.now().microsecondsSinceEpoch}'
        '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final path = 'teamPhotoUploads/$_uid/$id';
    await _storage.ref(path).putData(
          bytes,
          SettableMetadata(contentType: contentType),
        );
    return path;
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    await _functions.httpsCallable(name).call<void>(data);
  }

  Future<void> createTeam({
    required String name,
    required String state,
    required XFile photo,
  }) async {
    final path = await _uploadPhoto(photo);
    try {
      await _call('createTeam', {
        'name': name.trim(),
        'state': state.trim(),
        'photoPath': path,
      });
    } catch (_) {
      await _storage.ref(path).delete().catchError((Object _) {});
      rethrow;
    }
  }

  Future<void> editTeam({
    required String name,
    required String state,
    XFile? photo,
  }) async {
    final path = photo == null ? null : await _uploadPhoto(photo);
    try {
      await _call('editTeam', {
        'name': name.trim(),
        'state': state.trim(),
        if (path != null) 'photoPath': path,
      });
    } catch (_) {
      if (path != null) {
        await _storage.ref(path).delete().catchError((Object _) {});
      }
      rethrow;
    }
  }

  Future<void> joinTeam(String code) =>
      _call('joinTeam', {'code': code.trim()});
  Future<void> leaveTeam() => _call('leaveTeam', const {});
  Future<void> deleteTeam() => _call('deleteTeam', const {});
}
