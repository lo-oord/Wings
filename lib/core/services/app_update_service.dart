import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/app_update.dart';
import '../constants/app_links.dart';

/// Reads the published update manifest and fetches the new APK.
///
/// The manifest is a small static JSON file on the Wings website, so checking
/// for an update costs one request and never blocks start-up: the caller awaits
/// it after the first frame.
class AppUpdateService {
  AppUpdateService(this._dio);

  final Dio _dio;

  /// Returns the published release, or `null` when nothing was published yet.
  Future<AppUpdate?> fetchLatest() async {
    final response = await _dio.get<dynamic>(
      AppLinks.updatesManifest,
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 12),
        headers: const <String, String>{'Cache-Control': 'no-cache'},
      ),
    );
    return AppUpdate.fromJson(response.data);
  }

  /// Downloads the APK into the app's temporary folder.
  ///
  /// [onProgress] receives a 0..1 value; an unknown length reports 0 so the
  /// dialog can show an indeterminate bar instead of a stuck percentage.
  Future<File> download(
    AppUpdate update, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final directory = await getTemporaryDirectory();
    final folder = Directory('${directory.path}/updates');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File('${folder.path}/wings-${update.version}.apk');
    if (file.existsSync()) file.deleteSync();

    await _dio.download(
      update.apkUrl,
      file.path,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total <= 0) {
          onProgress(0);
          return;
        }
        onProgress((received / total).clamp(0, 1));
      },
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 5),
        headers: const <String, String>{'Accept': 'application/octet-stream'},
      ),
    );
    if (!file.existsSync() || file.lengthSync() < 1024) {
      throw const FileSystemException('The downloaded package is empty.');
    }
    return file;
  }

  Future<OpenResult> install(File file) => OpenFilex.open(
    file.path,
    type: 'application/vnd.android.package-archive',
  );
}
