import 'package:flutter_test/flutter_test.dart';
import 'package:upeo_sms_gateway/src/auth/config_change_policy.dart';
import 'package:upeo_sms_gateway/src/config/app_config.dart';

void main() {
  const policy = ConfigChangePolicy();
  const saved = AppConfig(
    apiBaseUrl: 'https://gw.example.com',
    deviceId: 'PHONE_001',
    secretKey: 'abc',
    allowlist: ['MPESA'],
    retentionDays: 14,
    allowInsecureHttp: false,
  );

  test('first-run setup needs no password', () {
    expect(
      policy.requiresPassword(saved: AppConfig.empty, edited: saved),
      isFalse,
    );
  });

  test('re-saving identical values needs no password', () {
    expect(
      policy.requiresPassword(saved: saved, edited: saved.copyWith()),
      isFalse,
    );
  });

  test('surrounding whitespace in URL / Device ID is not a change', () {
    final edited = saved.copyWith(
      apiBaseUrl: ' https://gw.example.com ',
      deviceId: 'PHONE_001 ',
    );
    expect(policy.requiresPassword(saved: saved, edited: edited), isFalse);
  });

  final changes = <String, AppConfig>{
    'secret': saved.copyWith(secretKey: 'xyz'),
    'device id': saved.copyWith(deviceId: 'PHONE_002'),
    'url': saved.copyWith(apiBaseUrl: 'https://other.example.com'),
    'allowlist': saved.copyWith(allowlist: ['MPESA', 'KCB']),
    'retention': saved.copyWith(retentionDays: 7),
    'insecure http': saved.copyWith(allowInsecureHttp: true),
  };
  changes.forEach((field, edited) {
    test('changing the $field needs the password', () {
      expect(policy.requiresPassword(saved: saved, edited: edited), isTrue);
    });
  });
}
