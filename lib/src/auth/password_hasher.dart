import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted PBKDF2-HMAC-SHA256 hashing for the local admin password.
///
/// The `crypto` package has no PBKDF2, so it is implemented here per RFC 8018
/// (verified against Python's `hashlib.pbkdf2_hmac` in the tests). The encoded
/// form carries its own iteration count, so the cost can be raised later
/// without invalidating stored passwords.
class PasswordHasher {
  const PasswordHasher({this.iterations = defaultIterations});

  // Measured 0.27 s on a laptop (AOT); estimated ~1 s on a budget phone.
  // Modest by desktop standards, but the hash sits in Keystore-backed storage
  // behind a lockout, and each record keeps its own count so this can rise.
  static const int defaultIterations = 50000;
  static const String _scheme = 'pbkdf2-sha256';
  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  final int iterations;

  /// Returns `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>`.
  /// Runs off the UI isolate so the key stretching never janks a frame.
  Future<String> hash(String password) async {
    final salt = _randomSalt();
    final rounds = iterations;
    final key = await Isolate.run(
      () => pbkdf2(utf8.encode(password), salt, rounds, _keyBytes),
    );
    return [
      _scheme,
      '$rounds',
      base64Encode(salt),
      base64Encode(key),
    ].join(r'$');
  }

  /// Whether [password] matches [encoded]. A malformed record never matches.
  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) return false;
    final salt = base64Decode(parts[2]);
    final expected = base64Decode(parts[3]);
    final actual = await Isolate.run(
      () => pbkdf2(utf8.encode(password), salt, rounds, expected.length),
    );
    return _constantTimeEquals(actual, expected);
  }

  /// RFC 8018 PBKDF2 with HMAC-SHA256 as the PRF.
  static Uint8List pbkdf2(
    List<int> password,
    List<int> salt,
    int rounds,
    int length,
  ) {
    final mac = Hmac(sha256, password);
    final out = BytesBuilder(copy: false);
    for (var block = 1; out.length < length; block++) {
      var u = mac.convert([...salt, ..._int32BigEndian(block)]).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < rounds; i++) {
        u = mac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return Uint8List.sublistView(out.takeBytes(), 0, length);
  }

  static List<int> _int32BigEndian(int i) => [
    (i >> 24) & 0xff,
    (i >> 16) & 0xff,
    (i >> 8) & 0xff,
    i & 0xff,
  ];

  static Uint8List _randomSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => rng.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
