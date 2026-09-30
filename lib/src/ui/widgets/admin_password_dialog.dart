import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/admin_auth_repository.dart';
import '../../state/auth_providers.dart';

/// Asks for the admin password. Resolves to true only when it is verified.
Future<bool> confirmAdminPassword(
  BuildContext context, {
  required String reason,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminPasswordDialog(reason: reason),
  );
  return ok ?? false;
}

class AdminPasswordDialog extends ConsumerStatefulWidget {
  const AdminPasswordDialog({super.key, required this.reason});

  final String reason;

  @override
  ConsumerState<AdminPasswordDialog> createState() =>
      _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends ConsumerState<AdminPasswordDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final result = await ref
        .read(adminAuthRepositoryProvider)
        .verify(_ctrl.text);
    if (!mounted) return;
    if (result is AuthGranted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _ctrl.clear();
      _error = authFailureMessage(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Admin password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.reason),
          const SizedBox(height: 12),
          TextField(
            key: const Key('adminPasswordField'),
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Admin password',
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

/// User-facing text for a denied or locked-out check.
String authFailureMessage(AuthResult result) => switch (result) {
  AuthDenied(:final attemptsLeft) =>
    'Wrong password. $attemptsLeft attempt(s) left before a lockout.',
  AuthLockedOut(:final until) =>
    'Too many wrong attempts. Try again after '
        '${DateFormat.Hm().format(until)}.',
  AuthGranted() => '',
};
