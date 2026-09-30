import 'package:flutter_test/flutter_test.dart';
import 'package:upeo_sms_gateway/src/config/app_config.dart';
import 'package:upeo_sms_gateway/src/core/canonical.dart';
import 'package:upeo_sms_gateway/src/data/sms_message.dart';
import 'package:upeo_sms_gateway/src/data/sms_repository.dart';
import 'package:upeo_sms_gateway/src/services/api_client.dart';
import 'package:upeo_sms_gateway/src/services/history_restore_service.dart';

const _config = AppConfig(
  apiBaseUrl: 'https://erp.example.com',
  deviceId: 'PHONE_001',
  secretKey: 'secret',
  allowlist: ['MPESA'],
  retentionDays: 14,
  allowInsecureHttp: false,
);

class _FakeApi implements ApiClient {
  _FakeApi(this.response);
  final HistoryFetch response;
  int? askedDays;
  int? askedLimit;

  @override
  Future<HistoryFetch> fetchHistory({
    required int days,
    required int limit,
  }) async {
    askedDays = days;
    askedLimit = limit;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stores rows in memory with the real table's unique-hash dedup.
class _FakeRepo implements SmsRepository {
  final rows = <SmsRecord>[];

  @override
  Future<int?> insert(SmsRecord r) async {
    if (rows.any((x) => x.messageHash == r.messageHash)) return null;
    rows.add(r);
    return rows.length;
  }

  @override
  Future<bool> existsByContent(String sender, String message) async =>
      rows.any((x) => x.sender == sender && x.message == message);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _row(String message, {String? hash}) {
  const receivedAt = '2026-09-29T10:00:00+03:00';
  return {
    'sender': 'MPESA',
    'message': message,
    'received_at': receivedAt,
    'sim_slot': 1,
    'message_hash':
        hash ??
        Canonical.messageHash(
          sender: 'MPESA',
          message: message,
          receivedAt: receivedAt,
        ),
    'created_at': '2026-09-29T10:00:05+03:00',
  };
}

HistoryRestoreService _service(_FakeApi api, _FakeRepo repo) =>
    HistoryRestoreService(api: api, repo: repo, config: _config);

void main() {
  test('history string-to-sign is bound to the endpoint, in order', () {
    expect(
      Canonical.historyStringToSign(
        deviceId: 'PHONE_001',
        nonce: 'n-1',
        sentAt: '2026-09-30T12:00:00+03:00',
        days: 14,
        limit: 500,
      ),
      'history\nPHONE_001\nn-1\n2026-09-30T12:00:00+03:00\n14\n500',
    );
  });

  test(
    'restored messages are logged as synced so they are never re-sent',
    () async {
      final api = _FakeApi(HistoryFetch.ok([_row('one'), _row('two')]));
      final repo = _FakeRepo();

      final result = await _service(api, repo).restore();

      expect(result.isOk, isTrue);
      expect(result.restored, 2);
      expect(repo.rows.map((r) => r.status), everyElement(SmsStatus.synced));
      final first = repo.rows.first;
      expect(first.deviceId, 'PHONE_001');
      expect(first.simSlot, 1);
      final storedAt = DateTime.parse(
        '2026-09-29T10:00:05+03:00',
      ).millisecondsSinceEpoch;
      expect(first.createdAt, storedAt);
      expect(first.syncedAt, storedAt);
    },
  );

  test('asks for the retention window, capped at the history limit', () async {
    final api = _FakeApi(const HistoryFetch.ok([]));
    await _service(api, _FakeRepo()).restore();
    expect(api.askedDays, 14);
    expect(api.askedLimit, 500);
  });

  test('messages already in the log are not added twice', () async {
    final repo = _FakeRepo();
    final api = _FakeApi(HistoryFetch.ok([_row('one')]));
    await _service(api, repo).restore();

    final again = await _service(api, repo).restore();

    expect(again.restored, 0);
    expect(again.alreadyPresent, 1);
    expect(repo.rows, hasLength(1));
  });

  test(
    'a message the inbox backfill re-captured is matched on content',
    () async {
      final repo = _FakeRepo();
      // Same SMS, captured locally with a different timestamp, so another hash.
      await repo.insert(
        SmsRecord(
          sender: 'MPESA',
          message: 'one',
          receivedAt: '2026-09-29T10:00:01+03:00',
          simSlot: 1,
          subscriptionId: 1,
          deviceId: 'PHONE_001',
          status: SmsStatus.pending,
          retryCount: 0,
          lastError: null,
          nextAttemptAt: 0,
          messageHash: 'local-hash',
          createdAt: 0,
          syncedAt: null,
        ),
      );

      final result = await _service(
        _FakeApi(HistoryFetch.ok([_row('one')])),
        repo,
      ).restore();

      expect(result.restored, 0);
      expect(repo.rows, hasLength(1));
    },
  );

  test('rows whose hash does not match their content are skipped', () async {
    final repo = _FakeRepo();
    final api = _FakeApi(HistoryFetch.ok([_row('one', hash: 'tampered')]));

    final result = await _service(api, repo).restore();

    expect(result.restored, 0);
    expect(repo.rows, isEmpty);
  });

  test('a server error is reported, not swallowed', () async {
    final api = _FakeApi(
      const HistoryFetch.failed(SendOutcome.permanent, 'HTTP 401: invalid'),
    );

    final result = await _service(api, _FakeRepo()).restore();

    expect(result.isOk, isFalse);
    expect(result.error, contains('401'));
  });
}
