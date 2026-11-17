import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/errors/app_failure.dart';
import '../repositories/auth_repository.dart';

/// Firebase Authentication implementation: email/password, Google, email
/// verification, password reset, provider linking, re-authentication and
/// account deletion.
///
/// No credential or token is ever written to disk, logged or kept in a model.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({fb.FirebaseAuth? auth, GoogleSignIn? google})
    : _auth = auth ?? fb.FirebaseAuth.instance,
      _google = google ?? GoogleSignIn.instance;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _google;

  static bool _googleInitialized = false;

  /// Raw Firebase user, used by the account service for profile work.
  fb.User? get rawUser => _auth.currentUser;

  @override
  bool get isProductionBackend => true;

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> get authChanges => _auth.authStateChanges().map(_map);

  @override
  bool get emailVerified => _auth.currentUser?.emailVerified ?? false;

  @override
  bool get hasPasswordProvider =>
      _auth.currentUser?.providerData.any(
        (provider) => provider.providerId == 'password',
      ) ??
      false;

  @override
  bool get hasGoogleProvider =>
      _auth.currentUser?.providerData.any(
        (provider) => provider.providerId == 'google.com',
      ) ??
      false;

  AuthUser? _map(fb.User? user) {
    if (user == null) return null;
    return AuthUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      createdAt: user.metadata.creationTime ?? DateTime.now(),
      emailVerified: user.emailVerified,
    );
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _require(result.user);
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    final credential = await _googleCredential();
    try {
      final result = await _auth.signInWithCredential(credential);
      return _require(result.user);
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = _require(result.user);
      if (displayName.trim().isNotEmpty) {
        await result.user?.updateDisplayName(displayName.trim());
      }
      return user;
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> setDisplayName(String name) async {
    try {
      await _auth.currentUser?.updateDisplayName(name.trim());
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (error) {
      // The UI must not reveal whether an account exists, so a missing user is
      // reported as a successful request.
      if (error.code == 'user-not-found') return;
      throw _failure(error);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<bool> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> reauthenticate({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw const AppFailure(FailureKind.permission);
    try {
      if (hasPasswordProvider) {
        final email = user.email;
        if (email == null || password == null || password.isEmpty) {
          throw const AppFailure(
            FailureKind.permission,
            technical: 'password-required',
          );
        }
        await user.reauthenticateWithCredential(
          fb.EmailAuthProvider.credential(email: email, password: password),
        );
        return;
      }
      await user.reauthenticateWithCredential(await _googleCredential());
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> linkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw const AppFailure(FailureKind.permission);
    if (hasGoogleProvider) return;
    final credential = await _googleCredential();
    try {
      await user.linkWithCredential(credential);
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (hasGoogleProvider || _googleInitialized) {
        await _google.signOut();
      }
    } on Object {
      // Signing out of Firebase is what matters; the Google client can be
      // unavailable on devices without Play services.
    }
    await _auth.signOut();
  }

  AuthUser _require(fb.User? user) {
    final mapped = _map(user);
    if (mapped == null) {
      throw const AppFailure(FailureKind.unknown, technical: 'no-user');
    }
    return mapped;
  }

  Future<fb.AuthCredential> _googleCredential() async {
    try {
      if (!_googleInitialized) {
        await _google.initialize();
        _googleInitialized = true;
      }
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AppFailure(
          FailureKind.permission,
          technical: 'missing-google-id-token',
        );
      }
      return fb.GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AppFailure(FailureKind.cancelled);
      }
      throw AppFailure(
        FailureKind.permission,
        technical: 'google-${error.code.name}',
      );
    }
  }

  /// Keeps the Firebase error code in [AppFailure.technical] so the UI can show
  /// a precise, localized message without leaking implementation details.
  AppFailure _failure(fb.FirebaseAuthException error) {
    final kind = switch (error.code) {
      'network-request-failed' => FailureKind.network,
      'too-many-requests' => FailureKind.server,
      'user-disabled' => FailureKind.permission,
      'requires-recent-login' => FailureKind.permission,
      'wrong-password' ||
      'invalid-credential' ||
      'invalid-email' ||
      'email-already-in-use' ||
      'weak-password' ||
      'user-not-found' ||
      'credential-already-in-use' ||
      'provider-already-linked' ||
      'account-exists-with-different-credential' => FailureKind.permission,
      _ => FailureKind.unknown,
    };
    return AppFailure(kind, technical: error.code);
  }
}
