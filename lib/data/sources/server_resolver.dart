import 'package:dio/dio.dart';

import '../../core/constants/network_constants.dart';
import '../models/anime.dart';

/// Turns a published server entry into a direct media URL where possible.
///
/// Only servers that expose their own public file endpoint are resolved.
/// Anything else is reported as browser-only instead of pretending it plays.
class ServerResolver {
  ServerResolver(this._dio);

  final Dio _dio;

  Future<ResolvedStream?> resolve(StreamServer server) async {
    if (server.requiresBrowser) return null;
    try {
      return switch (server.flavor) {
        ServerFlavor.direct => _direct(server),
        ServerFlavor.pixelDrain => await _pixelDrain(server),
        ServerFlavor.mediaFire => await _mediaFire(server),
        ServerFlavor.streamTape => null,
        ServerFlavor.browser => null,
      };
    } on DioException {
      return null;
    } on Object {
      return null;
    }
  }

  ResolvedStream? _direct(StreamServer server) {
    final url = server.url.trim();
    if (!url.startsWith('http')) return null;
    return ResolvedStream(
      url: url,
      server: server,
      headers: <String, String>{
        'User-Agent': kBrowserUserAgent,
        ...server.headers,
      },
    );
  }

  Future<ResolvedStream?> _pixelDrain(StreamServer server) async {
    final uri = Uri.tryParse(server.url);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;

    switch (segments.first) {
      case 'u':
        return ResolvedStream(
          url: 'https://pixeldrain.com/api/file/${segments[1]}',
          server: server,
        );
      case 'api':
        if (segments.length >= 3 && segments[1] == 'file') {
          return ResolvedStream(url: server.url, server: server);
        }
        return null;
      case 'l':
        final response = await _dio.get<Map<String, dynamic>>(
          'https://pixeldrain.com/api/list/${segments[1]}',
        );
        final files = response.data?['files'];
        if (files is! List || files.isEmpty) return null;
        final entries = files.whereType<Map>().toList()
          ..sort(
            (a, b) =>
                ((b['size'] as num?) ?? 0).compareTo((a['size'] as num?) ?? 0),
          );
        final id = entries.first['id'];
        if (id is! String || id.isEmpty) return null;
        return ResolvedStream(
          url: 'https://pixeldrain.com/api/file/$id',
          server: server,
        );
      default:
        return null;
    }
  }

  Future<ResolvedStream?> _mediaFire(StreamServer server) async {
    final response = await _dio.get<String>(
      server.url,
      options: Options(
        responseType: ResponseType.plain,
        headers: const <String, String>{'User-Agent': kBrowserUserAgent},
      ),
    );
    final html = response.data ?? '';
    if (html.isEmpty) return null;

    final primary = RegExp(r'id="downloadButton"[^>]*href="([^"]+)"')
        .firstMatch(html);
    final fallback = RegExp(r'href="(https://download[^"]+)"').firstMatch(html);
    final href = primary?.group(1) ?? fallback?.group(1);
    if (href == null || href.isEmpty) return null;

    final url = href.replaceAll('&amp;', '&').replaceAll(r'\/', '/');
    if (!url.startsWith('http')) return null;
    return ResolvedStream(
      url: url,
      server: server,
      headers: const <String, String>{
        'User-Agent': kBrowserUserAgent,
        'Referer': 'https://www.mediafire.com/',
      },
    );
  }
}
