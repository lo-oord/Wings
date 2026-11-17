import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/library.dart';

void main() {
  group('sync cadence', () {
    test('defaults to every hour', () {
      expect(const AppSettings().syncInterval, SyncInterval.hourly);
      expect(
        AppSettings.fromJson(<String, dynamic>{}).syncInterval,
        SyncInterval.hourly,
      );
    });

    test('maps each choice to the interval it promises', () {
      expect(SyncInterval.every30Minutes.period, const Duration(minutes: 30));
      expect(SyncInterval.hourly.period, const Duration(hours: 1));
      expect(SyncInterval.daily.period, const Duration(hours: 24));
      expect(SyncInterval.weekly.period, const Duration(days: 7));
      expect(SyncInterval.monthly.period, const Duration(days: 30));
      // Instant pushes each change; manual runs only on demand.
      expect(SyncInterval.instant.period, Duration.zero);
      expect(SyncInterval.manual.period, isNull);
    });

    test('the chosen interval survives a settings round-trip', () {
      const settings = AppSettings(syncInterval: SyncInterval.monthly);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.syncInterval, SyncInterval.monthly);
      expect(restored.syncInterval.label(arabic: true), 'شهريًا');
    });
  });

  group('saved episodes', () {
    test('round-trips the display information and keeps a stable key', () {
      final episode = SavedEpisode(
        animeId: 'anime-1',
        animeTitle: 'Naruto',
        posterUrl: 'https://example.test/poster.jpg',
        episodeId: 'ep-12',
        episodeNumber: 12,
        episodeTitle: 'The battle',
        savedAt: DateTime(2026, 4, 5, 10, 30),
      );
      final restored = SavedEpisode.fromJson(episode.toJson());
      expect(restored.animeId, 'anime-1');
      expect(restored.episodeId, 'ep-12');
      expect(restored.episodeNumber, 12);
      expect(restored.savedAt, DateTime(2026, 4, 5, 10, 30));
      expect(restored.key, 'anime-1__ep-12');
    });

    test('tolerates a document with only the required fields', () {
      final restored = SavedEpisode.fromJson(<String, dynamic>{
        'animeId': 'a',
        'episodeId': 'e',
        'episodeNumber': 1,
      });
      expect(restored.animeTitle, isEmpty);
      expect(restored.episodeTitle, isNull);
    });
  });
}
