import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;
}

/// Contract for account services.
///
/// A production implementation (Firebase, Supabase, or a custom backend) plugs
/// in here without any screen changes. No implementation is shipped that talks
/// to a network, and no credentials are stored on device.
abstract interface class AuthRepository {
  AuthUser? get currentUser;

  Stream<AuthUser?> get authChanges;

  bool get isProductionBackend;

  Future<AuthUser> signIn({required String email, required String password});

  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> verifyEmail();

  Future<void> signOut();

  Future<void> deleteAccount();
}

/// Development-only adapter that keeps a session in memory.
///
/// It exists so the account screens, validation and profile states can be
/// exercised without a backend. It is explicitly marked as non-production and
/// nothing is persisted, so no fake account survives a restart.
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
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (password.length < 8) {
      throw const AppFailure(
        FailureKind.unknown,
        technical: 'invalid credentials',
      );
    }
    _user = AuthUser(
      id: 'local-${email.hashCode}',
      email: email,
      displayName: email.split('@').first,
      createdAt: DateTime.now(),
    );
    return _user!;
  }

  @override
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
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
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> verifyEmail() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  Future<void> deleteAccount() async {
    _user = null;
  }
}
