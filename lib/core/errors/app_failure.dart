import 'package:dio/dio.dart';

import '../../app/localization/app_localizations.dart';

enum FailureKind {
  network,
  timeout,
  server,
  notFound,
  parsing,
  storage,
  playback,
  permission,
  cancelled,
  unknown,
}

/// A user-safe error. Technical details are kept for logging only.
class AppFailure implements Exception {
  const AppFailure(this.kind, {this.technical, this.statusCode});

  final FailureKind kind;
  final String? technical;
  final int? statusCode;

  factory AppFailure.from(Object error, [StackTrace? stack]) {
    if (error is AppFailure) return error;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return AppFailure(FailureKind.timeout, technical: error.message);
        case DioExceptionType.connectionError:
          return AppFailure(FailureKind.network, technical: error.message);
        case DioExceptionType.cancel:
          return const AppFailure(FailureKind.cancelled);
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == 404) {
            return AppFailure(FailureKind.notFound, statusCode: code);
          }
          if (code != null && code >= 500) {
            return AppFailure(FailureKind.server, statusCode: code);
          }
          return AppFailure(
            FailureKind.server,
            statusCode: code,
            technical: error.message,
          );
        case DioExceptionType.badCertificate:
        case DioExceptionType.unknown:
          return AppFailure(FailureKind.network, technical: error.message);
      }
    }
    if (error is FormatException) {
      return AppFailure(FailureKind.parsing, technical: error.message);
    }
    return AppFailure(FailureKind.unknown, technical: error.toString());
  }

  String message(AppLocalizations l10n) => switch (kind) {
    FailureKind.network => l10n.stateErrorNetwork,
    FailureKind.timeout => l10n.stateErrorTimeout,
    FailureKind.server => l10n.stateErrorServer,
    FailureKind.notFound => l10n.stateErrorNotFound,
    FailureKind.parsing => l10n.stateErrorGeneric,
    FailureKind.storage => l10n.stateErrorGeneric,
    FailureKind.playback => l10n.playerPlaybackErrorBody,
    FailureKind.permission => l10n.settingsPermissionDenied,
    FailureKind.cancelled => l10n.stateErrorGeneric,
    FailureKind.unknown => l10n.stateErrorGeneric,
  };

  @override
  String toString() =>
      'AppFailure($kind, status: $statusCode, technical: $technical)';
}
