import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../core/storage/local_store.dart';

/// Profile pictures are stored inside Firestore as bytes because Firebase
/// Storage is not available on the Spark plan.
///
/// Every picture is downscaled and recompressed until it fits [maxBytes], which
/// keeps the document far below Firestore's 1 MiB limit. The bytes live in
/// `users/{uid}/private/avatar` so a profile read never downloads an image, and
/// decoded images are cached locally per `photoVersion`.
class AvatarRepository {
  AvatarRepository(this._db, this._store);

  final FirebaseFirestore _db;
  final LocalStore _store;

  /// Conservative budget: 160 KB including Firestore field overhead.
  static const int maxBytes = 160 * 1024;

  static const int maxDimension = 512;

  String _cacheKey(String uid, int version) => 'avatar_${uid}_$version';

  /// Compresses an image file into a Firestore-safe byte budget.
  Future<Uint8List?> compressFile(String path) async {
    var width = maxDimension;
    var quality = 82;
    for (var attempt = 0; attempt < 5; attempt++) {
      final bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: width,
        minHeight: width,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (bytes == null) return null;
      if (bytes.length <= maxBytes) return bytes;
      width = (width * 0.78).round();
      quality = (quality - 10).clamp(40, 82);
      if (width < 96) break;
    }
    return null;
  }

  Future<Uint8List?> cached({required String uid, required int version}) {
    final raw = _store.getString(LocalStore.cacheBox, _cacheKey(uid, version));
    if (raw == null) return Future<Uint8List?>.value();
    try {
      return Future<Uint8List?>.value(base64Decode(raw));
    } on FormatException {
      return Future<Uint8List?>.value();
    }
  }

  /// Reads the avatar, preferring the local cache. Returns null when the user
  /// has no picture or the read is not permitted.
  Future<Uint8List?> fetch({
    required String uid,
    required int version,
    bool allowServer = true,
  }) async {
    final local = await cached(uid: uid, version: version);
    if (local != null) return local;
    if (!allowServer) return null;
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('avatar')
        .get();
    final blob = snapshot.data()?['bytes'];
    final bytes = blob is Blob ? blob.bytes : null;
    if (bytes == null) return null;
    await _store.setString(
      LocalStore.cacheBox,
      _cacheKey(uid, version),
      base64Encode(bytes),
    );
    return bytes;
  }

  /// Stores the compressed picture owned by [uid]. The caller bumps the
  /// profile `photoVersion` so other devices invalidate their cache.
  Future<void> save({required String uid, required Uint8List bytes}) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('avatar')
        .set(<String, dynamic>{
          'bytes': Blob(bytes),
          'byteSize': bytes.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    await _store.setString(
      LocalStore.cacheBox,
      _cacheKey(uid, -1),
      base64Encode(bytes),
    );
  }

  Future<void> remove(String uid) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('avatar')
        .delete();
    await _store.delete(LocalStore.cacheBox, _cacheKey(uid, -1));
  }
}
