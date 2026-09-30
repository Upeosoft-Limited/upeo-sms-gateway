import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/admin_auth_repository.dart';
import '../../state/auth_providers.dart';
import 'admin_password_dialog.dart';
import 'new_password_fields.dart';

/// Changes the admin password; the current one is required.
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _fields = NewPasswordControllers();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _fields.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final result = await ref
        .read(adminAuthRepositoryProvider)
        .changePassword(_current.text, _fields.password.text);
    if (!mounted) return;
    if (result is AuthGranted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _current.clear();
      _error = authFailureMessage(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change admin password'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              NewPasswordFields(controllers: _fields, enabled: !_busy),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Change'),
        ),
      ],
    );
  }
}
