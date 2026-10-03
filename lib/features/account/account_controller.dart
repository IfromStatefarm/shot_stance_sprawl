import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/firebase_bootstrap.dart';
import 'account_models.dart';
import 'account_repository.dart';
import 'local_account_data.dart';

final firebaseAvailabilityProvider =
    NotifierProvider<FirebaseAvailabilityNotifier, bool>(
  FirebaseAvailabilityNotifier.new,
);

class FirebaseAvailabilityNotifier extends Notifier<bool> {
  @override
  bool build() => FirebaseBootstrap.isAvailable;

  Future<bool> retry() async {
    final available = await FirebaseBootstrap.retry();
    state = available;
    ref.invalidate(accountIdentityProvider);
    ref.invalidate(accountUsernameProvider);
    return available;
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  if (!ref.watch(firebaseAvailabilityProvider)) {
    throw const AccountException(
      'Firebase is unavailable. Local workouts are still available.',
    );
  }
  return AccountRepository();
});

final localAccountDataProvider = FutureProvider<LocalAccountData>((ref) async {
  return LocalAccountData(await SharedPreferences.getInstance());
});

final accountIdentityProvider = StreamProvider<AccountIdentity?>((ref) {
  if (!ref.watch(firebaseAvailabilityProvider)) {
    return Stream<AccountIdentity?>.value(null);
  }
  return ref.watch(accountRepositoryProvider).watchIdentity();
});

final accountUsernameProvider = FutureProvider<String?>((ref) async {
  final identity = await ref.watch(accountIdentityProvider.future);
  if (identity == null) return null;
  return ref.watch(accountRepositoryProvider).loadUsername(identity.uid);
});

final accountControllerProvider =
    NotifierProvider<AccountController, AccountActionState>(
  AccountController.new,
);

class AccountController extends Notifier<AccountActionState> {
  @override
  AccountActionState build() => const AccountActionState();

  AccountRepository get _repository => ref.read(accountRepositoryProvider);

  Future<void> createEmailAccount(String email, String password) {
    return _authenticate(
      () => _repository.createEmailAccount(email: email, password: password),
    );
  }

  Future<void> signInWithEmail(String email, String password) {
    return _authenticate(
      () => _repository.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> signInWithGoogle() {
    return _authenticate(_repository.signInWithGoogle);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    _begin();
    try {
      if (email.trim().isEmpty) {
        throw const AccountException('Enter your email address first.');
      }
      await _repository.sendPasswordResetEmail(email);
      state = state.copyWith(
        busy: false,
        message: 'Password reset email sent.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> signInWithApple() {
    return _authenticate(_repository.signInWithApple);
  }

  Future<void> _authenticate(
    Future<AccountIdentity> Function() authenticate,
  ) async {
    _begin();
    try {
      final identity = await authenticate();
      final synced = await _linkLocalProgress(identity.uid);
      ref.invalidate(accountUsernameProvider);
      state = state.copyWith(
        busy: false,
        localProgressSyncPending: !synced,
        message: synced
            ? 'Account connected. Your local progress is linked.'
            : 'Signed in. Local progress will sync when Firebase reconnects.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<bool> _linkLocalProgress(String uid) async {
    final localData = await ref.read(localAccountDataProvider.future);
    if (localData.isLinkedTo(uid)) return true;
    try {
      await _repository.uploadLocalProgress(localData.progressSnapshot());
      await localData.markLinkedTo(uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> retryLocalProgressSync() async {
    final identity = _repository.currentIdentity;
    if (identity == null) throw const AccountException('Sign in first.');
    _begin();
    final synced = await _linkLocalProgress(identity.uid);
    state = state.copyWith(
      busy: false,
      localProgressSyncPending: !synced,
      message: synced
          ? 'Local progress is linked.'
          : 'Progress is still local. Try again when Firebase is reachable.',
    );
    if (!synced) {
      throw const AccountException(
        'Progress is still local. Try again when Firebase is reachable.',
      );
    }
  }

  Future<String> claimUsername(String value) async {
    _begin();
    try {
      final username = await _repository.claimUsername(value);
      ref.invalidate(accountUsernameProvider);
      state = state.copyWith(
        busy: false,
        message: '@$username is ready for friend invites.',
      );
      return username;
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> sendFriendRequest(String username) async {
    _begin();
    try {
      final result = await _repository.sendFriendRequest(username);
      state = state.copyWith(
        busy: false,
        message: switch (result) {
          'already-friends' => 'You are already friends with @$username.',
          'already-pending' => 'A friend request is already pending.',
          _ => 'Friend request sent to @$username.',
        },
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<File> createDataExport() async {
    _begin();
    try {
      final localData = await ref.read(localAccountDataProvider.future);
      Map<String, dynamic> remoteData;
      if (ref.read(firebaseAvailabilityProvider)) {
        try {
          remoteData = await _repository.exportRemoteAccountData();
        } catch (error) {
          remoteData = {
            'available': false,
            'reason': accountErrorMessage(error),
          };
        }
      } else {
        remoteData = const {
          'available': false,
          'reason': 'Firebase was unavailable during export.',
        };
      }
      final file = await localData.writeExportFile(remoteData);
      state = state.copyWith(busy: false, message: 'Data export is ready.');
      return file;
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> shareDataExport({Rect? sharePositionOrigin}) async {
    final file = await createDataExport();
    await SharePlus.instance.share(
      ShareParams(
        title: 'Snap & Go data export',
        subject: 'My Snap & Go data export',
        files: [XFile(file.path, mimeType: 'application/json')],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<void> deleteAccount() async {
    _begin();
    try {
      await _repository.deleteAccount();
      ref.invalidate(accountIdentityProvider);
      ref.invalidate(accountUsernameProvider);
      state = const AccountActionState(message: 'Account deleted.');
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> signOut() async {
    _begin();
    try {
      await _repository.signOut();
      ref.invalidate(accountUsernameProvider);
      state = const AccountActionState(message: 'Signed out.');
    } catch (error) {
      _fail(error);
    }
  }

  void clearMessage() {
    state = state.copyWith(clearMessage: true);
  }

  void _begin() {
    state = state.copyWith(
      busy: true,
      clearMessage: true,
    );
  }

  Never _fail(Object error) {
    final message = accountErrorMessage(error);
    debugPrint('Account request failed (${error.runtimeType}): $error');
    state = state.copyWith(busy: false, message: message);
    throw AccountException(message);
  }
}

abstract final class AccountInviteLinks {
  static Uri appLink(String username) =>
      Uri.parse('snapandgo://friend/${normalizeUsername(username)}');

  static Uri webLink(String username) => Uri.https(
        'keepkidswrestling.com',
        '/Snap-and-go/invite',
        {'username': normalizeUsername(username)},
      );

  static String? usernameFromUri(Uri uri) {
    String? candidate;
    if (uri.scheme == 'snapandgo' && uri.host == 'friend') {
      candidate = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'keepkidswrestling.com' &&
        uri.path == '/Snap-and-go/invite') {
      candidate = uri.queryParameters['username'];
    }
    if (candidate == null || !isValidUsername(candidate)) return null;
    return normalizeUsername(candidate);
  }
}
