import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upeo_sms_gateway/src/auth/admin_auth_repository.dart';
import 'package:upeo_sms_gateway/src/config/config_repository.dart';
import 'package:upeo_sms_gateway/src/state/auth_providers.dart';
import 'package:upeo_sms_gateway/src/ui/widgets/config_form.dart';

/// Stands in for the password check only (its PBKDF2 runs in an isolate,
/// which widget tests' fake clock cannot drive). The form guard is real.
class _FakeAuth extends AdminAuthRepository {
  int checks = 0;

  @override
  Future<AuthResult> verify(String password) async {
    checks++;
    return password == 'admin-pw' ? const AuthGranted() : const AuthDenied(4);
  }
}

const _configured = {
  'cfg_base_url': 'https://gw.example.com',
  'cfg_device_id': 'PHONE_001',
  'cfg_secret': 'original-secret',
  'cfg_allowlist': '["MPESA"]',
  'cfg_retention_days': '14',
  'cfg_allow_http': 'false',
};

Future<_FakeAuth> _pumpForm(WidgetTester tester) async {
  final auth = _FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminAuthRepositoryProvider.overrideWithValue(auth)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ConfigForm())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Finder _secretField() =>
    find.widgetWithText(TextFormField, 'Device secret key (HMAC)');

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.text('Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  // Not pumpAndSettle: while the password dialog is open the form's busy bar
  // animates indefinitely, so pump a fixed span instead.
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<String> _savedSecret() async =>
    (await ConfigRepository().load()).secretKey;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(Map.of(_configured)));

  testWidgets('changing the secret with a wrong password saves nothing', (
    tester,
  ) async {
    await _pumpForm(tester);
    await tester.enterText(_secretField(), 'new-secret');
    await _tapSave(tester);

    expect(find.text('Admin password required'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('adminPasswordField')),
      'guess',
    );
    await tester.tap(find.text('Confirm'));
    await _pumpFrames(tester);
    expect(find.textContaining('Wrong password'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Changes not saved'), findsOneWidget);
    expect(await _savedSecret(), 'original-secret');
  });

  testWidgets('changing the secret with the right password saves it', (
    tester,
  ) async {
    await _pumpForm(tester);
    await tester.enterText(_secretField(), 'new-secret');
    await _tapSave(tester);

    await tester.enterText(
      find.byKey(const Key('adminPasswordField')),
      'admin-pw',
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Configuration saved'), findsOneWidget);
    expect(await _savedSecret(), 'new-secret');
  });

  testWidgets('saving unchanged settings does not ask for the password', (
    tester,
  ) async {
    final auth = await _pumpForm(tester);
    await _tapSave(tester);

    expect(find.text('Admin password required'), findsNothing);
    expect(auth.checks, 0);
    expect(find.text('Configuration saved'), findsOneWidget);
  });

  testWidgets('first-run setup saves without a password', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = await _pumpForm(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API base URL'),
      'https://gw.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Device ID'),
      'PHONE_001',
    );
    await tester.enterText(_secretField(), 'first-secret');
    await _tapSave(tester);

    expect(auth.checks, 0);
    expect(await _savedSecret(), 'first-secret');
  });
}
