import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/admin_models.dart';
import 'admin_providers.dart';

/// The single account that owns the product.
///
/// `config/owner` is a one-field public document (`uid`) so every client can
/// recognise the owner without exposing the staff collection. The owner writes
/// it on first sign-in after this update, and the Firestore rules let only an
/// `owner` staff role create or change it.
final ownerUidProvider = FutureProvider<String>((ref) async {
  final db = FirebaseFirestore.instance;
  final doc = db.collection('config').doc('owner');
  try {
    final snapshot = await doc.get();
    final stored = snapshot.data()?['uid'] as String? ?? '';
    if (stored.isNotEmpty) return stored;
    final role = await ref.read(staffRoleProvider.future);
    final me = ref.read(authProvider)?.id;
    if (role == StaffRole.owner && me != null) {
      await doc.set(<String, dynamic>{'uid': me});
      return me;
    }
  } on Object {
    // Older deployments without the document keep every feature working.
  }
  return '';
});

/// True only when [uid] is the protected owner account.
final isOwnerAccountProvider = Provider.family<bool, String>((ref, uid) {
  final owner = ref.watch(ownerUidProvider).value ?? '';
  return owner.isNotEmpty && owner == uid;
});
