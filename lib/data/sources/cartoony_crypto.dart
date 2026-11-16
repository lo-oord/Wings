import 'dart:convert';

/// Decoder for the catalogue envelopes.
///
/// The public endpoints answer with `{"iv": "<hex>", "encryptedData": "<hex>"}`
/// where the payload is AES-CBC (PKCS#7) encrypted JSON. Plain JSON answers are
/// passed through untouched. The implementation is self-contained so the data
/// layer stays free of native or platform crypto dependencies.
abstract final class CartoonyCrypto {
  /// Public client key published by the catalogue for its read-only endpoints.
  static const String key = '7annaba3l_loves_crypto_safe_key!';

  /// Unwraps and decodes a response body.
  static Object? decode(String body) {
    final Object? parsed;
    try {
      parsed = jsonDecode(body);
    } on FormatException {
      throw const FormatException('catalogue returned malformed JSON');
    }
    if (parsed is! Map) return parsed;

    final envelope = parsed.cast<String, dynamic>();
    final iv = envelope['iv'];
    final data = envelope['encryptedData'];
    if (iv is! String || data is! String) return parsed;

    final clear = decryptEnvelope(iv: iv, encrypted: data);
    try {
      return jsonDecode(utf8.decode(clear));
    } on FormatException {
      throw const FormatException('catalogue envelope did not decrypt');
    }
  }

  /// Decrypts one AES-CBC envelope into its UTF-8 JSON bytes.
  static List<int> decryptEnvelope({
    required String iv,
    required String encrypted,
    String keyText = key,
  }) {
    final keyBytes = utf8.encode(keyText);
    final ivBytes = hexToBytes(iv);
    final cipherBytes = hexToBytes(encrypted);
    if (ivBytes.length != 16) {
      throw const FormatException('catalogue IV has an invalid length');
    }
    if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) {
      throw const FormatException('catalogue payload has an invalid length');
    }

    final roundKeys = _expandKey(keyBytes);
    final output = <int>[];
    var previous = ivBytes;
    for (var offset = 0; offset < cipherBytes.length; offset += 16) {
      final block = cipherBytes.sublist(offset, offset + 16);
      final clear = _decryptBlock(block, roundKeys);
      for (var i = 0; i < 16; i++) {
        output.add(clear[i] ^ previous[i]);
      }
      previous = block;
    }
    return _unpadPkcs7(output);
  }

  /// Decodes a lowercase or uppercase hex string.
  static List<int> hexToBytes(String hex) {
    if (hex.length.isOdd) {
      throw const FormatException('catalogue hex string has an odd length');
    }
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final value = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (value == null) {
        throw const FormatException('catalogue hex string is invalid');
      }
      bytes.add(value);
    }
    return bytes;
  }

  static List<int> _unpadPkcs7(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('catalogue payload is empty');
    }
    final padding = bytes.last;
    if (padding < 1 || padding > 16 || padding > bytes.length) {
      throw const FormatException('catalogue padding is invalid');
    }
    for (var i = bytes.length - padding; i < bytes.length; i++) {
      if (bytes[i] != padding) {
        throw const FormatException('catalogue padding is invalid');
      }
    }
    return bytes.sublist(0, bytes.length - padding);
  }

  // -- AES (FIPS-197) ------------------------------------------------------

  static final List<int> _sbox = _buildSbox();
  static final List<int> _inverseSbox = _buildInverseSbox(_sbox);

  static List<int> _buildSbox() {
    final box = List<int>.filled(256, 0);
    for (var value = 0; value < 256; value++) {
      final inverse = value == 0 ? 0 : _power(value, 254);
      box[value] =
          inverse ^
          _rotate(inverse, 1) ^
          _rotate(inverse, 2) ^
          _rotate(inverse, 3) ^
          _rotate(inverse, 4) ^
          0x63;
    }
    return box;
  }

  static List<int> _buildInverseSbox(List<int> sbox) {
    final inverse = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      inverse[sbox[i]] = i;
    }
    return inverse;
  }

  static int _power(int value, int exponent) {
    var result = 1;
    var base = value;
    var power = exponent;
    while (power > 0) {
      if (power & 1 == 1) {
        result = _multiply(result, base);
      }
      base = _multiply(base, base);
      power >>= 1;
    }
    return result;
  }

  static int _multiply(int a, int b) {
    var result = 0;
    var left = a;
    var right = b;
    for (var i = 0; i < 8; i++) {
      if (right & 1 == 1) result ^= left;
      final high = left & 0x80;
      left = (left << 1) & 0xff;
      if (high != 0) left ^= 0x1b;
      right >>= 1;
    }
    return result & 0xff;
  }

  static int _rotate(int value, int shift) =>
      ((value << shift) | (value >> (8 - shift))) & 0xff;

  /// Expands the key into 16-byte round keys (10, 12 or 14 rounds).
  static List<int> _expandKey(List<int> key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw const FormatException('catalogue key has an invalid length');
    }
    final words = key.length ~/ 4;
    final rounds = words + 6;
    final schedule = List<int>.filled(4 * (rounds + 1) * 4, 0);

    for (var i = 0; i < key.length; i++) {
      schedule[i] = key[i];
    }

    var rcon = 1;
    for (var word = words; word < 4 * (rounds + 1); word++) {
      var temp = <int>[
        schedule[(word - 1) * 4],
        schedule[(word - 1) * 4 + 1],
        schedule[(word - 1) * 4 + 2],
        schedule[(word - 1) * 4 + 3],
      ];
      if (word % words == 0) {
        temp = <int>[
          _sbox[temp[1]],
          _sbox[temp[2]],
          _sbox[temp[3]],
          _sbox[temp[0]],
        ];
        temp[0] ^= rcon;
        rcon = _multiply(rcon, 2);
      } else if (words > 6 && word % words == 4) {
        temp = <int>[
          _sbox[temp[0]],
          _sbox[temp[1]],
          _sbox[temp[2]],
          _sbox[temp[3]],
        ];
      }
      for (var i = 0; i < 4; i++) {
        schedule[word * 4 + i] = schedule[(word - words) * 4 + i] ^ temp[i];
      }
    }
    return schedule;
  }

  static List<int> _decryptBlock(List<int> block, List<int> schedule) {
    final rounds = schedule.length ~/ 16 - 1;
    final state = List<int>.from(block);

    _addRoundKey(state, schedule, rounds);
    for (var round = rounds - 1; round >= 1; round--) {
      _inverseShiftRows(state);
      for (var i = 0; i < 16; i++) {
        state[i] = _inverseSbox[state[i]];
      }
      _addRoundKey(state, schedule, round);
      _inverseMixColumns(state);
    }
    _inverseShiftRows(state);
    for (var i = 0; i < 16; i++) {
      state[i] = _inverseSbox[state[i]];
    }
    _addRoundKey(state, schedule, 0);
    return state;
  }

  static void _addRoundKey(List<int> state, List<int> schedule, int round) {
    final offset = round * 16;
    for (var i = 0; i < 16; i++) {
      state[i] ^= schedule[offset + i];
    }
  }

  static void _inverseShiftRows(List<int> state) {
    for (var row = 1; row < 4; row++) {
      final values = <int>[
        state[row],
        state[row + 4],
        state[row + 8],
        state[row + 12],
      ];
      for (var column = 0; column < 4; column++) {
        state[row + column * 4] = values[(column - row) % 4];
      }
    }
  }

  static void _inverseMixColumns(List<int> state) {
    for (var column = 0; column < 4; column++) {
      final index = column * 4;
      final a0 = state[index];
      final a1 = state[index + 1];
      final a2 = state[index + 2];
      final a3 = state[index + 3];
      state[index] =
          _multiply(a0, 14) ^
          _multiply(a1, 11) ^
          _multiply(a2, 13) ^
          _multiply(a3, 9);
      state[index + 1] =
          _multiply(a0, 9) ^
          _multiply(a1, 14) ^
          _multiply(a2, 11) ^
          _multiply(a3, 13);
      state[index + 2] =
          _multiply(a0, 13) ^
          _multiply(a1, 9) ^
          _multiply(a2, 14) ^
          _multiply(a3, 11);
      state[index + 3] =
          _multiply(a0, 11) ^
          _multiply(a1, 13) ^
          _multiply(a2, 9) ^
          _multiply(a3, 14);
    }
  }
}
