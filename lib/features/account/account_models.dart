import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountIdentity {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isAnonymous;

  const AccountIdentity({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    required this.isAnonymous,
  });

  factory AccountIdentity.fromFirebaseUser(User user) {
    return AccountIdentity(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      isAnonymous: user.isAnonymous,
    );
  }
}

class AccountActionState {
  final bool busy;
  final bool localProgressSyncPending;
  final String? message;

  const AccountActionState({
    this.busy = false,
    this.localProgressSyncPending = false,
    this.message,
  });

  AccountActionState copyWith({
    bool? busy,
    bool? localProgressSyncPending,
    String? message,
    bool clearMessage = false,
  }) {
    return AccountActionState(
      busy: busy ?? this.busy,
      localProgressSyncPending:
          localProgressSyncPending ?? this.localProgressSyncPending,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class AccountException implements Exception {
  final String message;
  final String? code;

  const AccountException(this.message, {this.code});

  @override
  String toString() => message;
}

String accountErrorMessage(Object error) {
  if (error is AccountException) return error.message;
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
      GoogleSignInExceptionCode.interrupted =>
        'Google sign-in was interrupted. Please try again.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not configured for this Android build.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google sign-in could not open. Please try again.',
      GoogleSignInExceptionCode.userMismatch =>
        'Choose the same Google account and try again.',
      _ => error.description ?? 'Google sign-in failed. Please try again.',
    };
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'invalid-credential' ||
      'wrong-password' =>
        'The email or password is incorrect.',
      'email-already-in-use' => 'That email already has an account.',
      'weak-password' => 'Use a password with at least 6 characters.',
      'user-disabled' => 'This account has been disabled.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'network-request-failed' =>
        'Firebase is unreachable. Local workouts are still available.',
      'requires-recent-login' =>
        'Sign out, sign back in, and try this sensitive action again.',
      'credential-already-in-use' =>
        'That sign-in method belongs to another account.',
      'provider-already-linked' =>
        'That sign-in method is already linked to this account.',
      'invalid-verification-code' => 'The verification code is incorrect.',
      'session-expired' => 'That verification code expired. Send a new one.',
      _ => error.message ?? 'Account request failed (${error.code}).',
    };
  }
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'Secure account request failed (${error.code}).';
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Your account connected, but its profile could not be created.',
      'unavailable' => 'Firebase is temporarily unavailable. Please try again.',
      _ => error.message ?? 'Firebase request failed (${error.code}).',
    };
  }
  return 'Account request failed. Local workouts are still available.';
}
