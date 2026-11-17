import 'package:cloud_firestore/cloud_firestore.dart';

import '../username/username_rules.dart';

enum UsernameStatus { invalid, checking, available, taken, error }

/// Result of a live availability check shown under the username field.
class UsernameAvailability {
  const UsernameAvailability(
    this.status, {
    this.normalized = '',
    this.problem,
    this.suggestions = const <String>[],
  });

  final UsernameStatus status;
  final String normalized;
  final UsernameProblem? problem;
  final List<String> suggestions;
}

class UsernameTakenException implements Exception {
  const UsernameTakenException(this.normalized);

  final String normalized;
}

class UsernameOwnershipException implements Exception {
  const UsernameOwnershipException();
}

/// Username registry backed by `usernames/{normalizedUsername}`.
///
/// Uniqueness is enforced by atomic transactions, never by a check followed by
/// a separate write: two clients claiming the same handle can only win one
/// transaction.
class UsernameRepository {
  UsernameRepository(this._db);

  final FirebaseFirestore _db;

  static const String collection = 'usernames';

  DocumentReference<Map<String, dynamic>> _doc(String normalized) =>
      _db.collection(collection).doc(normalized);

  Future<bool> isAvailable(String normalized) async {
    final snapshot = await _doc(normalized)
        .get(const GetOptions(source: Source.server));
    return !snapshot.exists;
  }

  /// Validates locally first, then performs a single exact-document lookup.
  /// Candidates are never queried as a collection, so the registry cannot be
  /// enumerated by clients.
  Future<UsernameAvailability> check(String raw) async {
    final validation = UsernameRules.validate(raw);
    if (!validation.ok) {
      return UsernameAvailability(
        UsernameStatus.invalid,
        normalized: validation.normalized,
        problem: validation.problem,
      );
    }
    final available = await isAvailable(validation.normalized);
    if (available) {
      return UsernameAvailability(
        UsernameStatus.available,
        normalized: validation.normalized,
      );
    }
    return UsernameAvailability(
      UsernameStatus.taken,
      normalized: validation.normalized,
      suggestions: await suggestions(validation.normalized),
    );
  }

  /// Probes a handful of deterministic alternatives.
  Future<List<String>> suggestions(String raw, {int count = 4}) async {
    final candidates = UsernameRules.suggestions(raw, count: count + 2);
    final result = <String>[];
    for (final candidate in candidates) {
      if (await isAvailable(candidate)) {
        result.add(candidate);
        if (result.length >= count) break;
      }
    }
    return result;
  }

  /// Reserves [normalized] for [uid]. Fails when it belongs to someone else.
  Future<void> reserve({
    required String uid,
    required String normalized,
  }) async {
    await _db.runTransaction((transaction) async {
      final ref = _doc(normalized);
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        final owner = snapshot.data()?['uid'];
        if (owner == uid) return;
        throw UsernameTakenException(normalized);
      }
      transaction.set(ref, <String, dynamic>{
        'uid': uid,
        'username': normalized,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Releases a reservation owned by [uid], ignoring missing documents.
  Future<void> release({
    required String uid,
    required String normalized,
  }) async {
    await _db.runTransaction((transaction) async {
      final ref = _doc(normalized);
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      if (snapshot.data()?['uid'] != uid) {
        throw const UsernameOwnershipException();
      }
      transaction.delete(ref);
    });
  }

  /// Atomically moves the handle: reserve the new one, update the owner profile
  /// and only then drop the previous reservation.
  Future<void> changeUsername({
    required String uid,
    required String? previousNormalized,
    required String nextNormalized,
  }) async {
    final next = UsernameRules.normalize(nextNormalized);
    final previous = previousNormalized == null
        ? null
        : UsernameRules.normalize(previousNormalized);
    await _db.runTransaction((transaction) async {
      final nextRef = _doc(next);
      final nextSnapshot = await transaction.get(nextRef);
      if (nextSnapshot.exists && nextSnapshot.data()?['uid'] != uid) {
        throw UsernameTakenException(next);
      }
      transaction.set(nextRef, <String, dynamic>{
        'uid': uid,
        'username': next,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(_db.collection('users').doc(uid), <String, dynamic>{
        'username': nextNormalized.trim(),
        'normalizedUsername': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (previous != null && previous != next) {
        final previousRef = _doc(previous);
        final previousSnapshot = await transaction.get(previousRef);
        if (previousSnapshot.exists && previousSnapshot.data()?['uid'] == uid) {
          transaction.delete(previousRef);
        }
      }
    });
  }
}
