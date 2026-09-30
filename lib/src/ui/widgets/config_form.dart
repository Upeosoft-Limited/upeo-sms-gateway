import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../services/api_client.dart';
import '../../state/auth_providers.dart';
import '../../state/gateway_actions.dart';
import '../../state/providers.dart';
import 'admin_password_dialog.dart';

/// Reusable editor for the gateway configuration, used by both Setup and
/// Settings. Includes Save and Test Connection (a signed heartbeat handshake).
///
/// Renders as a non-scrolling [Column]; the parent screen supplies the scroll
/// view, so the Save / Test Connection buttons are always reachable.
class ConfigForm extends ConsumerStatefulWidget {
  const ConfigForm({super.key, this.onSaved});

  /// Called after a successful save (e.g. to pop the setup flow).
  final VoidCallback? onSaved;

  @override
  ConsumerState<ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<ConfigForm> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _allowlistCtrl = TextEditingController();
  final _retentionCtrl = TextEditingController();

  bool _secretVisible = false;
  bool _allowHttp = false;
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _deviceCtrl.dispose();
    _secretCtrl.dispose();
    _allowlistCtrl.dispose();
    _retentionCtrl.dispose();
    super.dispose();
  }

  void _hydrate(AppConfig cfg) {
    if (_loaded) return;
    _loaded = true;
    _urlCtrl.text = cfg.apiBaseUrl;
    _deviceCtrl.text = cfg.deviceId;
    _secretCtrl.text = cfg.secretKey;
    _allowlistCtrl.text = cfg.allowlist.join(', ');
    _retentionCtrl.text = '${cfg.retentionDays}';
    _allowHttp = cfg.allowInsecureHttp;
  }

  AppConfig _collect() {
    final allowlist = _allowlistCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return AppConfig(
      apiBaseUrl: _urlCtrl.text.trim(),
      deviceId: _deviceCtrl.text.trim(),
      secretKey: _secretCtrl.text,
      allowlist: allowlist.isEmpty ? const ['MPESA'] : allowlist,
      retentionDays: int.tryParse(_retentionCtrl.text.trim()) ?? 14,
      allowInsecureHttp: _allowHttp,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (!await _persist()) return;
      if (mounted) {
        _snack('Configuration saved');
        widget.onSaved?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // Persist first so the heartbeat uses the latest values.
      if (!await _persist()) return;
      final res = await ref.read(gatewayActionsProvider).testConnection();
      if (!mounted) return;
      final ok = res.outcome == SendOutcome.success;
      _snack(
        ok ? 'Connection OK — heartbeat accepted' : 'Test failed: ${res.detail}',
        error: !ok,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves the form, first asking for the admin password when the change
  /// needs it. Returns false (nothing saved) if the password was not given.
  Future<bool> _persist() async {
    final edited = _collect();
    final saved = await ref.read(configControllerProvider.future);
    final needsPassword = ref
        .read(configChangePolicyProvider)
        .requiresPassword(saved: saved, edited: edited);
    if (needsPassword) {
      if (!mounted) return false;
      final ok = await confirmAdminPassword(context,
          reason: 'Changing the gateway settings can stop sync. Enter the '
              'admin password to save these changes.');
      if (!ok) {
        if (mounted) _snack('Changes not saved', error: true);
        return false;
      }
    }
    await ref.read(configControllerProvider.notifier).save(edited);
    return true;
  }

  /// Generate a strong random secret. You must register the SAME value on the
  /// backend for this Device ID (see the help text / README).
  void _generateSecret() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    setState(() {
      _secretCtrl.text = base64Url.encode(bytes);
      _secretVisible = true;
    });
    Clipboard.setData(ClipboardData(text: _secretCtrl.text));
    _snack('Secret generated and copied — register it on the backend');
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configControllerProvider);
    return cfgAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load config: $e'),
      ),
      data: (cfg) {
        _hydrate(cfg);
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'API base URL',
                  hintText: 'https://gateway.example.com',
                  helperText: 'Your backend root (FastAPI/ERPNext). HTTPS required.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  final uri = Uri.tryParse(s);
                  if (uri == null || !uri.hasScheme) return 'Enter a full URL';
                  if (!s.toLowerCase().startsWith('https://') && !_allowHttp) {
                    return 'HTTPS required (or enable debug HTTP below)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  hintText: 'PHONE_001',
                  helperText:
                      'A unique name YOU choose for this phone (e.g. PHONE_001, '
                      'SHOP_NRB_01). Must match the device record on the backend.',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secretCtrl,
                obscureText: !_secretVisible,
                decoration: InputDecoration(
                  labelText: 'Device secret key (HMAC)',
                  helperText:
                      'A shared secret YOU generate, registered on the backend '
                      'for this Device ID. Tap the key icon to generate one.',
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Generate strong secret',
                        icon: const Icon(Icons.key),
                        onPressed: _generateSecret,
                      ),
                      IconButton(
                        tooltip: _secretVisible ? 'Hide' : 'Show',
                        icon: Icon(_secretVisible
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _secretVisible = !_secretVisible),
                      ),
                    ],
                  ),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _allowlistCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sender allowlist (comma-separated)',
                  helperText:
                      'Only SMS whose sender matches one of these is stored/forwarded. '
                      'Default: MPESA',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _retentionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Retention window (days)',
                  helperText: 'Synced messages are auto-purged after this many days.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow insecure HTTP (debug only)'),
                subtitle: const Text(
                    'Leave OFF in production. HTTPS protects SMS PII in transit.'),
                value: _allowHttp,
                onChanged: (v) => setState(() => _allowHttp = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _testConnection,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Test Connection'),
                    ),
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
