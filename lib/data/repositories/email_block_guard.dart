import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/email_hash.dart';

/// Registration-side email denylist check.
///
/// The client never reads `emailBlocks`: it asks Firestore to create an empty
/// marker in `emailChecks/{hash}`, which the rules only permit while the
/// address is **not** blocked. A refused write therefore means “blocked”, and
/// the denylist itself is never exposed to the app.
abstract final class EmailBlockGuard {
  /// True when the owner blocked this address.
  ///
  /// Network failures return false on purpose: an offline registration should
  /// not be reported as a block, and the `users` creation rule re-checks the
  /// hash on the server anyway.
  static Future<bool> isBlocked(FirebaseFirestore db, String email) async {
    if (email.trim().isEmpty) return false;
    final hash = hashEmail(email);
    final ref = db.collection('emailChecks').doc(hash);
    try {
      await ref.set(<String, dynamic>{'hash': hash});
    } on FirebaseException catch (error) {
      return error.code == 'permission-denied';
    } on Object {
      return false;
    }
    try {
      await ref.delete();
    } on Object {
      // The marker is empty; a later probe removes it.
    }
    return false;
  }
}
