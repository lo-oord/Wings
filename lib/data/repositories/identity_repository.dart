import 'package:cloud_firestore/cloud_firestore.dart';

import '../username/username_rules.dart';

/// Blocked identities and the review request a blocked person can send.
///
/// An email or handle can be blocked before any account exists, so the checks
/// are exact document lookups (`emailBlocks/{email}`, `blockedUsernames/{handle}`)
/// rather than a query, and the review request is an append-only document the
/// person may create without an account.
class IdentityRepository {
  IdentityRepository(this._db);

  final FirebaseFirestore _db;

  static const String emailBlocksCollection = 'emailBlocks';
  static const String usernameBlocksCollection = 'blockedUsernames';
  static const String reviewsCollection = 'identityReviews';

  /// True only when the exact address has a block document. A read failure is
  /// treated as "not blocked" so a network hiccup can never stop a valid
  /// registration; the security rules still enforce the block on write.
  Future<bool> emailBlocked(String email) async {
    final id = email.trim().toLowerCase();
    if (id.isEmpty) return false;
    try {
      final doc = await _db.collection(emailBlocksCollection).doc(id).get();
      return doc.exists;
    } on Object {
      return false;
    }
  }

  Future<bool> usernameBlocked(String username) async {
    final id = UsernameRules.normalize(username);
    if (id.isEmpty) return false;
    try {
      final doc = await _db.collection(usernameBlocksCollection).doc(id).get();
      return doc.exists;
    } on Object {
      return false;
    }
  }

  /// Sends a review request to the Wings team.
  ///
  /// [counterpart] carries the other half of the identity: the last handle
  /// typed with a blocked email, or the last email typed with a blocked handle.
  Future<void> requestReview({
    required bool email,
    required String value,
    required String reason,
    String counterpart = '',
    String requesterUid = '',
  }) async {
    await _db.collection(reviewsCollection).add(<String, dynamic>{
      'type': email ? 'email' : 'username',
      'value': value.trim(),
      'reason': reason.trim(),
      'counterpart': counterpart.trim(),
      'requesterUid': requesterUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
