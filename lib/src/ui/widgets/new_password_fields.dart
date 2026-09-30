import 'package:flutter/material.dart';

import '../../auth/admin_auth_repository.dart';

/// Controllers for a "new password + confirm" pair.
class NewPasswordControllers {
  final password = TextEditingController();
  final confirm = TextEditingController();

  void dispose() {
    password.dispose();
    confirm.dispose();
  }
}

/// "New password" and "Confirm password" fields with validation. Must sit
/// inside a [Form].
class NewPasswordFields extends StatelessWidget {
  const NewPasswordFields({
    super.key,
    required this.controllers,
    this.enabled = true,
  });

  final NewPasswordControllers controllers;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('newPasswordField'),
          controller: controllers.password,
          obscureText: true,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'New admin password',
            helperText: 'At least ${AdminAuthRepository.minLength} characters.',
            border: OutlineInputBorder(),
          ),
          validator: (v) => (v ?? '').length < AdminAuthRepository.minLength
              ? 'Use at least ${AdminAuthRepository.minLength} characters'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('confirmPasswordField'),
          controller: controllers.confirm,
          obscureText: true,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              v != controllers.password.text ? 'Passwords do not match' : null,
        ),
      ],
    );
  }
}
