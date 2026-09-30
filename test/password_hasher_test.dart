import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:upeo_sms_gateway/src/auth/password_hasher.dart';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // Expected values from Python's hashlib.pbkdf2_hmac; the first is also
    // the RFC 7914 §11 test vector.
    test('matches RFC 7914 vector (multi-block output)', () {
      final dk = PasswordHasher.pbkdf2(
        utf8.encode('passwd'),
        utf8.encode('salt'),
        1,
        64,
      );
      expect(
        _hex(dk),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('matches hashlib for many iterations', () {
      final dk = PasswordHasher.pbkdf2(
        utf8.encode('Password'),
        utf8.encode('NaCl'),
        4096,
        32,
      );
      expect(
        _hex(dk),
        '438b6f1df76520b1c9989ddf976545b40f1ab4d9da723a81aa5083108b0da61f',
      );
    });

    test('matches hashlib for UTF-8 password and truncated block', () {
      final dk = PasswordHasher.pbkdf2(
        utf8.encode('päss'),
        utf8.encode('saltSALTsalt'),
        10,
        40,
      );
      expect(
        _hex(dk),
        'f0f0684a88f3921e6f84eac0a18befc3ecde72d65f80cab6b42ce3f048e767fe'
        '6095722d960d5e29',
      );
    });
  });

  group('PasswordHasher', () {
    const hasher = PasswordHasher(iterations: 1000);

    test('verifies the right password and rejects a wrong one', () async {
      final encoded = await hasher.hash('correct horse');
      expect(await hasher.verify('correct horse', encoded), isTrue);
      expect(await hasher.verify('correct horsE', encoded), isFalse);
    });

    test('salts each hash, and stores its iteration count', () async {
      final a = await hasher.hash('same');
      final b = await hasher.hash('same');
      expect(a, isNot(b));
      expect(a, startsWith(r'pbkdf2-sha256$1000$'));
    });

    test('verifies with the stored count, not the current default', () async {
      final old = await const PasswordHasher(iterations: 500).hash('pw1234');
      expect(await hasher.verify('pw1234', old), isTrue);
    });

    test('never matches a malformed record', () async {
      expect(await hasher.verify('x', ''), isFalse);
      expect(await hasher.verify('x', r'md5$1$a$b'), isFalse);
      expect(await hasher.verify('x', r'pbkdf2-sha256$0$AAAA$AAAA'), isFalse);
    });
  });
}
