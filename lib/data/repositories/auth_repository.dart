import 'package:flutter/foundation.dart';

/// Identity of the signed-in account.
///
/// Only values that come from the authentication provider or from the loaded
/// profile are stored here; passwords are never modelled or persisted.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.username = '',
    this.country = '',
    this.emailVerified = false,
    this.hasPassword = false,
    this.hasGoogle = false,
    this.avatarPath,
    this.bio,
  });

  final String id;
  final String email;
  final String displayName;
  final String username;
  final String country;
  final bool emailVerified;
  final DateTime createdAt;

  /// Signed in with an email address and a password.
  final bool hasPassword;

  /// Signed in with Google, either alone or linked to the password account.
  final bool hasGoogle;

  final String? avatarPath;
  final String? bio;

  AuthUser copyWith({
    String? email,
    String? displayName,
    String? username,
    String? country,
    String? avatarPath,
    String? bio,
    bool? emailVerified,
    bool? hasPassword,
    bool? hasGoogle,
  }) => AuthUser(
    id: id,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    username: username ?? this.username,
    country: country ?? this.country,
    emailVerified: emailVerified ?? this.emailVerified,
    hasPassword: hasPassword ?? this.hasPassword,
    hasGoogle: hasGoogle ?? this.hasGoogle,
    createdAt: createdAt,
    avatarPath: avatarPath ?? this.avatarPath,
    bio: bio ?? this.bio,
  );
}

/// Contract for the account service.
///
/// [FirebaseAuthRepository] is the production implementation. Profile data,
/// username reservations and synchronization live in their own repositories;
/// this contract only covers identity.
abstract interface class AuthRepository {
  AuthUser? get currentUser;

  Stream<AuthUser?> get authChanges;

  bool get isProductionBackend;

  bool get emailVerified;

  bool get hasPasswordProvider;

  bool get hasGoogleProvider;

  Future<AuthUser> signIn({required String email, required String password});

  /// Signs in with Google.
  ///
  /// With [createAccount] false an unknown Google account is refused instead of
  /// being created, which is what a sign-in button must do. With it true a
  /// known account is refused instead, so registration never silently signs an
  /// existing account in.
  Future<AuthUser> signInWithGoogle({bool createAccount = false});

  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> setDisplayName(String name);

  Future<void> sendPasswordReset(String email);

  Future<void> sendEmailVerification();

  Future<bool> refreshEmailVerification();

  Future<void> reauthenticate({String? password});

  Future<void> linkGoogle();

  /// Starts adding an email + password to the signed-in account.
  ///
  /// Returns true when the address is already the account's own email (Google
  /// has verified it, so no second verification is needed) and false when a
  /// verification link was sent to the new address. The password stays in
  /// memory only until [completeEmailLink] finishes.
  Future<bool> requestEmailLink({
    required String email,
    required String password,
  });

  /// True when the verification link of a pending email link was used.
  Future<bool> emailLinkVerified();

  /// Links the password provider once the pending address is verified.
  Future<void> completeEmailLink();

  /// Whether an email link is waiting for its verification.
  bool get hasPendingEmailLink;

  Future<void> deleteCurrentUser();

  Future<void> signOut();
}

/// Development-only adapter that keeps a session in memory.
///
/// It exists so the account screens can be exercised without a backend, and it
/// is never used when Firebase is initialized. It is explicitly marked as
/// non-production and nothing is persisted.
class LocalDevelopmentAuthRepository implements AuthRepository {
  LocalDevelopmentAuthRepository();

  AuthUser? _user;
  final Stream<AuthUser?> _changes = const Stream<AuthUser?>.empty();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authChanges => _changes;

  @override
  bool get isProductionBackend => false;

  @override
  bool get emailVerified => _user?.emailVerified ?? false;

  @override
  bool get hasPasswordProvider => _user != null;

  @override
  bool get hasGoogleProvider => false;

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (password.length < 8) {
      throw StateError('invalid credentials');
    }
    _user = AuthUser(
      id: 'local-${email.hashCode}',
      email: email,
      displayName: email.split('@').first,
      username: email.split('@').first,
      country: 'SA',
      emailVerified: true,
      hasPassword: true,
      createdAt: DateTime.now(),
    );
    return _user!;
  }

  @override
  Future<AuthUser> signInWithGoogle({bool createAccount = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _user = AuthUser(
      id: 'local-google',
      email: 'google@example.com',
      displayName: 'Google User',
      username: 'google_user',
      country: 'SA',
      emailVerified: true,
      hasGoogle: true,
      createdAt: DateTime.now(),
    );
    return _user!;
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _user = AuthUser(
      id: 'local-${email.hashCode}',
      email: email,
      displayName: displayName,
      createdAt: DateTime.now(),
    );
    return _user!;
  }

  @override
  Future<void> setDisplayName(String name) async {
    _user = _user?.copyWith(displayName: name);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> sendEmailVerification() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<bool> refreshEmailVerification() async => true;

  @override
  Future<void> reauthenticate({String? password}) async {}

  @override
  Future<void> linkGoogle() async {
    _user = _user?.copyWith(hasGoogle: true);
  }

  @override
  bool get hasPendingEmailLink => false;

  @override
  Future<bool> requestEmailLink({
    required String email,
    required String password,
  }) async => true;

  @override
  Future<bool> emailLinkVerified() async => true;

  @override
  Future<void> completeEmailLink() async {
    _user = _user?.copyWith(hasPassword: true);
  }

  @override
  Future<void> deleteCurrentUser() async {
    _user = null;
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }
}
