import 'package:flutter/material.dart';

import 'anime.dart';

enum LibraryStatus { watching, completed, planToWatch, onHold, dropped }

@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.anime,
    required this.status,
    required this.updatedAt,
    required this.addedAt,
    this.isFavorite = false,
    this.watchedEpisodes = 0,
  });

  final Anime anime;
  final LibraryStatus status;
  final bool isFavorite;
  final DateTime addedAt;
  final DateTime updatedAt;
  final int watchedEpisodes;

  LibraryEntry copyWith({
    LibraryStatus? status,
    bool? isFavorite,
    int? watchedEpisodes,
    DateTime? updatedAt,
  }) {
    return LibraryEntry(
      anime: anime,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'anime': anime.toJson(),
    'status': status.name,
    'isFavorite': isFavorite,
    'addedAt': addedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'watchedEpisodes': watchedEpisodes,
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
    anime: Anime.fromJson((json['anime'] as Map).cast<String, dynamic>()),
    status: LibraryStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => LibraryStatus.planToWatch,
    ),
    isFavorite: json['isFavorite'] as bool? ?? false,
    addedAt:
        DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    watchedEpisodes: (json['watchedEpisodes'] as num?)?.toInt() ?? 0,
  );
}

@immutable
class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.animeId,
    required this.animeTitle,
    required this.episodeId,
    required this.episodeNumber,
    required this.updatedAt,
    this.posterUrl,
    this.contentPath,
    this.episodeTitle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.completed = false,
  });

  final String animeId;
  final String animeTitle;
  final String? posterUrl;
  final String? contentPath;
  final String episodeId;
  final int episodeNumber;
  final String? episodeTitle;
  final Duration position;
  final Duration duration;
  final bool completed;
  final DateTime updatedAt;

  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  String get key => '$animeId::$episodeId';

  WatchHistoryEntry copyWith({
    Duration? position,
    Duration? duration,
    bool? completed,
    DateTime? updatedAt,
  }) {
    return WatchHistoryEntry(
      animeId: animeId,
      animeTitle: animeTitle,
      posterUrl: posterUrl,
      contentPath: contentPath,
      episodeId: episodeId,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'animeId': animeId,
    'animeTitle': animeTitle,
    'posterUrl': posterUrl,
    'contentPath': contentPath,
    'episodeId': episodeId,
    'episodeNumber': episodeNumber,
    'episodeTitle': episodeTitle,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'completed': completed,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      WatchHistoryEntry(
        animeId: json['animeId'] as String,
        animeTitle: json['animeTitle'] as String? ?? '',
        posterUrl: json['posterUrl'] as String?,
        contentPath: json['contentPath'] as String?,
        episodeId: json['episodeId'] as String,
        episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 0,
        episodeTitle: json['episodeTitle'] as String?,
        position: Duration(
          milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
        ),
        duration: Duration(
          milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
        ),
        completed: json['completed'] as bool? ?? false,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

enum DownloadStatus { queued, downloading, paused, completed, failed }

@immutable
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.animeId,
    required this.animeTitle,
    required this.episodeId,
    required this.episodeNumber,
    required this.quality,
    required this.url,
    required this.status,
    required this.createdAt,
    this.posterUrl,
    this.episodeTitle,
    this.headers = const <String, String>{},
    this.filePath,
    this.fileName,
    this.publicUri,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final String id;
  final String animeId;
  final String animeTitle;
  final String? posterUrl;
  final String episodeId;
  final int episodeNumber;
  final String? episodeTitle;
  final String quality;
  final String url;
  final Map<String, String> headers;
  final DownloadStatus status;
  final String? filePath;
  final String? fileName;
  final String? publicUri;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final DateTime createdAt;

  double get progress =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  /// Stable notification id for this transfer.
  int get trayId => id.hashCode.abs() % 100000;

  DownloadTask copyWith({
    DownloadStatus? status,
    String? filePath,
    String? fileName,
    String? publicUri,
    int? receivedBytes,
    int? totalBytes,
    String? error,
    bool clearError = false,
  }) {
    return DownloadTask(
      id: id,
      animeId: animeId,
      animeTitle: animeTitle,
      posterUrl: posterUrl,
      episodeId: episodeId,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      quality: quality,
      url: url,
      headers: headers,
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      publicUri: publicUri ?? this.publicUri,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'animeId': animeId,
    'animeTitle': animeTitle,
    'posterUrl': posterUrl,
    'episodeId': episodeId,
    'episodeNumber': episodeNumber,
    'episodeTitle': episodeTitle,
    'quality': quality,
    'url': url,
    'headers': headers,
    'status': status.name,
    'filePath': filePath,
    'fileName': fileName,
    'publicUri': publicUri,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    animeId: json['animeId'] as String? ?? '',
    animeTitle: json['animeTitle'] as String? ?? '',
    posterUrl: json['posterUrl'] as String?,
    episodeId: json['episodeId'] as String? ?? '',
    episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 0,
    episodeTitle: json['episodeTitle'] as String?,
    quality: json['quality'] as String? ?? '',
    url: json['url'] as String? ?? '',
    headers: json['headers'] is Map
        ? Map<String, String>.fromEntries(
            (json['headers'] as Map).entries.map(
              (entry) => MapEntry(entry.key.toString(), entry.value.toString()),
            ),
          )
        : const <String, String>{},
    status: DownloadStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => DownloadStatus.failed,
    ),
    filePath: json['filePath'] as String?,
    fileName: json['fileName'] as String?,
    publicUri: json['publicUri'] as String?,
    receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
    error: json['error'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.localeCode = 'ar',
    this.autoplayNext = true,
    this.rememberPosition = true,
    this.playbackSpeed = 1.0,
    this.preferredQuality = '1080p',
    this.notifyNewEpisodes = true,
    this.notifyDownloads = true,
    this.notifyGeneral = false,
    this.onboardingDone = false,
    this.guestMode = false,
  });

  final ThemeMode themeMode;
  final String localeCode;
  final bool autoplayNext;
  final bool rememberPosition;
  final double playbackSpeed;
  final String preferredQuality;
  final bool notifyNewEpisodes;
  final bool notifyDownloads;
  final bool notifyGeneral;
  final bool onboardingDone;
  final bool guestMode;

  Locale get locale => Locale(localeCode);

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? localeCode,
    bool? autoplayNext,
    bool? rememberPosition,
    double? playbackSpeed,
    String? preferredQuality,
    bool? notifyNewEpisodes,
    bool? notifyDownloads,
    bool? notifyGeneral,
    bool? onboardingDone,
    bool? guestMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode ?? this.localeCode,
      autoplayNext: autoplayNext ?? this.autoplayNext,
      rememberPosition: rememberPosition ?? this.rememberPosition,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      notifyNewEpisodes: notifyNewEpisodes ?? this.notifyNewEpisodes,
      notifyDownloads: notifyDownloads ?? this.notifyDownloads,
      notifyGeneral: notifyGeneral ?? this.notifyGeneral,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      guestMode: guestMode ?? this.guestMode,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'localeCode': localeCode,
    'autoplayNext': autoplayNext,
    'rememberPosition': rememberPosition,
    'playbackSpeed': playbackSpeed,
    'preferredQuality': preferredQuality,
    'notifyNewEpisodes': notifyNewEpisodes,
    'notifyDownloads': notifyDownloads,
    'notifyGeneral': notifyGeneral,
    'onboardingDone': onboardingDone,
    'guestMode': guestMode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (m) => m.name == json['themeMode'],
      orElse: () => ThemeMode.system,
    ),
    localeCode: json['localeCode'] as String? ?? 'ar',
    autoplayNext: json['autoplayNext'] as bool? ?? true,
    rememberPosition: json['rememberPosition'] as bool? ?? true,
    playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
    preferredQuality: json['preferredQuality'] as String? ?? '1080p',
    notifyNewEpisodes: json['notifyNewEpisodes'] as bool? ?? true,
    notifyDownloads: json['notifyDownloads'] as bool? ?? true,
    notifyGeneral: json['notifyGeneral'] as bool? ?? false,
    onboardingDone: json['onboardingDone'] as bool? ?? false,
    guestMode: json['guestMode'] as bool? ?? false,
  );
}
