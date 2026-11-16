import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/network_constants.dart';

/// Creates the shared HTTP client with timeouts and a small retry policy.
Dio createHttpClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: const <String, String>{
        'User-Agent': kBrowserUserAgent,
        'Accept-Language': 'ar,en;q=0.8',
      },
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  dio.interceptors.add(_RetryInterceptor(dio));
  if (kDebugMode) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          debugPrint(
            '[http] ${response.requestOptions.method} '
            '${response.requestOptions.uri.path} -> ${response.statusCode}',
          );
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint(
            '[http] ${error.requestOptions.uri.path} failed: ${error.type}',
          );
          handler.next(error);
        },
      ),
    );
  }
  return dio;
}

/// Retries idempotent GET/POST requests on transient network failures.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;
  static const int maxAttempts = 2;
  final Random _random = Random();

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra['attempt'] as int?) ?? 0;
    if (attempt >= maxAttempts || !_isTransient(err)) {
      handler.next(err);
      return;
    }
    final delayMs = 350 * pow(2, attempt).toInt() + _random.nextInt(200);
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    final options = err.requestOptions..extra['attempt'] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  bool _isTransient(DioException err) {
    if (err.type == DioExceptionType.cancel) return false;
    final code = err.response?.statusCode;
    return switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      DioExceptionType.badResponse => code != null && code >= 500,
      _ => false,
    };
  }
}
