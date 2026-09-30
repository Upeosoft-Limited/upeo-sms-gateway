import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/admin_auth_repository.dart';
import '../auth/config_change_policy.dart';

final adminAuthRepositoryProvider = Provider<AdminAuthRepository>(
  (ref) => AdminAuthRepository(),
);

final configChangePolicyProvider = Provider<ConfigChangePolicy>(
  (ref) => const ConfigChangePolicy(),
);

/// Whether an admin password exists. Drives the one-time "create password"
/// gate for installs configured before passwords existed.
class AdminPasswordController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(adminAuthRepositoryProvider).hasPassword();

  Future<void> create(String password) async {
    await ref.read(adminAuthRepositoryProvider).createPassword(password);
    state = const AsyncData(true);
  }
}

final adminPasswordControllerProvider =
    AsyncNotifierProvider<AdminPasswordController, bool>(
      AdminPasswordController.new,
    );
