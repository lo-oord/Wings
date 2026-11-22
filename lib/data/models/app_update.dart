/// One published release of Wings, read from the website's update manifest.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.build,
    required this.apkUrl,
    this.pageUrl = '',
    this.mandatory = false,
    this.welcome = '',
    this.notesAr = const <String>[],
    this.notesEn = const <String>[],
  });

  final String version;
  final int build;
  final String apkUrl;
  final String pageUrl;
  final bool mandatory;

  /// Shown once above the release notes ("أهلاً بك في Wings").
  final String welcome;
  final List<String> notesAr;
  final List<String> notesEn;

  String get id => '$version+$build';

  /// True when this release is newer than the running build.
  bool isNewerThan({
    required String currentVersion,
    required int currentBuild,
  }) {
    final remote = _segments(version);
    final local = _segments(currentVersion);
    for (var index = 0; index < 3; index++) {
      final left = index < remote.length ? remote[index] : 0;
      final right = index < local.length ? local[index] : 0;
      if (left != right) return left > right;
    }
    return build > currentBuild;
  }

  static List<int> _segments(String value) => value
      .split('+')
      .first
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList(growable: false);

  static AppUpdate? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final version = (json['version'] ?? '').toString().trim();
    final apkUrl = (json['apk_url'] ?? json['apkUrl'] ?? '').toString().trim();
    if (version.isEmpty || apkUrl.isEmpty) return null;
    List<String> notes(Object? value, String locale) {
      if (value is Map) return notes(value[locale], locale);
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
      return const <String>[];
    }

    return AppUpdate(
      version: version,
      build: (json['build'] as num?)?.toInt() ?? 1,
      apkUrl: apkUrl,
      pageUrl: (json['page_url'] ?? json['pageUrl'] ?? '').toString(),
      mandatory: json['mandatory'] == true,
      welcome: (json['welcome'] ?? '').toString(),
      notesAr: notes(json['notes_ar'] ?? json['notesAr'], 'ar'),
      notesEn: notes(json['notes_en'] ?? json['notesEn'], 'en'),
    );
  }
}
