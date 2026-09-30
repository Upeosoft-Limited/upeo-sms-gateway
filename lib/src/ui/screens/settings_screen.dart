import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_log.dart';
import '../../state/dashboard_controller.dart';
import '../../state/gateway_actions.dart';
import '../../state/providers.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/config_form.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Gateway configuration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ConfigForm(),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change admin password'),
            subtitle: const Text('Required to change any gateway setting.'),
            onTap: () => _changePassword(context),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Maintenance',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('Clear synced messages'),
            subtitle: const Text('Delete all messages already confirmed by the backend.'),
            onTap: () => _clearSynced(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Export logs'),
            subtitle: const Text('View / copy the in-app diagnostic log.'),
            onTap: () => _exportLogs(context),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Check for update'),
            subtitle: const Text('Sideload builds are not auto-updated by Play.'),
            onTap: () => _checkUpdate(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin password changed')));
    }
  }

  Future<void> _clearSynced(BuildContext context, WidgetRef ref) async {
    final repo = await ref.read(smsRepositoryProvider.future);
    final n = await repo.deleteSynced();
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(logsControllerProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted $n synced messages')));
    }
  }

  void _exportLogs(BuildContext context) {
    final text = AppLog.export();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Diagnostic log'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '(empty)' : text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.of(context).pop();
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    final latest = await ref.read(gatewayActionsProvider).checkForUpdate();
    if (!context.mounted) return;
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No update info available')));
      return;
    }
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final latestVer = (latest['version'] ?? '').toString();
    final url = (latest['url'] ?? latest['apk_url'] ?? '').toString();
    final notes = (latest['notes'] ?? '').toString();
    final isNewer = latestVer.isNotEmpty && latestVer != current;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isNewer ? 'Update available' : 'Up to date'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Installed: $current'),
            Text('Latest: ${latestVer.isEmpty ? 'unknown' : latestVer}'),
            if (notes.isNotEmpty) ...[const SizedBox(height: 8), Text(notes)],
          ],
        ),
        actions: [
          if (isNewer && url.isNotEmpty)
            FilledButton(
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Download APK'),
            ),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
