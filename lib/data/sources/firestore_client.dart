import 'package:dio/dio.dart';

import 'wings_config.dart';

/// Minimal read-only client for the catalogue's public Firestore documents.
class FirestoreClient {
  FirestoreClient(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>?> getDocument(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      WingsConfig.firestoreDocumentUrl(path),
      queryParameters: <String, String>{'key': WingsConfig.firestoreClientKey},
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) return null;
    final data = response.data;
    if (data == null || data['fields'] is! Map) return null;
    return (data['fields'] as Map).cast<String, dynamic>();
  }

  /// Returns the document `fields` decoded into plain Dart values.
  Future<Map<String, dynamic>?> getFields(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final fields = await getDocument(path, cancelToken: cancelToken);
    if (fields == null) return null;
    return decodeFields(fields);
  }

  /// Reads a sub-collection and returns each document's decoded fields.
  /// Like [getDocuments] but keeps each document's id.
  Future<List<(String, Map<String, dynamic>)>> getDocumentsWithIds(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final url =
        'https://firestore.googleapis.com/v1/projects/${WingsConfig.firestoreProject}'
        '/databases/(default)/documents/$encoded';
    final response = await _dio.get<Map<String, dynamic>>(
      url,
      queryParameters: <String, String>{
        'key': WingsConfig.firestoreClientKey,
        'pageSize': '2000',
      },
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) return const [];
    final documents = response.data?['documents'];
    if (documents is! List) return const [];
    final result = <(String, Map<String, dynamic>)>[];
    for (final doc in documents.whereType<Map>()) {
      final fields = doc['fields'];
      final name = doc['name']?.toString() ?? '';
      final id = name.split('/').last;
      if (id.isEmpty) continue;
      result.add((
        id,
        fields is Map
            ? decodeFields(fields.cast<String, dynamic>())
            : <String, dynamic>{},
      ));
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getDocuments(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final url =
        'https://firestore.googleapis.com/v1/projects/${WingsConfig.firestoreProject}'
        '/databases/(default)/documents/$encoded';
    final response = await _dio.get<Map<String, dynamic>>(
      url,
      queryParameters: <String, String>{'key': WingsConfig.firestoreClientKey},
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) return const [];
    final documents = response.data?['documents'];
    if (documents is! List) return const [];
    return documents
        .whereType<Map>()
        .map((doc) {
          final fields = doc['fields'];
          return fields is Map
              ? decodeFields(fields.cast<String, dynamic>())
              : <String, dynamic>{};
        })
        .toList(growable: false);
  }

  static Map<String, dynamic> decodeFields(Map<String, dynamic> fields) {
    return fields.map((key, value) => MapEntry(key, decodeValue(value)));
  }

  /// Converts a Firestore `Value` object into a plain Dart value.
  static dynamic decodeValue(dynamic value) {
    if (value is! Map) return value;
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue']?.toString() ?? '');
    }
    if (value.containsKey('doubleValue')) {
      final raw = value['doubleValue'];
      return raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
    }
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('timestampValue')) {
      return DateTime.tryParse(value['timestampValue']?.toString() ?? '');
    }
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('referenceValue')) return value['referenceValue'];
    if (value.containsKey('mapValue')) {
      final fields = value['mapValue']?['fields'];
      return fields is Map
          ? decodeFields(fields.cast<String, dynamic>())
          : <String, dynamic>{};
    }
    if (value.containsKey('arrayValue')) {
      final values = value['arrayValue']?['values'];
      if (values is! List) return const <dynamic>[];
      return values.map(decodeValue).toList(growable: false);
    }
    return null;
  }
}
