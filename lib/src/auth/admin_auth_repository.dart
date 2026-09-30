import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'password_hasher.dart';

/// Outcome of an admin-password check.
sealed class AuthResult {
  const AuthResult();
}

class AuthGranted extends AuthResult {
  const AuthGranted();
}

class AuthDenied extends AuthResult {
  const AuthDenied(this.attemptsLeft);
  final int attemptsLeft;
}

class AuthLockedOut extends AuthResult {
  const AuthLockedOut(this.until);
  final DateTime until;
}

/// The local admin password that guards gateway configuration changes, so a
/// casual user of the till phone cannot alter the device secret (or any other
/// setting) and silently break sync.
///
/// Stored as a PBKDF2 hash in the same Keystore-backed secure storage as the
/// config. Failed attempts and the lockout are persisted, so restarting the
/// app does not reset them.
class AdminAuthRepository {
  AdminAuthRepository({
    FlutterSecureStorage? storage,
    this._hasher = const PasswordHasher(),
    DateTime Function()? clock,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _now = clock ?? DateTime.now;

  static const int minLength = 6;
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 5);

  static const _kHash = 'auth_admin_password';
  static const _kFailures = 'auth_failed_attempts';
  static const _kLockedUntil = 'auth_locked_until';

  final FlutterSecureStorage _storage;
  final PasswordHasher _hasher;
  final DateTime Function() _now;

  Future<bool> hasPassword() async {
    final stored = await _storage.read(key: _kHash);
    return stored != null && stored.isNotEmpty;
  }

  /// Sets the first password. Refuses to overwrite an existing one, which must
  /// go through [changePassword] instead.
  Future<void> createPassword(String password) async {
    _checkStrength(password);
    if (await hasPassword()) {
      throw StateError('An admin password is already set');
    }
    await _storage.write(key: _kHash, value: await _hasher.hash(password));
  }

  /// Replaces the password after verifying the current one.
  Future<AuthResult> changePassword(String current, String next) async {
    _checkStrength(next);
    final result = await verify(current);
    if (result is AuthGranted) {
      await _storage.write(key: _kHash, value: await _hasher.hash(next));
    }
    return result;
  }

  /// Checks [password], counting failures toward the lockout.
  Future<AuthResult> verify(String password) async {
    final lockedUntil = await _lockedUntil();
    if (lockedUntil != null) return AuthLockedOut(lockedUntil);

    final stored = await _storage.read(key: _kHash);
    if (stored != null && await _hasher.verify(password, stored)) {
      await _clearFailures();
      return const AuthGranted();
    }
    return _recordFailure();
  }

  void _checkStrength(String password) {
    if (password.length < minLength) {
      throw ArgumentError(
        'Password must be at least $minLength characters',
        'password',
      );
    }
  }

  Future<DateTime?> _lockedUntil() async {
    final raw = await _storage.read(key: _kLockedUntil);
    final until = raw == null ? null : DateTime.tryParse(raw);
    if (until == null || !_now().isBefore(until)) return null;
    return until;
  }

  Future<AuthResult> _recordFailure() async {
    final failures =
        (int.tryParse(await _storage.read(key: _kFailures) ?? '') ?? 0) + 1;
    if (failures >= maxAttempts) {
      final until = _now().add(lockoutDuration);
      await _storage.write(key: _kLockedUntil, value: until.toIso8601String());
      await _storage.write(key: _kFailures, value: '0');
      return AuthLockedOut(until);
    }
    await _storage.write(key: _kFailures, value: '$failures');
    return AuthDenied(maxAttempts - failures);
  }

  Future<void> _clearFailures() async {
    await _storage.delete(key: _kFailures);
    await _storage.delete(key: _kLockedUntil);
  }
}
