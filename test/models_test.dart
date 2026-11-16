import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/models/library.dart';

void main() {
  group('Anime', () {
    test('round-trips through JSON without losing fields', () {
      const anime = Anime(
        id: 'One Piece',
        title: 'One Piece',
        englishTitle: 'One Piece',
        posterUrl: 'https://example.com/poster.jpg',
        synopsis: 'قصة',
        genres: <String>['اكشن', 'مغامرات'],
        type: 'مسلسل',
        year: 1999,
        status: 'مستمر',
        rating: 8.7,
        episodeCount: 1100,
        studios: <String>['Toei Animation'],
        contentPath: 'anime_list/One Piece',
        relatedIds: <String>['Naruto'],
      );

      final restored = Anime.fromJson(anime.toJson());

      expect(restored.id, anime.id);
      expect(restored.title, anime.title);
      expect(restored.genres, anime.genres);
      expect(restored.rating, anime.rating);
      expect(restored.contentPath, anime.contentPath);
      expect(restored.relatedIds, anime.relatedIds);
      expect(restored.imageUrl, anime.posterUrl);
    });

    test('tolerates missing optional fields', () {
      final anime = Anime.fromJson(<String, dynamic>{'id': 'x', 'title': 'X'});
      expect(anime.genres, isEmpty);
      expect(anime.rating, isNull);
      expect(anime.year, isNull);
      expect(anime.englishTitle, isNull);
    });

    test('routeId encodes unsafe characters', () {
      const anime = Anime(id: 'Re:Zero / Season 2', title: 'Re:Zero');
      expect(anime.routeId.contains('/'), isFalse);
      expect(Uri.decodeComponent(anime.routeId), 'Re:Zero / Season 2');
    });
  });

  group('WatchHistoryEntry', () {
    test('progress is clamped and computed from durations', () {
      final entry = WatchHistoryEntry(
        animeId: 'a',
        animeTitle: 'A',
        episodeId: '1',
        episodeNumber: 1,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 20),
        updatedAt: DateTime(2026),
      );
      expect(entry.progress, closeTo(0.25, 0.001));
      expect(entry.key, 'a::1');
    });

    test('guards against zero duration', () {
      final entry = WatchHistoryEntry(
        animeId: 'a',
        animeTitle: 'A',
        episodeId: '1',
        episodeNumber: 1,
        updatedAt: DateTime(2026),
      );
      expect(entry.progress, 0);
    });

    test('serialises playback state', () {
      final entry = WatchHistoryEntry(
        animeId: 'a',
        animeTitle: 'A',
        episodeId: '3',
        episodeNumber: 3,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 24),
        completed: true,
        updatedAt: DateTime(2026, 5, 1),
      );
      final restored = WatchHistoryEntry.fromJson(entry.toJson());
      expect(restored.position, entry.position);
      expect(restored.duration, entry.duration);
      expect(restored.completed, isTrue);
      expect(restored.episodeNumber, 3);
    });
  });

  group('DownloadTask', () {
    test('progress never exceeds one', () {
      final task = DownloadTask(
        id: 't',
        animeId: 'a',
        animeTitle: 'A',
        episodeId: '1',
        episodeNumber: 1,
        quality: '1080p',
        url: 'https://example.com/video.mp4',
        status: DownloadStatus.downloading,
        createdAt: DateTime(2026),
        receivedBytes: 200,
        totalBytes: 100,
      );
      expect(task.progress, 1.0);
    });

    test('copyWith keeps identity and clears errors', () {
      final task = DownloadTask(
        id: 't',
        animeId: 'a',
        animeTitle: 'A',
        episodeId: '1',
        episodeNumber: 1,
        quality: '720p',
        url: 'https://example.com/video.mp4',
        status: DownloadStatus.failed,
        createdAt: DateTime(2026),
        error: 'boom',
      );
      final refreshed = task.copyWith(
        status: DownloadStatus.queued,
        clearError: true,
      );
      expect(refreshed.id, task.id);
      expect(refreshed.error, isNull);
      expect(refreshed.status, DownloadStatus.queued);
    });
  });

  group('AppSettings', () {
    test('defaults to Arabic and persists changes', () {
      const settings = AppSettings();
      expect(settings.localeCode, 'ar');
      final updated = settings.copyWith(
        themeMode: ThemeMode.light,
        autoplayNext: false,
      );
      final restored = AppSettings.fromJson(updated.toJson());
      expect(restored.themeMode, ThemeMode.light);
      expect(restored.autoplayNext, isFalse);
    });
  });

  group('Paged', () {
    test('append merges pages and keeps totals', () {
      const first = Paged<int>(
        items: <int>[1, 2],
        page: 0,
        hasMore: true,
        total: 4,
      );
      const second = Paged<int>(items: <int>[3, 4], page: 1, hasMore: false);
      final merged = first.append(second);
      expect(merged.items, <int>[1, 2, 3, 4]);
      expect(merged.page, 1);
      expect(merged.hasMore, isFalse);
      expect(merged.total, 4);
    });
  });
}
