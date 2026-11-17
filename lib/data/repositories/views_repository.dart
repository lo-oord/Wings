import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/storage/local_store.dart';

/// Real watch counters for episodes and whole titles.
///
/// Earlier builds incremented a shared integer document on every screen open,
/// which could be inflated by retries, reinstalls, or a client that was opened
/// by mistake. A view is now an *identity*, not a write:
///
/// * watching an episode for [watchDelay] stores one document at
///   `episodes/{id}/stats/watch/viewers/{uid}`,
/// * the displayed number is a `count()` aggregation over those documents, so
///   repeating the same view can never raise it,
/// * rules only allow a user to create their own viewer document (never to
///   update or delete one), so the number cannot be tampered with,
/// * the count is cached for [cacheTtl] because an aggregation is one billed
///   read per 1000 viewers.
///
/// The legacy `stats/views` counters are intentionally ignored: they were the
/// source of the inflated, fake numbers.
class ViewsRepository {
  ViewsRepository(this._db, this._store);

  final FirebaseFirestore _db;
  final LocalStore _store;

  /// How long a displayed number may be reused before a new read happens.
  static const Duration cacheTtl = Duration(minutes: 5);

  /// A device watches the same episode again after this long and it is still
  /// the same viewer, so the local guard only saves a pointless write.
  static const Duration localMarkTtl = Duration(hours: 24);

  /// Playback has to actually run before a view is recorded.
  static const Duration watchDelay = Duration(seconds: 15);

  static const String episodeScope = 'episode';
  static const String animeScope = 'anime';

  DocumentReference<Map<String, dynamic>> _root(String scope, String id) =>
      scope == episodeScope
      ? _db.collection('episodes').doc(id)
      : _db.collection('anime').doc(id);

  CollectionReference<Map<String, dynamic>> _viewers(String scope, String id) =>
      _root(scope, id).collection('stats').doc('watch').collection('viewers');

  String _cacheKey(String scope, String id) => 'watch_count_${scope}_$id';

  String _markKey(String scope, String id, String uid) =>
      'watched_${scope}_${id}_$uid';

  bool _recentlyMarked(String scope, String id, String uid) {
    final raw = _store.getString(LocalStore.cacheBox, _markKey(scope, id, uid));
    final last = int.tryParse(raw ?? '');
    if (last == null) return false;
    return DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        ) <
        localMarkTtl;
  }

  Future<void> _markLocally(String scope, String id, String uid) =>
      _store.setString(
        LocalStore.cacheBox,
        _markKey(scope, id, uid),
        DateTime.now().millisecondsSinceEpoch.toString(),
      );

  int? _cached(String scope, String id) {
    final value = _store.readCache(_cacheKey(scope, id));
    return value is num ? value.toInt() : null;
  }

  Future<void> _storeCount(String scope, String id, int count) =>
      _store.putCache(_cacheKey(scope, id), count, ttl: cacheTtl);

  Future<int> _count(String scope, String id, {bool allowCache = true}) async {
    if (allowCache) {
      final cached = _cached(scope, id);
      if (cached != null) return cached;
    }
    try {
      final snapshot = await _viewers(scope, id).count().get();
      final count = (snapshot.count ?? 0).clamp(0, 1 << 53);
      await _storeCount(scope, id, count);
      return count;
    } on Object {
      // Offline: keep the last known number rather than showing a wrong zero.
      final stale = _store.readCache(_cacheKey(scope, id), allowStale: true);
      return stale is num ? stale.toInt() : 0;
    }
  }

  Future<int> episodeViews(String episodeId, {bool allowCache = true}) =>
      _count(episodeScope, episodeId, allowCache: allowCache);

  Future<int> animeViews(String animeId, {bool allowCache = true}) =>
      _count(animeScope, animeId, allowCache: allowCache);

  /// Records that [uid] watched this episode. Only called after playback has
  /// been running for [watchDelay]; a guest (no uid) is never counted.
  ///
  /// Every write is best effort: a rejected or offline write must never
  /// interrupt playback.
  Future<void> registerPlayback({
    required String episodeId,
    required String animeId,
    required String uid,
  }) async {
    if (uid.isEmpty) return;
    final tasks = <Future<void>>[];
    if (episodeId.isNotEmpty) {
      tasks.add(_markViewer(episodeScope, episodeId, uid));
    }
    if (animeId.isNotEmpty) {
      tasks.add(_markViewer(animeScope, animeId, uid));
    }
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
  }

  Future<void> _markViewer(String scope, String id, String uid) async {
    if (_recentlyMarked(scope, id, uid)) return;
    try {
      await _viewers(scope, id).doc(uid).set(<String, dynamic>{
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _markLocally(scope, id, uid);
      final cached = _cached(scope, id);
      if (cached != null) await _storeCount(scope, id, cached + 1);
    } on FirebaseException catch (error) {
      // `permission-denied` means this viewer document already exists (rules
      // reject updates), so the view is already counted.
      if (error.code == 'permission-denied') {
        await _markLocally(scope, id, uid);
      }
    } on Object {
      // Offline or any other failure: the number stays where it was.
    }
  }
}
