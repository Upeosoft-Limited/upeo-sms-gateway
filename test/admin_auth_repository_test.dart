import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upeo_sms_gateway/src/auth/admin_auth_repository.dart';
import 'package:upeo_sms_gateway/src/auth/password_hasher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late AdminAuthRepository repo;

  AdminAuthRepository build() => AdminAuthRepository(
    hasher: const PasswordHasher(iterations: 1000),
    clock: () => now,
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    now = DateTime(2026, 9, 30, 10);
    repo = build();
  });

  test('starts with no password', () async {
    expect(await repo.hasPassword(), isFalse);
  });

  test('stores a hash, never the plain password', () async {
    await repo.createPassword('s3cret!');
    expect(await repo.hasPassword(), isTrue);
    final all = await const FlutterSecureStorage().readAll();
    expect(all.values, isNot(contains('s3cret!')));
  });

  test('verifies the right password', () async {
    await repo.createPassword('s3cret!');
    expect(await repo.verify('s3cret!'), isA<AuthGranted>());
  });

  test('denies a wrong password and counts down attempts', () async {
    await repo.createPassword('s3cret!');
    final r = await repo.verify('nope');
    expect(r, isA<AuthDenied>());
    expect((r as AuthDenied).attemptsLeft, AdminAuthRepository.maxAttempts - 1);
  });

  test('rejects short passwords', () async {
    expect(() => repo.createPassword('12345'), throwsArgumentError);
  });

  test('refuses to overwrite an existing password on create', () async {
    await repo.createPassword('s3cret!');
    expect(() => repo.createPassword('other-pw'), throwsStateError);
    expect(await repo.verify('s3cret!'), isA<AuthGranted>());
  });

  test('locks out after max failures, even for the right password', () async {
    await repo.createPassword('s3cret!');
    AuthResult last = const AuthGranted();
    for (var i = 0; i < AdminAuthRepository.maxAttempts; i++) {
      last = await repo.verify('wrong');
    }
    expect(last, isA<AuthLockedOut>());
    expect(await repo.verify('s3cret!'), isA<AuthLockedOut>());
  });

  test('lockout survives an app restart and expires on time', () async {
    await repo.createPassword('s3cret!');
    for (var i = 0; i < AdminAuthRepository.maxAttempts; i++) {
      await repo.verify('wrong');
    }
    repo = build(); // fresh instance, same storage
    expect(await repo.verify('s3cret!'), isA<AuthLockedOut>());
    now = now.add(AdminAuthRepository.lockoutDuration);
    expect(await repo.verify('s3cret!'), isA<AuthGranted>());
  });

  test('a success resets the failure count', () async {
    await repo.createPassword('s3cret!');
    for (var i = 0; i < AdminAuthRepository.maxAttempts - 1; i++) {
      await repo.verify('wrong');
    }
    await repo.verify('s3cret!');
    final r = await repo.verify('wrong');
    expect((r as AuthDenied).attemptsLeft, AdminAuthRepository.maxAttempts - 1);
  });

  test('changePassword needs the current password', () async {
    await repo.createPassword('s3cret!');
    expect(await repo.changePassword('wrong', 'newpass1'), isA<AuthDenied>());
    expect(await repo.verify('s3cret!'), isA<AuthGranted>());

    expect(
      await repo.changePassword('s3cret!', 'newpass1'),
      isA<AuthGranted>(),
    );
    expect(await repo.verify('newpass1'), isA<AuthGranted>());
    expect(await repo.verify('s3cret!'), isA<AuthDenied>());
  });
}
