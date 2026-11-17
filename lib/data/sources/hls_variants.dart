import 'package:dio/dio.dart';

/// One rendition published by an HLS master playlist.
typedef HlsVariant = ({String quality, String url});

final Dio _dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
    followRedirects: true,
    maxRedirects: 5,
    validateStatus: (status) => status != null && status < 400,
  ),
);

/// Reads the quality ladder of a master playlist.
///
/// Many providers publish a single `.m3u8` link that is really a master
/// playlist pointing at several renditions. Playing that link directly hands
/// the choice to the platform player, so the app showed one entry and could
/// not offer "1080p / 720p / 480p". Expanding the ladder here is what makes
/// every quality selectable. A media playlist (no `#EXT-X-STREAM-INF`) or a
/// failed request simply returns an empty list and the caller keeps the
/// original link.
Future<List<HlsVariant>> hlsVariants(
  String url, {
  Map<String, String> headers = const <String, String>{},
}) async {
  if (!url.contains('.m3u8')) return const <HlsVariant>[];
  try {
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: <String, String>{
          ...headers,
          'Accept': 'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
        },
      ),
    );
    final text = response.data;
    if (text == null || !text.contains('#EXT-X-STREAM-INF')) {
      return const <HlsVariant>[];
    }
    final base = Uri.tryParse(url);
    if (base == null) return const <HlsVariant>[];

    final variants = <HlsVariant>[];
    String? pending;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        pending = _qualityLabel(line);
      } else if (!line.startsWith('#') && pending != null) {
        variants.add((quality: pending, url: base.resolve(line).toString()));
        pending = null;
      }
    }
    return variants;
  } on Object {
    return const <HlsVariant>[];
  }
}

String _qualityLabel(String tag) {
  final name = RegExp(r'NAME="([^"]+)"').firstMatch(tag)?.group(1);
  if (name != null && name.trim().isNotEmpty) return name.trim();
  final height = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(tag)?.group(1);
  if (height != null) return '${height}p';
  return 'HD';
}
