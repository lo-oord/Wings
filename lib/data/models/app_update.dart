/// One published release of Wings, read from the website's update manifest.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.build,
    required this.apkUrl,
    this.apkUrls = const <String, String>{},
    this.pageUrl = '',
    this.mandatory = false,
    this.welcome = '',
    this.notesAr = const <String>[],
    this.notesEn = const <String>[],
  });

  final String version;
  final int build;

  /// Universal package, used when the device ABI is unknown.
  final String apkUrl;

  /// Per-architecture packages keyed by `arm64-v8a`, `armeabi-v7a`,
  /// `x86_64` and `universal`.
  final Map<String, String> apkUrls;
  final String pageUrl;
  final bool mandatory;

  /// Shown once above the release notes ("أهلاً بك في Wings").
  final String welcome;
  final List<String> notesAr;
  final List<String> notesEn;

  String get id => '$version+$build';

  /// The smallest package that runs on this device.
  ///
  /// The device reports its ABIs in preference order, so the first match wins;
  /// an unknown or unsupported device falls back to the universal build.
  String urlForAbi(Iterable<String> abis) {
    for (final abi in abis) {
      final match = apkUrls[abi.toLowerCase().trim()];
      if (match != null && match.isNotEmpty) return match;
    }
    final universal = apkUrls['universal'];
    if (universal != null && universal.isNotEmpty) return universal;
    return apkUrl;
  }

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

    final rawUrls = json['apk_urls'] ?? json['apkUrls'];
    final apkUrls = <String, String>{
      if (rawUrls is Map)
        for (final entry in rawUrls.entries)
          if (entry.value.toString().trim().isNotEmpty)
            entry.key.toString().toLowerCase(): entry.value.toString().trim(),
    };

    return AppUpdate(
      version: version,
      build: (json['build'] as num?)?.toInt() ?? 1,
      apkUrl: apkUrl,
      apkUrls: apkUrls,
      pageUrl: (json['page_url'] ?? json['pageUrl'] ?? '').toString(),
      mandatory: json['mandatory'] == true,
      welcome: (json['welcome'] ?? '').toString(),
      notesAr: notes(json['notes_ar'] ?? json['notesAr'], 'ar'),
      notesEn: notes(json['notes_en'] ?? json['notesEn'], 'en'),
    );
  }
}
