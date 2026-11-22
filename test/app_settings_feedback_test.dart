import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/library.dart';

void main() {
  group('AppSettings feedback switches', () {
    test('default to enabled', () {
      const settings = AppSettings();
      expect(settings.hapticsEnabled, isTrue);
      expect(settings.soundEffectsEnabled, isTrue);
    });

    test('survive a JSON round trip', () {
      const settings = AppSettings(
        hapticsEnabled: false,
        soundEffectsEnabled: false,
      );
      final copy = AppSettings.fromJson(settings.toJson());
      expect(copy.hapticsEnabled, isFalse);
      expect(copy.soundEffectsEnabled, isFalse);
    });

    test('copyWith changes only the requested switch', () {
      const settings = AppSettings();
      final muted = settings.copyWith(hapticsEnabled: false);
      expect(muted.hapticsEnabled, isFalse);
      expect(muted.soundEffectsEnabled, isTrue);
      expect(muted.themeMode, settings.themeMode);
    });

    test('older stored settings without the keys stay enabled', () {
      final copy = AppSettings.fromJson(<String, dynamic>{
        'themeMode': 'dark',
        'localeCode': 'ar',
      });
      expect(copy.hapticsEnabled, isTrue);
      expect(copy.soundEffectsEnabled, isTrue);
    });
  });
}
