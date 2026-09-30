import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/history_restore_service.dart';
import '../../state/gateway_actions.dart';

/// "Restore from server": refills the log with the messages the backend
/// already received from this phone. Shown as an app-bar icon, or as a full
/// button on the empty log (the usual state right after a reinstall).
class RestoreHistoryButton extends ConsumerStatefulWidget {
  const RestoreHistoryButton({super.key}) : _asIcon = false;
  const RestoreHistoryButton.icon({super.key}) : _asIcon = true;

  final bool _asIcon;

  @override
  ConsumerState<RestoreHistoryButton> createState() =>
      _RestoreHistoryButtonState();
}

class _RestoreHistoryButtonState extends ConsumerState<RestoreHistoryButton> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(gatewayActionsProvider).restoreHistory();
      if (mounted) _report(result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(RestoreResult r) {
    final text = !r.isOk
        ? 'Could not restore from server: ${r.error}'
        : r.restored == 0
        ? 'Nothing new to restore'
        : 'Restored ${r.restored} message(s) from the server';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: r.isOk ? null : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget._asIcon) {
      return IconButton(
        icon: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_download),
        tooltip: 'Restore from server',
        onPressed: _busy ? null : _restore,
      );
    }
    return FilledButton.icon(
      onPressed: _busy ? null : _restore,
      icon: const Icon(Icons.cloud_download),
      label: Text(_busy ? 'Restoring…' : 'Restore from server'),
    );
  }
}
