import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../state/auth_providers.dart';
import '../state/providers.dart';
import 'home_shell.dart';
import 'screens/create_password_screen.dart';
import 'screens/setup_screen.dart';

class UpeoApp extends ConsumerWidget {
  const UpeoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configControllerProvider);
    return MaterialApp(
      title: K.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: cfg.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Config error: $e'))),
        // First run (no usable config) → setup; otherwise the main shell.
        data: (c) => c.isComplete ? const _AdminPasswordGate() : const SetupScreen(),
      ),
    );
  }
}

/// Configured gateways need an admin password before the main shell opens, so
/// settings are never left unprotected (including installs that predate it).
class _AdminPasswordGate extends ConsumerWidget {
  const _AdminPasswordGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(adminPasswordControllerProvider).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) =>
              Scaffold(body: Center(child: Text('Password check failed: $e'))),
          data: (hasPassword) =>
              hasPassword ? const HomeShell() : const CreatePasswordScreen(),
        );
  }
}
