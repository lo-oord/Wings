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

  /// OAuth **web** client id from `android/app/google-services.json`
  /// (`client_type: 3`). `google_sign_in` 7.x only returns a Firebase-usable
  /// `idToken` on Android when the sign-in client is initialised with a
  /// server client id; without it `authentication.idToken` is null and every
  /// Google sign-in fails. Override it with
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` if the Firebase project
  /// changes.
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '469028233998-3jga5u4v81dh9ftmri6li3a8p8j3bfd7.apps.googleusercontent.com',
  );

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
    final providers = user.providerData
        .map((provider) => provider.providerId)
        .toSet();
    return AuthUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      createdAt: user.metadata.creationTime ?? DateTime.now(),
      emailVerified: user.emailVerified,
      hasPassword: providers.contains('password'),
      hasGoogle: providers.contains('google.com'),
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
      // A missing account must never be reported as a bad password, and a
      // sign-in attempt must never create one: the account has to exist.
      if (error.code == 'user-not-found') {
        throw const AppFailure(
          FailureKind.permission,
          technical: 'account-not-found',
        );
      }
      throw _failure(error);
    }
  }

  /// Signs in with Google without ever creating an account unless
  /// [createAccount] is set.
  ///
  /// `signInWithCredential` creates the Firebase user when the Google account
  /// is new. Doing that from a sign-in button left an account behind for every
  /// stranger who tapped it, so a new user is removed again and reported as
  /// "no account"; registration refuses the mirror case.
  @override
  Future<AuthUser> signInWithGoogle({bool createAccount = false}) async {
    final credential = await _googleCredential();
    fb.UserCredential result;
    try {
      result = await _auth.signInWithCredential(credential);
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
    final isNew = result.additionalUserInfo?.isNewUser ?? false;
    if (isNew && !createAccount) {
      await _discardFreshGoogleUser(result.user);
      throw const AppFailure(
        FailureKind.permission,
        technical: 'google-account-not-found',
      );
    }
    if (!isNew && createAccount) {
      // Registration must not silently sign an existing account in.
      try {
        await _auth.signOut();
      } on Object {
        // The next attempt recovers either way.
      }
      throw const AppFailure(
        FailureKind.permission,
        technical: 'google-account-exists',
      );
    }
    return _require(result.user);
  }

  /// Deletes the user `signInWithCredential` just created for a Google account
  /// that is not registered in Wings.
  Future<void> _discardFreshGoogleUser(fb.User? user) async {
    try {
      await user?.delete();
    } on Object {
      // The token is fresh, so a delete failure is rare; sign out instead of
      // leaving the app on an account it did not offer to create.
      try {
        await _auth.signOut();
      } on Object {
        // Nothing else to do.
      }
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
      // Wings now tells the reader when no account uses that address, instead
      // of claiming a message was sent to an inbox that will never receive it.
      if (error.code == 'user-not-found') {
        throw const AppFailure(
          FailureKind.permission,
          technical: 'account-not-found',
        );
      }
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
      // `linkWithCredential` refuses a Google account that already belongs to
      // another Wings user (`credential-already-in-use`), so one Google account
      // can never end up on two profiles.
      await user.linkWithCredential(credential);
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  // ------------------------------------------------------- email linking

  String? _pendingEmail;
  String? _pendingPassword;

  @override
  bool get hasPendingEmailLink => _pendingEmail != null;

  @override
  Future<bool> requestEmailLink({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const AppFailure(FailureKind.permission);
    final address = email.trim();
    if (password.length < 8) {
      throw const AppFailure(
        FailureKind.permission,
        technical: 'weak-password',
      );
    }
    _pendingEmail = address;
    _pendingPassword = password;
    // The Google address was already verified by Google itself.
    if (address.toLowerCase() == (user.email ?? '').toLowerCase()) return true;
    try {
      await _verifyBeforeUpdate(user, address);
      return false;
    } on fb.FirebaseAuthException catch (error) {
      _pendingEmail = null;
      _pendingPassword = null;
      throw _failure(error);
    }
  }

  /// Sends the verification link that Firebase uses before changing an email.
  /// A stale session (`requires-recent-login`) is refreshed with the Google
  /// account once, so a long-running session does not dead-end here.
  Future<void> _verifyBeforeUpdate(fb.User user, String address) async {
    try {
      await user.verifyBeforeUpdateEmail(address);
    } on fb.FirebaseAuthException catch (error) {
      if (error.code != 'requires-recent-login') rethrow;
      await user.reauthenticateWithCredential(await _googleCredential());
      await user.verifyBeforeUpdateEmail(address);
    }
  }

  @override
  Future<bool> emailLinkVerified() async {
    final pending = _pendingEmail;
    final user = _auth.currentUser;
    if (pending == null || user == null) return false;
    try {
      await user.reload();
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
    final current = _auth.currentUser;
    return (current?.email ?? '').toLowerCase() == pending.toLowerCase() &&
        (current?.emailVerified ?? false);
  }

  @override
  Future<void> completeEmailLink() async {
    final pending = _pendingEmail;
    final password = _pendingPassword;
    final user = _auth.currentUser;
    if (pending == null || password == null || user == null) {
      throw const AppFailure(FailureKind.permission, technical: 'no-user');
    }
    try {
      await user.linkWithCredential(
        fb.EmailAuthProvider.credential(email: pending, password: password),
      );
    } on fb.FirebaseAuthException catch (error) {
      throw _failure(error);
    } finally {
      _pendingEmail = null;
      _pendingPassword = null;
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
      if (_googleInitialized) {
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
        await _google.initialize(serverClientId: serverClientId);
        _googleInitialized = true;
      }
      if (!_google.supportsAuthenticate()) {
        throw const AppFailure(
          FailureKind.permission,
          technical: 'google-unsupported-platform',
        );
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
