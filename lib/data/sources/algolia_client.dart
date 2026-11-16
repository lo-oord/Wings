import 'dart:convert';

import 'package:dio/dio.dart';

import 'firestore_client.dart';
import 'wings_config.dart';

class SearchHitPage {
  const SearchHitPage({
    required this.hits,
    required this.page,
    required this.pageCount,
    required this.total,
    this.facets = const <String, Map<String, int>>{},
  });

  final List<Map<String, dynamic>> hits;
  final int page;
  final int pageCount;
  final int total;
  final Map<String, Map<String, int>> facets;

  bool get hasMore => page + 1 < pageCount;
}

/// Read-only client for the catalogue's public search indexes.
///
/// Credentials are public read keys and are refreshed from the service's own
/// configuration document when the service rotates them.
class SearchIndexClient {
  SearchIndexClient(this._dio, this._firestore);

  final Dio _dio;
  final FirestoreClient _firestore;

  String _appId = WingsConfig.bootstrapSearchAppId;
  String _apiKey = WingsConfig.bootstrapSearchKey;
  DateTime? _credentialsUpdatedAt;

  Future<void> _ensureCredentials({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _credentialsUpdatedAt != null &&
        now.difference(_credentialsUpdatedAt!) < const Duration(minutes: 45)) {
      return;
    }
    try {
      final fields = await _firestore.getFields('Settings/constants');
      if (fields == null) return;
      final primary = (fields['search_settings'] as Map?)
          ?.cast<String, dynamic>();
      final secondary = (fields['search_settings2'] as Map?)
          ?.cast<String, dynamic>();
      final appId = primary?['app_id'] ?? secondary?['app_id'];
      final apiKey = primary?['api_key'] ?? secondary?['api_key'];
      if (appId is String &&
          appId.isNotEmpty &&
          apiKey is String &&
          apiKey.isNotEmpty) {
        _appId = appId;
        _apiKey = apiKey;
      }
      _credentialsUpdatedAt = now;
    } on DioException {
      // Keep the bootstrap credentials and let the query surface the failure.
    }
  }

  Future<SearchHitPage> query(
    String index, {
    String text = '',
    int page = 0,
    int hitsPerPage = 24,
    String? facetFilter,
    String? filters,
    List<String>? facets,
    List<String>? attributesToRetrieve,
    CancelToken? cancelToken,
  }) async {
    await _ensureCredentials();
    try {
      return await _send(
        index,
        text: text,
        page: page,
        hitsPerPage: hitsPerPage,
        facetFilter: facetFilter,
        filters: filters,
        facets: facets,
        attributesToRetrieve: attributesToRetrieve,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        await _ensureCredentials(force: true);
        return _send(
          index,
          text: text,
          page: page,
          hitsPerPage: hitsPerPage,
          facetFilter: facetFilter,
          filters: filters,
          facets: facets,
          attributesToRetrieve: attributesToRetrieve,
          cancelToken: cancelToken,
        );
      }
      rethrow;
    }
  }

  Future<SearchHitPage> _send(
    String index, {
    required String text,
    required int page,
    required int hitsPerPage,
    String? facetFilter,
    String? filters,
    List<String>? facets,
    List<String>? attributesToRetrieve,
    CancelToken? cancelToken,
  }) async {
    final params = <String, String>{
      'query': text,
      'page': '$page',
      'hitsPerPage': '$hitsPerPage',
      if (facetFilter != null)
        'facetFilters': jsonEncode(<String>[facetFilter]),
      'filters': ?filters,
      if (facets != null) 'facets': jsonEncode(facets),
      if (attributesToRetrieve != null)
        'attributesToRetrieve': jsonEncode(attributesToRetrieve),
    };

    final response = await _dio.post<Map<String, dynamic>>(
      WingsConfig.searchUrl(_appId, index),
      data: <String, String>{'params': Uri(queryParameters: params).query},
      cancelToken: cancelToken,
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{
          'X-Algolia-Application-Id': _appId,
          'X-Algolia-API-Key': _apiKey,
        },
      ),
    );

    if (response.statusCode == 403) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'search credentials rejected',
      );
    }

    final data = response.data;
    if (data == null) {
      throw const FormatException('empty catalogue response');
    }
    if (data['hits'] is! List && data['message'] != null) {
      throw FormatException('catalogue error: ${data['message']}');
    }

    final hits = (data['hits'] as List? ?? const [])
        .whereType<Map>()
        .map((hit) => hit.cast<String, dynamic>())
        .toList(growable: false);

    final rawFacets = data['facets'];
    final facetMap = <String, Map<String, int>>{};
    if (rawFacets is Map) {
      for (final entry in rawFacets.entries) {
        final values = entry.value;
        if (values is Map) {
          facetMap[entry.key.toString()] = values.map(
            (key, value) =>
                MapEntry(key.toString(), value is num ? value.toInt() : 0),
          );
        }
      }
    }

    final currentPage = data['page'] is num
        ? (data['page'] as num).toInt()
        : page;
    final pageCount = data['nbPages'] is num
        ? (data['nbPages'] as num).toInt()
        : 1;
    final total = data['nbHits'] is num
        ? (data['nbHits'] as num).toInt()
        : hits.length;

    return SearchHitPage(
      hits: hits,
      page: currentPage,
      pageCount: pageCount,
      total: total,
      facets: facetMap,
    );
  }
}
