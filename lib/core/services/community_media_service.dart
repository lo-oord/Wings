import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Talks to the existing `wings-media-api` Worker.
///
/// The Worker is the only holder of the Tigris credentials: Flutter never sees
/// an access key. For every upload the app asks the Worker for a short-lived
/// signed URL, sends the bytes **straight to Tigris**, and then stores only the
/// object key in Firestore. Downloads are the same idea in reverse, which is
/// why the private bucket never needs a public URL.
///
/// The base URL is supplied at build time:
/// `--dart-define=WINGS_MEDIA_API=https://wings-media-api.<account>.workers.dev`.
/// When it is missing, image upload shows a clear, non-technical message
/// instead of silently failing.
class CommunityMediaService {
  CommunityMediaService(this._dio, {String? baseUrl, FirebaseAuth? auth})
    : _baseUrl = (baseUrl ?? const String.fromEnvironment('WINGS_MEDIA_API'))
          .trim()
          .replaceAll(RegExp(r'/+$'), ''),
      _auth = auth ?? FirebaseAuth.instance;

  final Dio _dio;
  final String _baseUrl;
  final FirebaseAuth _auth;

  /// Signed download URLs are reused while they are comfortably valid, so a
  /// scrolling feed asks the Worker once per image rather than once per build.
  final Map<String, _CachedUrl> _cache = <String, _CachedUrl>{};

  static const int maxImageBytes = 5 * 1024 * 1024;

  /// Short vertical clips stay small enough to upload on mobile data and to
  /// start playing quickly, and the Worker enforces the same ceiling.
  static const int maxVideoBytes = 50 * 1024 * 1024;
  static const int maxVideoSeconds = 60;

  static const int maxUploadsPerRequest = 4;

  static const Set<String> allowedTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'video/mp4',
    'video/quicktime',
    'video/webm',
  };

  static bool isVideoType(String contentType) =>
      contentType.startsWith('video/');

  static int limitFor(String contentType) =>
      isVideoType(contentType) ? maxVideoBytes : maxImageBytes;

  bool get available => _baseUrl.isNotEmpty;

  Future<String> _token() async {
    final user = _auth.currentUser;
    if (user == null) throw const MediaUnavailableException();
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const MediaUnavailableException();
    }
    return token;
  }

  Future<Map<String, String>> _headers() async => <String, String>{
    'Authorization': 'Bearer ${await _token()}',
  };

  /// Asks for signed PUT URLs for the pictures of one post.
  Future<List<MediaUpload>> createUploads({
    required String postId,
    required List<MediaFile> files,
  }) async {
    if (!available) throw const MediaUnavailableException();
    if (files.isEmpty) return const <MediaUpload>[];
    if (files.length > maxUploadsPerRequest) {
      throw const MediaRejectedException('too-many-files');
    }
    for (final file in files) {
      if (!allowedTypes.contains(file.contentType)) {
        throw const MediaRejectedException('unsupported-type');
      }
      if (file.size <= 0 || file.size > limitFor(file.contentType)) {
        throw const MediaRejectedException('file-too-large');
      }
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/v1/uploads',
      data: <String, dynamic>{
        'postId': postId,
        'files': <Map<String, dynamic>>[
          for (final file in files)
            <String, dynamic>{
              'contentType': file.contentType,
              'size': file.size,
            },
        ],
      },
      options: Options(headers: await _headers()),
    );
    final objects = response.data?['objects'];
    if (objects is! List) throw const MediaRejectedException('bad-response');
    final uploads = <MediaUpload>[];
    for (final raw in objects) {
      if (raw is! Map) continue;
      final key = raw['key'] as String? ?? '';
      final url = raw['uploadUrl'] as String? ?? '';
      final headers = raw['headers'];
      if (key.isEmpty || url.isEmpty) continue;
      uploads.add(
        MediaUpload(
          key: key,
          uploadUrl: url,
          headers: headers is Map
              ? headers.map((key, value) => MapEntry('$key', '$value'))
              : const <String, String>{},
        ),
      );
    }
    if (uploads.length != files.length) {
      throw const MediaRejectedException('bad-response');
    }
    return uploads;
  }

  /// Uploads the bytes with the signed URL. Nothing passes through the Worker.
  ///
  /// [onProgress] is used by the composer's progress bar; a retry starts a
  /// fresh PUT to the same key, which is idempotent.
  Future<void> upload(
    MediaUpload upload,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await _dio.put<void>(
      upload.uploadUrl,
      data: Stream<List<int>>.value(bytes),
      onSendProgress: onProgress,
      options: Options(
        headers: <String, String>{
          ...upload.headers,
          'Content-Length': '${bytes.length}',
        },
        contentType: upload.headers['Content-Type'],
        followRedirects: false,
        validateStatus: (status) => status != null && status < 300,
      ),
    );
  }

  /// Short-lived signed GET URLs for a batch of keys.
  Future<Map<String, String>> downloadUrls(List<String> keys) async {
    if (!available || keys.isEmpty) return const <String, String>{};
    final now = DateTime.now();
    final result = <String, String>{};
    final missing = <String>[];
    for (final key in keys) {
      final cached = _cache[key];
      if (cached != null && cached.expiresAt.isAfter(now)) {
        result[key] = cached.url;
      } else {
        missing.add(key);
      }
    }
    if (missing.isEmpty) return result;
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/v1/download',
      data: <String, dynamic>{'keys': missing},
      options: Options(headers: await _headers()),
    );
    final urls = response.data?['urls'];
    if (urls is! Map) return result;
    final lifetime = (response.data?['expiresIn'] as num?)?.toInt() ?? 600;
    // Refresh a minute before the signature actually expires.
    final expiresAt = now.add(
      Duration(seconds: (lifetime - 60).clamp(30, 3600)),
    );
    urls.forEach((key, value) {
      if (value is! String || value.isEmpty) return;
      _cache['$key'] = _CachedUrl(value, expiresAt);
      result['$key'] = value;
    });
    return result;
  }

  /// Removes objects whose post was never saved, so a failed publish does not
  /// leave paid-for storage behind. The Worker only accepts keys under the
  /// caller's own `users/{uid}/` prefix.
  Future<void> deleteObjects(List<String> keys) async {
    if (!available || keys.isEmpty) return;
    await _dio.post<void>(
      '$_baseUrl/v1/delete',
      data: <String, dynamic>{'keys': keys},
      options: Options(headers: await _headers()),
    );
    for (final key in keys) {
      _cache.remove(key);
    }
  }

  void forget(String key) => _cache.remove(key);
}

class _CachedUrl {
  const _CachedUrl(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;
}

/// A picture chosen by the member, already compressed to a safe size.
class MediaFile {
  const MediaFile({
    required this.bytes,
    required this.contentType,
    required this.extension,
    this.declaredSize,
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;

  /// Set for a video so the signed URL can be requested without reading the
  /// whole file into memory first.
  final int? declaredSize;

  int get size => declaredSize ?? bytes.length;
}

class MediaUpload {
  const MediaUpload({
    required this.key,
    required this.uploadUrl,
    required this.headers,
  });

  final String key;
  final String uploadUrl;
  final Map<String, String> headers;
}

/// The media API is not configured or the account is signed out.
class MediaUnavailableException implements Exception {
  const MediaUnavailableException();
}

/// The Worker (or the bucket) refused the request.
class MediaRejectedException implements Exception {
  const MediaRejectedException(this.reason);

  final String reason;
}
