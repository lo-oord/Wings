import '../../core/storage/local_store.dart';
import '../models/library.dart';

class SettingsRepository {
  SettingsRepository(this._store);

  final LocalStore _store;
  static const String _key = 'app';

  AppSettings load() {
    final raw = _store.getJson(LocalStore.settingsBox, _key);
    if (raw is Map) return AppSettings.fromJson(raw.cast<String, dynamic>());
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) =>
      _store.putJson(LocalStore.settingsBox, _key, settings.toJson());
}
