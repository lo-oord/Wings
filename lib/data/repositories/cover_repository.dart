import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../core/storage/local_store.dart';

/// Profile cover pictures, stored as bytes inside Firestore because Firebase
/// Storage is unavailable on the Spark plan.
///
/// A cover is a wide 16:10 banner, so it needs more pixels than the avatar. It
/// still has to fit comfortably under Firestore's 1 MiB document limit: the
/// image is recompressed until it is at most [maxBytes] and cached locally per
/// `coverVersion`, exactly like the avatar.
class CoverRepository {
  CoverRepository(this._db, this._store);

  final FirebaseFirestore _db;
  final LocalStore _store;

  /// 480 KB leaves room for Firestore's per-field and document overhead.
  static const int maxBytes = 480 * 1024;

  static const int maxDimension = 1280;

  String _cacheKey(String uid, int version) => 'cover_${uid}_$version';

  /// Downscales a picked image into the cover budget. Returns null when the
  /// file cannot be decoded or cannot be compressed small enough.
  Future<Uint8List?> compressFile(String path) async {
    var width = maxDimension;
    var quality = 78;
    for (var attempt = 0; attempt < 6; attempt++) {
      final bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: width,
        minHeight: (width * 0.625).round(),
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (bytes == null) return null;
      if (bytes.length <= maxBytes) return bytes;
      width = (width * 0.8).round();
      quality = (quality - 8).clamp(40, 80);
      if (width < 320) break;
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
        .doc('cover')
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

  Future<void> save({required String uid, required Uint8List bytes}) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('cover')
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
        .doc('cover')
        .delete();
    await _store.delete(LocalStore.cacheBox, _cacheKey(uid, -1));
  }
}
