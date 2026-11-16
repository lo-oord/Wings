import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/sources/cartoony_crypto.dart';

/// Real response captured from the public catalogue (read-only endpoint).
const String _envelope =
    '{"iv":"a036bcc0fbec3c808693d503f40bfa18","encryptedData":"4d'
    'c275145776dbe6f699b0ca382b7eaca7490c5c507b1604c9bc8cd6ff4f0e'
    '3ed1a10fbc5078ef401d85b00f38d9a14aa6af2535e3aeb25f91c546a253'
    'd90a958dc4dcbf0f4b93a9a99fb0af277519441b92f17f73a551fe927b3b'
    '7cf6ecd8ed366c8900bfd54441cf6cd503b20bf01cd6991848a1d4428a73'
    '44fe3c132f0e79a38f6a8babf3a2247c21e4f1a85da1594a138a50a25d44'
    'ba672f73460cb70e37c2b01262058449c80077bb0f3fdeb09b"}';

void main() {
  group('CartoonyCrypto', () {
    test('decrypts a real catalogue envelope', () {
      final decoded = CartoonyCrypto.decode(_envelope);
      expect(decoded, isA<Map<String, dynamic>>());
      final map = (decoded! as Map).cast<String, dynamic>();
      expect(map['streamUrl'], isA<String>());
      expect(map['streamUrl'] as String, startsWith('https://'));
      expect(map['streamUrl'] as String, contains('/hls/5470/'));
    });

    test('passes plain JSON through untouched', () {
      final decoded = CartoonyCrypto.decode(
        '{"link":"https://example.com/a.m3u8"}',
      );
      expect((decoded! as Map)['link'], 'https://example.com/a.m3u8');
    });

    test('rejects malformed bodies', () {
      expect(() => CartoonyCrypto.decode('not json'), throwsFormatException);
      expect(
        () => CartoonyCrypto.decryptEnvelope(iv: 'zz', encrypted: '00'),
        throwsFormatException,
      );
    });

    test('rejects a payload with invalid padding', () {
      expect(
        () =>
            CartoonyCrypto.decryptEnvelope(iv: '00' * 16, encrypted: '00' * 16),
        throwsFormatException,
      );
    });
  });
}
