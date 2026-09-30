import '../config/app_config.dart';
import '../core/app_log.dart';
import '../core/canonical.dart';
import '../core/constants.dart';
import '../data/sms_message.dart';
import '../data/sms_repository.dart';
import 'api_client.dart';

/// What a restore did, for UI feedback.
class RestoreResult {
  const RestoreResult({
    required this.restored,
    required this.alreadyPresent,
    this.error,
  });

  const RestoreResult.failed(String this.error)
    : restored = 0,
      alreadyPresent = 0;

  final int restored;
  final int alreadyPresent;
  final String? error;

  bool get isOk => error == null;
}

/// Rebuilds the local SMS log from the messages the backend already holds for
/// this device, e.g. after the app was uninstalled and reinstalled.
///
/// Restored rows are stored as already synced, so they are shown in the log
/// but never sent again.
class HistoryRestoreService {
  HistoryRestoreService({
    required this._api,
    required this._repo,
    required this._config,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final ApiClient _api;
  final SmsRepository _repo;
  final AppConfig _config;
  final DateTime Function() _now;

  static const _tag = 'HistoryRestore';

  /// Fetches up to [K.historyLimit] messages from the retention window and
  /// stores the ones not already in the log.
  Future<RestoreResult> restore() async {
    final fetch = await _api.fetchHistory(
      days: _config.retentionDays,
      limit: K.historyLimit,
    );
    if (!fetch.isOk) {
      AppLog.w(_tag, 'Restore failed: ${fetch.detail}');
      return RestoreResult.failed(fetch.detail);
    }

    var restored = 0;
    var present = 0;
    for (final row in fetch.messages) {
      final record = _toRecord(row);
      if (record == null) continue;
      if (await _alreadyLogged(record)) {
        present++;
        continue;
      }
      if (await _repo.insert(record) != null) {
        restored++;
      } else {
        present++;
      }
    }
    AppLog.i(
      _tag,
      'Restored $restored message(s); $present already in the log',
    );
    return RestoreResult(restored: restored, alreadyPresent: present);
  }

  /// The inbox backfill may already have re-captured the same SMS with a
  /// slightly different timestamp (so a different hash); match on content too
  /// so the log never shows it twice.
  Future<bool> _alreadyLogged(SmsRecord r) =>
      _repo.existsByContent(r.sender, r.message);

  /// Builds a synced record from a server row, or null if the row is
  /// malformed or its hash does not match its content.
  SmsRecord? _toRecord(Map<String, dynamic> row) {
    final sender = row['sender'];
    final message = row['message'];
    final receivedAt = row['received_at'];
    final hash = row['message_hash'];
    if (sender is! String ||
        message is! String ||
        receivedAt is! String ||
        hash is! String) {
      AppLog.w(_tag, 'Skipped a malformed history row');
      return null;
    }
    final expected = Canonical.messageHash(
      sender: sender,
      message: message,
      receivedAt: receivedAt,
    );
    if (expected != hash) {
      AppLog.w(_tag, 'Skipped a history row whose hash does not match');
      return null;
    }
    final at = _timestamp(row['created_at'], receivedAt);
    return SmsRecord(
      sender: sender,
      message: message,
      receivedAt: receivedAt,
      simSlot: (row['sim_slot'] as num?)?.toInt() ?? -1,
      subscriptionId: -1,
      deviceId: _config.deviceId,
      status: SmsStatus.synced,
      retryCount: 0,
      lastError: null,
      nextAttemptAt: 0,
      messageHash: hash,
      createdAt: at,
      // The server accepted it when it stored it; retention purges from here.
      syncedAt: at,
    );
  }

  /// When the server stored the message, falling back to when the phone
  /// received it, then to now.
  int _timestamp(Object? createdAt, String receivedAt) {
    final parsed =
        (createdAt is String ? DateTime.tryParse(createdAt) : null) ??
        DateTime.tryParse(receivedAt);
    return (parsed ?? _now()).millisecondsSinceEpoch;
  }
}
