import 'dart:convert';

import '../../data/models/app_notification.dart';
import '../storage/local_store.dart';
import 'notification_files.dart';

/// New-episode alerts as they appear inside the app.
///
/// The background worker drops fresh alerts into a JSON queue; this service
/// folds them into the Hive box the UI reads and clears the queue afterwards.
class InAppNotificationsService {
  InAppNotificationsService(this._store);

  final LocalStore _store;

  static String get _box => LocalStore.notificationsBox;

  List<AppNotification> all() {
    final items = <AppNotification>[];
    for (final raw in _store.valuesAsJson(_box)) {
      final item = AppNotification.fromJson(raw);
      if (item.animeId.isNotEmpty) items.add(item);
    }
    items.sort(AppNotification.newestFirst);
    return items;
  }

  int unreadCount() => all().where((item) => !item.read).length;

  Future<void> addAll(Iterable<AppNotification> items) async {
    for (final item in items) {
      await _store.putJson(_box, item.id, item.toJson());
    }
  }

  /// Merges background alerts (including the first run baseline).
  Future<void> pullPending() async {
    final pending = await NotificationFiles.takePending();
    if (pending.isEmpty) return;
    final existing = all().map((item) => item.id).toSet();
    await addAll(pending.where((item) => !existing.contains(item.id)));
  }

  Future<void> markAllRead() async {
    for (final item in all().where((item) => !item.read)) {
      await _store.putJson(_box, item.id, item.copyWith(read: true).toJson());
    }
  }

  Future<void> clear() => _store.clear(_box);

  /// Removes entries for titles the user has deleted from the library.
  Future<void> prune(Iterable<String> animeIds) async {
    final keep = animeIds.toSet();
    for (final item in all()) {
      if (!keep.contains(item.animeId)) {
        await _store.delete(_box, item.id);
      }
    }
  }

  Map<String, dynamic> exportDebug() => <String, dynamic>{
    'count': all().length,
    'unread': unreadCount(),
    'raw': jsonEncode(all().map((item) => item.toJson()).toList()),
  };
}
