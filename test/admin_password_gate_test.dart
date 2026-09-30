import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upeo_sms_gateway/src/auth/admin_auth_repository.dart';
import 'package:upeo_sms_gateway/src/auth/password_hasher.dart';
import 'package:upeo_sms_gateway/src/state/auth_providers.dart';
import 'package:upeo_sms_gateway/src/ui/app.dart';
import 'package:upeo_sms_gateway/src/ui/screens/create_password_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a configured phone without a password must create one first', (
    tester,
  ) async {
    // An install configured before admin passwords existed.
    FlutterSecureStorage.setMockInitialValues({
      'cfg_base_url': 'https://gw.example.com',
      'cfg_device_id': 'PHONE_001',
      'cfg_secret': 'original-secret',
    });
    await tester.pumpWidget(const ProviderScope(child: UpeoApp()));
    await tester.pumpAndSettle();

    expect(find.byType(CreatePasswordScreen), findsOneWidget);
  });

  test('creating the password flips the gate open', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        adminAuthRepositoryProvider.overrideWithValue(
          AdminAuthRepository(hasher: const PasswordHasher(iterations: 1000)),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(adminPasswordControllerProvider.future), false);
    await container
        .read(adminPasswordControllerProvider.notifier)
        .create('s3cret!');
    expect(container.read(adminPasswordControllerProvider).value, true);
  });
}
