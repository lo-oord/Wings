import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/storage/local_store.dart';

/// Watch counters for episodes and whole titles.
///
/// Firestore has no server-side counters on the free plan (no Cloud Functions),
/// so the client increments a deterministic document. To keep the database
/// cheap and resistant to abuse every guard is applied on the client *and* in
/// `firestore.rules`:
///
/// * one view per episode per device per [window],
/// * a counter document holds a single integer, so an increment is one write,
/// * reads are cached locally for [cacheTtl], so opening a screen repeatedly
///   costs no extra reads,
/// * only a single increment is allowed per request by the rules (no jumping
///   from 10 to 10 000 in one write).
class ViewsRepository {
  ViewsRepository(this._db, this._store);

  final FirebaseFirestore _db;
  final LocalStore _store;

  /// A device can only raise an episode's counter once in this window, which
  /// stops a replayed request or a re-opened screen from inflating views.
  static const Duration window = Duration(hours: 8);

  /// How long a displayed number may be reused before a new read happens.
  static const Duration cacheTtl = Duration(minutes: 5);

  DocumentReference<Map<String, dynamic>> _episodeCounter(String id) =>
      _db.collection('episodes').doc(id).collection('stats').doc('views');

  DocumentReference<Map<String, dynamic>> _animeCounter(String id) =>
      _db.collection('anime').doc(id).collection('stats').doc('views');

  String _cacheKey(String scope, String id) => 'views_${scope}_$id';

  String _guardKey(String scope, String id) => 'viewed_${scope}_$id';

  bool _windowElapsed(String scope, String id) {
    final raw = _store.getString(LocalStore.cacheBox, _guardKey(scope, id));
    final last = int.tryParse(raw ?? '');
    if (last == null) return true;
    return DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        ) >
        window;
  }

  Future<void> _markViewed(String scope, String id) => _store.setString(
    LocalStore.cacheBox,
    _guardKey(scope, id),
    DateTime.now().millisecondsSinceEpoch.toString(),
  );

  int? _cached(String scope, String id) {
    final value = _store.readCache(_cacheKey(scope, id));
    return value is num ? value.toInt() : null;
  }

  Future<void> _storeCount(String scope, String id, int count) =>
      _store.putCache(_cacheKey(scope, id), count, ttl: cacheTtl);

  /// Reads one counter, using the local cache first. A missing counter (a new
  /// episode nobody watched yet) reads as zero instead of an error.
  Future<int> _count(
    DocumentReference<Map<String, dynamic>> ref, {
    required String scope,
    required String id,
    bool allowCache = true,
  }) async {
    if (allowCache) {
      final cached = _cached(scope, id);
      if (cached != null) return cached;
    }
    try {
      final snapshot = await ref.get();
      final value = snapshot.data()?['count'];
      final count = value is num ? value.toInt().clamp(0, 1 << 53) : 0;
      await _storeCount(scope, id, count);
      return count;
    } on Object {
      // Offline: keep the last known number rather than showing a wrong zero.
      final stale = _store.readCache(_cacheKey(scope, id), allowStale: true);
      return stale is num ? stale.toInt() : 0;
    }
  }

  Future<int> episodeViews(String episodeId, {bool allowCache = true}) =>
      _count(
        _episodeCounter(episodeId),
        scope: 'episode',
        id: episodeId,
        allowCache: allowCache,
      );

  Future<int> animeViews(String animeId, {bool allowCache = true}) => _count(
    _animeCounter(animeId),
    scope: 'anime',
    id: animeId,
    allowCache: allowCache,
  );

  /// Counts one view for the episode (and the title) after playback actually
  /// started. Each increment is fire-and-forget: a rejected write must never
  /// interrupt playback.
  Future<void> registerPlayback({
    required String episodeId,
    required String animeId,
  }) async {
    final tasks = <Future<void>>[];
    if (episodeId.isNotEmpty && _windowElapsed('episode', episodeId)) {
      tasks.add(
        _increment(_episodeCounter(episodeId)).then((_) async {
          await _markViewed('episode', episodeId);
          final cached = _cached('episode', episodeId);
          if (cached != null) {
            await _storeCount('episode', episodeId, cached + 1);
          }
        }),
      );
    }
    if (animeId.isNotEmpty && _windowElapsed('anime', animeId)) {
      tasks.add(
        _increment(_animeCounter(animeId)).then((_) async {
          await _markViewed('anime', animeId);
          final cached = _cached('anime', animeId);
          if (cached != null) {
            await _storeCount('anime', animeId, cached + 1);
          }
        }),
      );
    }
    if (tasks.isEmpty) return;
    try {
      await Future.wait(tasks);
    } on Object {
      // Offline or denied: the counter simply stays where it was.
    }
  }

  /// Creates the counter at 1 or adds exactly one. The rules accept nothing
  /// else, so a tampered client cannot write an arbitrary number.
  Future<void> _increment(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.update(<String, dynamic>{
        'count': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') rethrow;
      await ref.set(<String, dynamic>{
        'count': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
