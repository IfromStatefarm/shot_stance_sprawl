import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'account_models.dart';

String normalizeUsername(String value) => value.trim().toLowerCase();

bool isValidUsername(String value) {
  return RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalizeUsername(value));
}

class AccountRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final GoogleSignIn googleSignIn;

  Future<void>? _googleInitialization;

  AccountRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    GoogleSignIn? googleSignIn,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance,
        googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  Stream<AccountIdentity?> watchIdentity() {
    return auth.userChanges().map(
          (user) =>
              user == null ? null : AccountIdentity.fromFirebaseUser(user),
        );
  }

  AccountIdentity? get currentIdentity {
    final user = auth.currentUser;
    return user == null ? null : AccountIdentity.fromFirebaseUser(user);
  }

  Future<AccountIdentity> createEmailAccount({
    required String email,
    required String password,
  }) async {
    final currentUser = auth.currentUser;
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    final result = currentUser?.isAnonymous == true
        ? await currentUser!.linkWithCredential(credential)
        : await auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
    return _finishAuthentication(result);
  }

  Future<AccountIdentity> signInWithEmail({
    required String email,
    required String password,
  }) async {
    // Signing in to an existing account intentionally replaces a temporary
    // anonymous Firebase user; the device progress is uploaded afterward.
    final result = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _finishAuthentication(result);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<AccountIdentity> signInWithGoogle() async {
    _googleInitialization ??= googleSignIn.initialize();
    await _googleInitialization;
    if (!googleSignIn.supportsAuthenticate()) {
      throw const AccountException(
        'Google sign-in is not supported on this platform.',
      );
    }

    final googleAccount = await googleSignIn.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AccountException(
        'Google did not return an identity token. Check Firebase OAuth setup.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final currentUser = auth.currentUser;
    late final UserCredential result;
    if (currentUser?.isAnonymous == true) {
      try {
        result = await currentUser!.linkWithCredential(credential);
      } on FirebaseAuthException catch (error) {
        if (error.code != 'credential-already-in-use') rethrow;
        result = await auth.signInWithCredential(credential);
      }
    } else {
      result = await auth.signInWithCredential(credential);
    }
    return _finishAuthentication(result);
  }

  Future<AccountIdentity> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final currentUser = auth.currentUser;
    late final UserCredential result;
    if (currentUser?.isAnonymous == true) {
      try {
        result = await currentUser!.linkWithProvider(provider);
      } on FirebaseAuthException catch (error) {
        if (error.code != 'credential-already-in-use') rethrow;
        result = kIsWeb
            ? await auth.signInWithPopup(provider)
            : await auth.signInWithProvider(provider);
      }
    } else {
      result = kIsWeb
          ? await auth.signInWithPopup(provider)
          : await auth.signInWithProvider(provider);
    }
    return _finishAuthentication(result);
  }

  Future<AccountIdentity> _finishAuthentication(UserCredential result) async {
    final user = result.user;
    if (user == null) {
      throw const AccountException('Firebase did not return an account.');
    }
    await ensureAccountDocuments(user);
    return AccountIdentity.fromFirebaseUser(user);
  }

  Future<void> ensureAccountDocuments(User user) async {
    final publicProfile = firestore.collection('users').doc(user.uid);
    final safeProfile = firestore.collection('safeProfiles').doc(user.uid);
    final privateAccount =
        publicProfile.collection('privateData').doc('account');
    final providers = user.providerData.map((item) => item.providerId).toSet();
    final existingProfile = (await publicProfile.get()).data();

    final batch = firestore.batch();
    final publicProfileData = <String, dynamic>{
      'displayName': _publicDisplayName(user),
      'photoUrl': user.photoURL,
      if (existingProfile?['language'] == null) 'language': 'en',
      if (existingProfile?['discoverable'] == null) 'discoverable': true,
      'accountSafety': {
        'allowFriendRequests': (existingProfile?['accountSafety']
                as Map?)?['allowFriendRequests'] as bool? ??
            true,
        'allowWorkoutMessages': (existingProfile?['accountSafety']
                as Map?)?['allowWorkoutMessages'] as bool? ??
            true,
      },
      if (existingProfile?['unreadSharedWorkoutCount'] == null)
        'unreadSharedWorkoutCount': 0,
      if (existingProfile?['createdAt'] == null)
        'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (existingProfile == null) {
      batch.set(publicProfile, publicProfileData);
    } else {
      // Replacing the complete settings map also removes the retired contact
      // matching preference from profiles created by older app versions.
      batch.update(publicProfile, publicProfileData);
    }
    batch.set(
      safeProfile,
      {
        'displayName': _publicDisplayName(user),
        'photoUrl': user.photoURL,
        'language': existingProfile?['language'] as String? ?? 'en',
        if (existingProfile?['username'] case final String username)
          'username': username,
      },
      SetOptions(merge: true),
    );
    batch.set(
      privateAccount,
      {
        'email': user.email,
        'phoneVerified': FieldValue.delete(),
        'providers': providers.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  String _publicDisplayName(User user) {
    final candidate = user.displayName?.trim();
    if (candidate != null && candidate.isNotEmpty) return candidate;
    return 'Snap & Go athlete';
  }

  Future<String?> loadUsername(String uid) async {
    final snapshot = await firestore.collection('users').doc(uid).get();
    return snapshot.data()?['username'] as String?;
  }

  Future<String> claimUsername(String value) async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('Sign in first.');

    final username = normalizeUsername(value);
    if (!isValidUsername(username)) {
      throw const AccountException(
        'Use 3–20 letters, numbers, or underscores.',
      );
    }

    final result = await functions.httpsCallable('claimUsername').call({
      'username': username,
    });
    final data = result.data;
    final claimed = data is Map ? data['username'] as String? : null;
    if (claimed == null || claimed.isEmpty) {
      throw const AccountException('Firebase did not return the username.');
    }
    return claimed;
  }

  Future<String> sendFriendRequest(String value) async {
    if (auth.currentUser == null) {
      throw const AccountException('Sign in first.');
    }
    final username = normalizeUsername(value);
    if (!isValidUsername(username)) {
      throw const AccountException('Enter a valid username.');
    }
    final result = await functions.httpsCallable('sendFriendRequest').call({
      'username': username,
    });
    final data = result.data;
    if (data is Map && data['status'] is String) {
      return data['status'] as String;
    }
    return 'sent';
  }

  Future<void> uploadLocalProgress(Map<String, dynamic> snapshot) async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('Sign in first.');
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('privateData')
        .doc('localProgress')
        .set(
      {
        'schemaVersion': 1,
        'snapshot': snapshot,
        'linkedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<Map<String, dynamic>> exportRemoteAccountData() async {
    final user = auth.currentUser;
    if (user == null) return const {'signedIn': false};

    try {
      final result = await functions.httpsCallable('exportAccountData').call();
      final data = result.data;
      if (data is Map) {
        return {'signedIn': true, ...Map<String, dynamic>.from(data)};
      }
    } catch (_) {
      // The direct owner-only reads below keep export available before the
      // callable is deployed and while developing against partial emulators.
    }

    final profileRef = firestore.collection('users').doc(user.uid);
    final snapshots = await Future.wait([
      profileRef.get(),
      profileRef.collection('privateData').doc('account').get(),
      profileRef.collection('privateData').doc('localProgress').get(),
    ]);

    return {
      'signedIn': true,
      'uid': user.uid,
      'publicProfile': snapshots[0].data(),
      'privateAccount': snapshots[1].data(),
      'linkedProgress': snapshots[2].data(),
    };
  }

  Future<void> deleteAccount() async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('No account is signed in.');

    // Server-side cleanup is required so future social subcollections and the
    // server-owned social records are removed before Auth is deleted.
    await functions.httpsCallable('deleteAccountData').call<void>();
    // The callable removes both Firestore data and the Firebase Auth user after
    // enforcing a recent sign-in. Clear any cached local SDK session afterward.
    await auth.signOut();
    await _signOutGoogleIfInitialized();
  }

  Future<void> signOut() async {
    await auth.signOut();
    await _signOutGoogleIfInitialized();
  }

  Future<void> _signOutGoogleIfInitialized() async {
    if (_googleInitialization == null) return;
    try {
      await googleSignIn.signOut();
    } catch (_) {
      // Firebase is already signed out; a stale Google session must not block it.
    }
  }
}
