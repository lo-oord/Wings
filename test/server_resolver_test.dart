import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/sources/server_resolver.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(
  body,
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);

ResponseBody _html(String body) => ResponseBody.fromString(
  body,
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
  },
);

Dio _dioWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (status) => status == 200));
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  test('pixelDrain file pages become direct API media URLs', () async {
    final resolver = ServerResolver(
      _dioWith(
        _FakeAdapter((options) async {
          fail('no network request expected for /u/ links');
        }),
      ),
    );
    const server = StreamServer(
      name: 'PD',
      url: 'https://pixeldrain.com/u/Vw7yRewN',
      quality: '1080p',
      flavor: ServerFlavor.pixelDrain,
    );

    final resolved = await resolver.resolve(server);

    expect(resolved, isNotNull);
    expect(resolved!.url, 'https://pixeldrain.com/api/file/Vw7yRewN');
    expect(resolved.quality, '1080p');
  });

  test('pixelDrain albums resolve to their largest file', () async {
    final resolver = ServerResolver(
      _dioWith(
        _FakeAdapter(
          (options) async => _json(
            '{"success":true,"files":[{"id":"small","size":10},{"id":"large","size":900}]}',
          ),
        ),
      ),
    );
    const server = StreamServer(
      name: 'PD',
      url: 'https://pixeldrain.com/l/dARVBmDw',
      quality: '720p',
      flavor: ServerFlavor.pixelDrain,
    );

    final resolved = await resolver.resolve(server);

    expect(resolved?.url, 'https://pixeldrain.com/api/file/large');
  });

  test('mediaFire pages expose the direct download link', () async {
    final resolver = ServerResolver(
      _dioWith(
        _FakeAdapter(
          (options) async => _html(
            '<a class="input popsok" id="downloadButton" '
            'href="https://download2274.mediafire.com/abc/file.mp4">Download</a>',
          ),
        ),
      ),
    );
    const server = StreamServer(
      name: 'MF2',
      url: 'https://www.mediafire.com/file/abc/file.mp4/file',
      quality: '480p',
      flavor: ServerFlavor.mediaFire,
    );

    final resolved = await resolver.resolve(server);

    expect(resolved, isNotNull);
    expect(resolved!.url, 'https://download2274.mediafire.com/abc/file.mp4');
    expect(resolved.headers['Referer'], contains('mediafire.com'));
  });

  test('mediaFire ticket pages are followed once to the media URL', () async {
    final requested = <String>[];
    final resolver = ServerResolver(
      _dioWith(
        _FakeAdapter((options) async {
          requested.add(options.uri.toString());
          if (requested.length == 1) {
            return _html(
              '<a class="input popsok" href="//www.mediafire.com/file/abc/'
              'file.mp4/file?dkey=ticket" onclick="go(=>)" '
              'id="downloadButton" rel="nofollow">Download</a>',
            );
          }
          return _html(
            '<a href="https://download2391.mediafire.com/xyz/file.mp4">'
            'Download now</a>',
          );
        }),
      ),
    );
    const server = StreamServer(
      name: 'MF',
      url: 'https://www.mediafire.com/file/abc/file.mp4/file',
      quality: '480p',
      flavor: ServerFlavor.mediaFire,
    );

    final resolved = await resolver.resolve(server);

    expect(requested, hasLength(2));
    expect(
      requested.last,
      'https://www.mediafire.com/file/abc/file.mp4/file?dkey=ticket',
    );
    expect(resolved?.url, 'https://download2391.mediafire.com/xyz/file.mp4');
  });

  test('stream servers can carry their own request headers', () async {
    final resolver = ServerResolver(
      _dioWith(_FakeAdapter((options) async => _html(''))),
    );
    const server = StreamServer(
      name: 'كرتوني',
      url: 'https://cdn.example.com/stream.m3u8',
      quality: '720p',
      flavor: ServerFlavor.direct,
      headers: <String, String>{'Referer': 'https://cartoony.net/'},
    );

    final resolved = await resolver.resolve(server);

    expect(resolved?.url, 'https://cdn.example.com/stream.m3u8');
    expect(resolved?.headers['Referer'], 'https://cartoony.net/');
    expect(resolved?.headers['User-Agent'], isNotEmpty);
  });

  test(
    'mediaFire pages without a link resolve to null instead of a fake URL',
    () async {
      final resolver = ServerResolver(
        _dioWith(
          _FakeAdapter((options) async => _html('<html>file removed</html>')),
        ),
      );
      const server = StreamServer(
        name: 'MF',
        url: 'https://www.mediafire.com/file/missing',
        quality: '720p',
        flavor: ServerFlavor.mediaFire,
      );

      expect(await resolver.resolve(server), isNull);
    },
  );

  test('browser-only servers are never reported as playable', () async {
    final resolver = ServerResolver(
      _dioWith(_FakeAdapter((options) async => _html(''))),
    );
    const server = StreamServer(
      name: 'ST',
      url: 'https://streamtape.com/v/abc',
      quality: '1080p',
      flavor: ServerFlavor.streamTape,
      requiresBrowser: true,
    );

    expect(await resolver.resolve(server), isNull);
  });

  test('quality ranking orders numeric labels', () {
    const low = StreamServer(
      name: 'A',
      url: 'https://example.com/a.mp4',
      quality: '480p',
      flavor: ServerFlavor.direct,
    );
    const high = StreamServer(
      name: 'B',
      url: 'https://example.com/b.mp4',
      quality: '1080p',
      flavor: ServerFlavor.direct,
    );
    expect(high.qualityRank, greaterThan(low.qualityRank));
  });
}
