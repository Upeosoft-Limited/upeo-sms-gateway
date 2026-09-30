import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sms_message.dart';
import '../../state/dashboard_controller.dart';
import '../format.dart';
import '../widgets/restore_history_button.dart';

class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(logsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Log'),
        actions: [
          const RestoreHistoryButton.icon(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(logsControllerProvider.notifier).refresh(),
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No allowlisted messages yet.\n'
                      'Only SMS matching your sender allowlist are stored here.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    // After a reinstall the log starts empty; offer the way back.
                    RestoreHistoryButton(),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(logsControllerProvider.notifier).refresh(),
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (_, i) => _LogTile(record: rows[i]),
            ),
          );
        },
      ),
    );
  }
}

class _LogTile extends ConsumerWidget {
  const _LogTile({required this.record});
  final SmsRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: _statusBadge(record.status),
      title: Text(record.sender, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.maskedPreview),
          Text(
            '${Fmt.ago(record.createdAtDate)} · SIM ${record.simSlot < 0 ? '?' : record.simSlot}'
            '${record.retryCount > 0 ? ' · retries ${record.retryCount}' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (record.status == SmsStatus.failed && record.lastError != null)
            Text('Error: ${record.lastError}',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ),
      isThreeLine: true,
      trailing: record.status == SmsStatus.failed
          ? IconButton(
              icon: const Icon(Icons.replay, color: Colors.orange),
              tooltip: 'Retry now',
              onPressed: () => ref.read(logsControllerProvider.notifier).retry(record.id!),
            )
          : null,
      onTap: () => _showDetail(context, record),
    );
  }

  Widget _statusBadge(SmsStatus s) {
    late Color c;
    late IconData icon;
    switch (s) {
      case SmsStatus.pending:
        c = Colors.blue;
        icon = Icons.schedule;
        break;
      case SmsStatus.synced:
        c = Colors.green;
        icon = Icons.cloud_done;
        break;
      case SmsStatus.failed:
        c = Colors.red;
        icon = Icons.error_outline;
        break;
    }
    return CircleAvatar(backgroundColor: c.withValues(alpha: 0.15), child: Icon(icon, color: c));
  }

  void _showDetail(BuildContext context, SmsRecord r) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r.sender),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('Status', r.status.name),
              _kv('Received at', r.receivedAt),
              _kv('SIM slot', '${r.simSlot}'),
              _kv('Subscription', '${r.subscriptionId}'),
              _kv('Retries', '${r.retryCount}'),
              _kv('Synced at', Fmt.dateTime(r.syncedAtDate)),
              _kv('Hash', r.messageHash),
              const Divider(),
              const Text('Message (raw):',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(r.message),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$k: $v', style: const TextStyle(fontSize: 13)),
      );
}
