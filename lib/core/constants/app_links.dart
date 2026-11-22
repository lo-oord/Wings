/// Stable public addresses for Wings.
///
/// They live in one place so a shared link, the in-app legal screens and the
/// update check all point at the same website.
abstract final class AppLinks {
  static const String site = 'https://wingsapp.vercel.app';
  static const String privacy = '$site/privacy';
  static const String security = '$site/security';
  static const String terms = '$site/terms';
  static const String support = '$site/support';
  static const String download = '$site/download';
  static const String changelog = '$site/changelog';
  static const String updatesManifest = '$site/updates/latest.json';
  static const String github = 'https://github.com/lo-oord/Wings';
  static const String releases = '$github/releases/latest';

  /// Opens the app when it is installed, and the website otherwise. Both the
  /// website and the installed app understand the same `/open` query.
  static String open({
    required String type,
    required String id,
    String? extra,
  }) =>
      '$site/open?type=${Uri.encodeComponent(type)}'
      '&id=${Uri.encodeComponent(id)}'
      '${extra == null ? '' : '&extra=${Uri.encodeComponent(extra)}'}';

  static String anime(String id) => open(type: 'anime', id: id);

  static String post(String id) => open(type: 'post', id: id);

  static String profile(String uid) => open(type: 'user', id: uid);

  static String episode({required String animeId, required String episodeId}) =>
      open(type: 'watch', id: animeId, extra: episodeId);

  static String tag(String slug) => open(type: 'tag', id: slug);
}
