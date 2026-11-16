/// Endpoint configuration for the catalogue backend.
///
/// The catalogue is served by a public, read-only index. The keys below are
/// public client keys published by that service for read access; they rotate,
/// so the client refreshes them at runtime from the public configuration
/// document (`Settings/constants`). Override any value at build time with
/// `--dart-define` if the operator issues new ones.
///
/// This file is internal infrastructure: none of these values are shown in the
/// interface, and no authenticated/private endpoint is accessed.
abstract final class WingsConfig {
  static const String firestoreProject = String.fromEnvironment(
    'WINGS_FIRESTORE_PROJECT',
    defaultValue: 'animewitcher-1c66d',
  );

  static const String firestoreClientKey = String.fromEnvironment(
    'WINGS_FIRESTORE_KEY',
    defaultValue: 'AIzaSyAcbWRwfFNnCpoydDXlEALWnM_TYVcJOMU',
  );

  /// Bootstrap search credentials, replaced by runtime values when available.
  static const String bootstrapSearchAppId = String.fromEnvironment(
    'WINGS_SEARCH_APP_ID',
    defaultValue: 'TVNESH8OZY',
  );

  static const String bootstrapSearchKey = String.fromEnvironment(
    'WINGS_SEARCH_KEY',
    defaultValue: '54098ae17637c217f486e6165c8a913c',
  );

  static const String searchHostSuffix = '-dsn.algolia.net';

  /// Indexes used by the catalogue layer.
  static const String indexSeries = 'series';
  static const String indexRecent = 'recent';
  static const String indexByNewest = 'series_date_created';
  static const String indexByOldest = 'series_year_asc';
  static const String indexByTitle = 'series_name_asc';
  static const String indexByPopularity = 'series_fav_count_desc';
  static const String indexByRating = 'best_mal_ranked';

  static String firestoreDocumentUrl(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://firestore.googleapis.com/v1/projects/$firestoreProject'
        '/databases/(default)/documents/$encoded';
  }

  static String searchUrl(String appId, String index) =>
      'https://$appId$searchHostSuffix/1/indexes/${Uri.encodeComponent(index)}/query';
}
