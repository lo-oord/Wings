import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/app_update.dart';

void main() {
  group('AppUpdate', () {
    test('compares semantic versions, then the build number', () {
      const update = AppUpdate(
        version: '1.2.0',
        build: 14,
        apkUrl: 'https://example.com/wings.apk',
      );
      expect(
        update.isNewerThan(currentVersion: '1.1.9', currentBuild: 99),
        isTrue,
      );
      expect(
        update.isNewerThan(currentVersion: '1.2.0', currentBuild: 13),
        isTrue,
      );
      expect(
        update.isNewerThan(currentVersion: '1.2.0', currentBuild: 14),
        isFalse,
      );
      expect(
        update.isNewerThan(currentVersion: '1.3.0', currentBuild: 1),
        isFalse,
      );
    });

    test('picks the package that matches the device ABI', () {
      const update = AppUpdate(
        version: '1.1.0',
        build: 3,
        apkUrl: 'https://wingsapp.vercel.app/downloads/wings-universal.apk',
        apkUrls: <String, String>{
          'arm64-v8a': 'https://wingsapp.vercel.app/downloads/wings-arm64.apk',
          'armeabi-v7a': 'https://wingsapp.vercel.app/downloads/wings-arm.apk',
          'universal':
              'https://wingsapp.vercel.app/downloads/wings-universal.apk',
        },
      );
      expect(
        update.urlForAbi(const <String>['arm64-v8a', 'armeabi-v7a']),
        contains('wings-arm64.apk'),
      );
      expect(
        update.urlForAbi(const <String>['armeabi-v7a']),
        contains('wings-arm.apk'),
      );
      expect(
        update.urlForAbi(const <String>['mips']),
        contains('wings-universal.apk'),
      );
    });

    test('keeps the manifest url when no per-ABI map is published', () {
      const update = AppUpdate(
        version: '1.0.1',
        build: 2,
        apkUrl: 'https://wingsapp.vercel.app/downloads/wings.apk',
      );
      expect(
        update.urlForAbi(const <String>['arm64-v8a']),
        'https://wingsapp.vercel.app/downloads/wings.apk',
      );
    });

    test('parses the published manifest', () {
      final update = AppUpdate.fromJson(<String, dynamic>{
        'version': '1.0.1',
        'build': 2,
        'apk_url': 'https://example.com/wings.apk',
        'apk_urls': <String, dynamic>{
          'arm64-v8a': 'https://example.com/wings-arm64.apk',
          'Universal': 'https://example.com/wings-universal.apk',
        },
        'page_url': 'https://wingsapp.vercel.app/download',
        'mandatory': true,
        'welcome': 'أهلاً بك',
        'notes_ar': <String>['أسرع', 'أجمل'],
        'notes_en': <String>['Faster', 'Prettier'],
      });
      expect(update, isNotNull);
      expect(update!.version, '1.0.1');
      expect(update.mandatory, isTrue);
      expect(update.notesAr, <String>['أسرع', 'أجمل']);
      expect(update.notesEn, <String>['Faster', 'Prettier']);
      expect(update.apkUrls['arm64-v8a'], contains('arm64'));
      expect(update.apkUrls['universal'], contains('universal'));
      expect(update.id, '1.0.1+2');
    });

    test('rejects a manifest without a version or download', () {
      expect(AppUpdate.fromJson(null), isNull);
      expect(AppUpdate.fromJson(<String, dynamic>{'build': 2}), isNull);
      expect(AppUpdate.fromJson(<String, dynamic>{'version': '1.0.1'}), isNull);
    });
  });
}
