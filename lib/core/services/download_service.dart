import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/library.dart';
import '../constants/network_constants.dart';
import '../storage/local_store.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Real file downloads with a concurrency-limited queue and resumable transfers.
class DownloadService {
  DownloadService(this._dio, this._store, this._notifications, this._storage);

  final Dio _dio;
  final LocalStore _store;
  final NotificationService _notifications;
  final StorageService _storage;

  static const int maxConcurrent = 2;

  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final Map<String, DateTime> _lastEmit = <String, DateTime>{};
  final Map<String, DateTime> _lastNotify = <String, DateTime>{};
  final StreamController<List<DownloadTask>> _controller =
      StreamController<List<DownloadTask>>.broadcast();

  bool _pumping = false;
  bool notificationsEnabled = true;

  Stream<List<DownloadTask>> get stream => _controller.stream;

  List<DownloadTask> get tasks {
    final list = _tasks.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> initialize() async {
    for (final task
        in _store
            .valuesAsJson(LocalStore.downloadsBox)
            .map(DownloadTask.fromJson)) {
      // Interrupted transfers return as paused so they can be resumed safely.
      _tasks[task.id] =
          task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued
          ? task.copyWith(status: DownloadStatus.paused)
          : task;
    }
    for (final task in _tasks.values) {
      await _persist(task);
    }
    _emit();
  }

  Future<void> enqueue(DownloadTask task) async {
    _tasks[task.id] = task;
    await _persist(task);
    _emit();
    unawaited(_pump());
  }

  Future<void> pause(String id) async {
    final task = _tasks[id];
    if (task == null || task.status != DownloadStatus.downloading) return;
    _tokens[id]?.cancel('paused');
    _tokens.remove(id);
    _tasks[id] = task.copyWith(status: DownloadStatus.paused);
    await _persist(_tasks[id]!);
    _emit();
  }

  Future<void> resume(String id) async {
    final task = _tasks[id];
    if (task == null) return;
    _tasks[id] = task.copyWith(status: DownloadStatus.queued, clearError: true);
    await _persist(_tasks[id]!);
    _emit();
    unawaited(_pump());
  }

  Future<void> retry(String id) async {
    final task = _tasks[id];
    if (task == null) return;
    _tasks[id] = task.copyWith(
      status: DownloadStatus.queued,
      receivedBytes: 0,
      error: null,
      clearError: true,
    );
    await _persist(_tasks[id]!);
    _emit();
    unawaited(_pump());
  }

  Future<void> cancel(String id) async {
    _tokens[id]?.cancel('cancelled');
    _tokens.remove(id);
    final task = _tasks.remove(id);
    if (task != null) {
      await _deleteFile(task.filePath);
      await _store.delete(LocalStore.downloadsBox, id);
    }
    _emit();
  }

  Future<void> deleteFile(String id) async {
    final task = _tasks[id];
    if (task == null) return;
    await _deleteFile(task.filePath);
    _tasks.remove(id);
    await _store.delete(LocalStore.downloadsBox, id);
    _emit();
  }

  int get storageUsedBytes => _tasks.values
      .where((t) => t.status == DownloadStatus.completed)
      .fold(0, (sum, t) => sum + t.totalBytes);

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final active = _tasks.values
            .where((t) => t.status == DownloadStatus.downloading)
            .length;
        if (active >= maxConcurrent) break;
        final queued =
            _tasks.values
                .where((t) => t.status == DownloadStatus.queued)
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (queued.isEmpty) break;
        final next = queued.first;
        _tasks[next.id] = next.copyWith(
          status: DownloadStatus.downloading,
          clearError: true,
        );
        await _persist(_tasks[next.id]!);
        _emit();
        unawaited(_run(_tasks[next.id]!));
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(DownloadTask task) async {
    final token = CancelToken();
    _tokens[task.id] = token;
    try {
      final directory = await _downloadDirectory();
      final file = File('${directory.path}/${_fileName(task)}');
      final transfer = _isHls(task.url)
          ? await _downloadHls(task, file, token)
          : await _downloadHttp(task, file, token);

      if (token.isCancelled ||
          _tasks[task.id]?.status == DownloadStatus.paused) {
        await _persist(_tasks[task.id]!);
        return;
      }

      final fileName = _fileName(task);
      String? publicUri;
      try {
        publicUri = await _storage.saveToDownloads(
          path: file.path,
          fileName: fileName,
        );
      } on Object {
        publicUri = null;
      }
      final done = _tasks[task.id]!.copyWith(
        status: DownloadStatus.completed,
        filePath: file.path,
        fileName: fileName,
        publicUri: publicUri,
        receivedBytes: transfer.receivedBytes,
        totalBytes: transfer.totalBytes > 0
            ? transfer.totalBytes
            : transfer.receivedBytes,
      );
      _tasks[task.id] = done;
      await _persist(done);
      _emit();
      await _notifications.showDownloadCompleted(
        id: done.trayId,
        title: done.animeTitle,
        body: 'الحلقة ${done.episodeNumber} جاهزة للمشاهدة',
        enabled: notificationsEnabled,
      );
    } on Object catch (error) {
      final current = _tasks[task.id];
      if (current == null) return;
      if (current.status == DownloadStatus.paused ||
          (error is DioException && error.type == DioExceptionType.cancel)) {
        return;
      }
      final failed = current.copyWith(
        status: DownloadStatus.failed,
        error: error is DioException ? error.type.name : 'error',
      );
      _tasks[task.id] = failed;
      await _persist(failed);
      _emit();
      await _notifications.cancel(failed.trayId);
      await _notifications.showDownloadFailed(
        id: failed.trayId,
        title: failed.animeTitle,
        body: 'تعذّر تنزيل الحلقة ${failed.episodeNumber}',
        enabled: notificationsEnabled,
      );
    } finally {
      _tokens.remove(task.id);
      unawaited(_pump());
    }
  }

  bool _isHls(String url) => url.toLowerCase().contains('.m3u8');

  Map<String, String> _headers(DownloadTask task) => <String, String>{
    'User-Agent': kBrowserUserAgent,
    ...task.headers,
  };

  Future<_TransferStats> _downloadHttp(
    DownloadTask task,
    File file,
    CancelToken token,
  ) async {
    final existing = await file.exists() ? await file.length() : 0;
    final response = await _dio.get<ResponseBody>(
      task.url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: <String, String>{
          ..._headers(task),
          if (existing > 0) 'Range': 'bytes=$existing-',
        },
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );
    final body = response.data;
    if (body == null) throw const FormatException('empty body');
    final partial = response.statusCode == 206;
    final headerLength =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;
    final total = partial ? existing + headerLength : headerLength;
    final startingBytes = partial ? existing : 0;
    _tasks[task.id] = _tasks[task.id]!.copyWith(
      totalBytes: total > 0 ? total : _tasks[task.id]!.totalBytes,
      receivedBytes: startingBytes,
    );
    _emit();
    final sink = file.openWrite(
      mode: partial ? FileMode.append : FileMode.write,
    );
    var received = 0;
    try {
      await for (final chunk in body.stream) {
        if (token.isCancelled) break;
        sink.add(chunk);
        received += chunk.length;
        _updateProgress(task.id, startingBytes + received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return _TransferStats(
      receivedBytes: startingBytes + received,
      totalBytes: total,
    );
  }

  Future<_TransferStats> _downloadHls(
    DownloadTask task,
    File file,
    CancelToken token,
  ) async {
    final response = await _dio.get<String>(
      task.url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.plain,
        headers: _headers(task),
        validateStatus: (status) => status == 200,
      ),
    );
    final playlist = response.data;
    if (playlist == null || playlist.isEmpty) {
      throw const FormatException('empty HLS playlist');
    }
    final base = Uri.parse(task.url);
    final segments = playlist
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((line) => base.resolve(line))
        .toList(growable: false);
    if (segments.isEmpty) {
      throw const FormatException('HLS playlist has no segments');
    }
    if (await file.exists()) await file.delete();
    final sink = file.openWrite();
    var received = 0;
    try {
      for (var index = 0; index < segments.length; index++) {
        if (token.isCancelled) break;
        final segment = await _dio.get<List<int>>(
          segments[index].toString(),
          cancelToken: token,
          options: Options(
            responseType: ResponseType.bytes,
            headers: _headers(task),
            validateStatus: (status) => status == 200,
          ),
        );
        final bytes = segment.data;
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException('empty HLS segment');
        }
        sink.add(bytes);
        received += bytes.length;
        _updateProgress(task.id, index + 1, segments.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return _TransferStats(receivedBytes: received, totalBytes: received);
  }

  void _updateProgress(String id, int received, int total) {
    final task = _tasks[id];
    if (task == null) return;
    _tasks[id] = task.copyWith(
      receivedBytes: received,
      totalBytes: total > 0 ? total : task.totalBytes,
    );
    final now = DateTime.now();
    if (notificationsEnabled) {
      final lastNotice = _lastNotify[id];
      if (lastNotice == null ||
          now.difference(lastNotice) > const Duration(seconds: 1)) {
        _lastNotify[id] = now;
        unawaited(
          _notifications.showDownloadProgress(
            id: task.trayId,
            title: '${task.animeTitle} · ${task.episodeNumber}',
            progress: received,
            max: total > 0 ? total : 0,
          ),
        );
      }
    }
    final last = _lastEmit[id];
    if (last == null ||
        now.difference(last) > const Duration(milliseconds: 350)) {
      _lastEmit[id] = now;
      _emit();
    }
  }

  Future<Directory> _downloadDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/wings_downloads');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Human-readable name that appears in the user's Downloads folder.
  String _fileName(DownloadTask task) {
    final title = task.animeTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final base = title.isEmpty ? 'Wings' : title;
    final extension = _isHls(task.url) ? 'ts' : 'mp4';
    return '$base - الحلقة ${task.episodeNumber} - Wings.$extension';
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      debugPrint('download cleanup failed: $error');
    }
  }

  Future<void> _persist(DownloadTask task) =>
      _store.putJson(LocalStore.downloadsBox, task.id, task.toJson());

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(tasks);
  }

  void dispose() {
    for (final token in _tokens.values) {
      token.cancel('disposed');
    }
    _controller.close();
  }
}

class _TransferStats {
  const _TransferStats({required this.receivedBytes, required this.totalBytes});

  final int receivedBytes;
  final int totalBytes;
}
