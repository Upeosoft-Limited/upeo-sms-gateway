import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_providers.dart';
import '../widgets/new_password_fields.dart';

/// One-time gate: shown once the gateway is configured but no admin password
/// exists yet (first setup, or an install upgraded from a version without
/// passwords). The gateway keeps forwarding in the background meanwhile.
class CreatePasswordScreen extends ConsumerStatefulWidget {
  const CreatePasswordScreen({super.key});

  @override
  ConsumerState<CreatePasswordScreen> createState() =>
      _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends ConsumerState<CreatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = NewPasswordControllers();
  bool _busy = false;

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // On success the app routes to the dashboard by itself.
      await ref
          .read(adminPasswordControllerProvider.notifier)
          .create(_fields.password.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save password: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create admin password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'This password protects the gateway settings. It will be asked '
              'for whenever anyone changes the device secret, Device ID, API '
              'URL or any other setting, so sync cannot be broken by '
              'accident.\n\nKeep it with the person who manages this phone. '
              'If it is lost, the only way back in is clearing the app data '
              'and setting the gateway up again.',
            ),
            const SizedBox(height: 16),
            NewPasswordFields(controllers: _fields, enabled: !_busy),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.lock),
              label: const Text('Save password'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
