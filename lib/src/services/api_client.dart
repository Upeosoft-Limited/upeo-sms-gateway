import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../core/app_log.dart';
import '../core/canonical.dart';
import '../core/constants.dart';
import '../core/time_utils.dart';
import '../data/sms_message.dart';

/// Outcome of a single send attempt.
enum SendOutcome {
  /// 2xx accepted, or server reported it as a duplicate — treat as done.
  success,

  /// Transient (network/5xx/timeout) — keep in queue, back off, retry.
  transient,

  /// Permanent (4xx other than duplicate, e.g. bad signature/config) — keep but
  /// the operator must fix configuration.
  permanent,
}

class SendResult {
  final SendOutcome outcome;
  final String detail;
  const SendResult(this.outcome, this.detail);
}

/// Outcome of a history request: the raw server rows, or why there are none.
class HistoryFetch {
  const HistoryFetch.ok(this.messages)
      : outcome = SendOutcome.success,
        detail = 'ok';
  const HistoryFetch.failed(this.outcome, this.detail) : messages = const [];

  final SendOutcome outcome;
  final String detail;
  final List<Map<String, dynamic>> messages;

  bool get isOk => outcome == SendOutcome.success;
}

/// Signs payloads and talks to the backend over HTTPS. The [AppConfig.secretKey]
/// is used only to compute the HMAC; it is never sent or logged.
class ApiClient {
  ApiClient(this._cfg) : _dio = _build(_cfg);

  final AppConfig _cfg;
  final Dio _dio;
  static const _uuid = Uuid();
  static const _tag = 'ApiClient';

  static Dio _build(AppConfig cfg) {
    final dio = Dio(BaseOptions(
      baseUrl: cfg.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      // We treat any status < 500 as a non-throwing response so we can inspect it.
      validateStatus: (s) => s != null && s < 600,
      headers: {'Content-Type': 'application/json'},
    ));
    return dio;
  }

  void _assertSecureUrl() {
    if (!_cfg.isHttps && !_cfg.allowInsecureHttp) {
      throw StateError(
        'Refusing to send over plain HTTP. Use an https:// URL, or enable the '
        'explicit debug "allow insecure HTTP" flag.',
      );
    }
  }

  /// Build the full, signed incoming-SMS payload for [r].
  Map<String, dynamic> buildIncomingPayload(SmsRecord r) {
    final nonce = _uuid.v4();
    final sentAt = TimeUtils.nowEat();
    final stringToSign = Canonical.incomingStringToSign(
      deviceId: r.deviceId,
      sender: r.sender,
      message: r.message,
      receivedAt: r.receivedAt,
      simSlot: r.simSlot,
      messageHash: r.messageHash,
      nonce: nonce,
      sentAt: sentAt,
    );
    final signature = Canonical.sign(stringToSign: stringToSign, secret: _cfg.secretKey);
    return {
      'device_id': r.deviceId,
      'sender': r.sender,
      'message': r.message,
      'received_at': r.receivedAt,
      'sim_slot': r.simSlot,
      'message_hash': r.messageHash,
      'nonce': nonce,
      'sent_at': sentAt,
      'signature': signature,
    };
  }

  Future<SendResult> sendIncoming(SmsRecord r) async {
    _assertSecureUrl();
    final payload = buildIncomingPayload(r);
    try {
      final res = await _dio.post(K.incomingPath, data: payload);
      final code = res.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        final dup = _looksDuplicate(res.data);
        return SendResult(SendOutcome.success, dup ? 'duplicate' : 'accepted');
      }
      if (code == 409) {
        // Conventional duplicate response.
        return const SendResult(SendOutcome.success, 'duplicate');
      }
      if (code >= 400 && code < 500) {
        return SendResult(SendOutcome.permanent, 'HTTP $code: ${_msg(res.data)}');
      }
      return SendResult(SendOutcome.transient, 'HTTP $code');
    } on DioException catch (e) {
      return SendResult(SendOutcome.transient, _dioMsg(e));
    } catch (e) {
      return SendResult(SendOutcome.transient, e.toString());
    }
  }

  /// Signed heartbeat. Doubles as the "Test Connection" handshake.
  Future<SendResult> sendHeartbeat(Map<String, dynamic> health) async {
    _assertSecureUrl();
    final nonce = _uuid.v4();
    final sentAt = TimeUtils.nowEat();
    final stringToSign = Canonical.heartbeatStringToSign(
      deviceId: _cfg.deviceId,
      nonce: nonce,
      sentAt: sentAt,
    );
    final signature = Canonical.sign(stringToSign: stringToSign, secret: _cfg.secretKey);
    final payload = {
      'device_id': _cfg.deviceId,
      'nonce': nonce,
      'sent_at': sentAt,
      'signature': signature,
      ...health,
    };
    try {
      final res = await _dio.post(K.heartbeatPath, data: payload);
      final code = res.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        return const SendResult(SendOutcome.success, 'ok');
      }
      if (code >= 400 && code < 500) {
        return SendResult(SendOutcome.permanent, 'HTTP $code: ${_msg(res.data)}');
      }
      return SendResult(SendOutcome.transient, 'HTTP $code');
    } on DioException catch (e) {
      return SendResult(SendOutcome.transient, _dioMsg(e));
    } catch (e) {
      return SendResult(SendOutcome.transient, e.toString());
    }
  }

  /// Signed request for the messages this device already delivered, newest
  /// first, so a reinstalled app can rebuild its log.
  Future<HistoryFetch> fetchHistory({required int days, required int limit}) async {
    _assertSecureUrl();
    final nonce = _uuid.v4();
    final sentAt = TimeUtils.nowEat();
    final signature = Canonical.sign(
      stringToSign: Canonical.historyStringToSign(
        deviceId: _cfg.deviceId,
        nonce: nonce,
        sentAt: sentAt,
        days: days,
        limit: limit,
      ),
      secret: _cfg.secretKey,
    );
    try {
      final res = await _dio.post(K.historyPath, data: {
        'device_id': _cfg.deviceId,
        'nonce': nonce,
        'sent_at': sentAt,
        'days': days,
        'limit': limit,
        'signature': signature,
      });
      final code = res.statusCode ?? 0;
      final data = res.data;
      if (code >= 200 && code < 300 && data is Map && data['messages'] is List) {
        final messages = (data['messages'] as List)
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
        return HistoryFetch.ok(messages);
      }
      if (code >= 400 && code < 500) {
        return HistoryFetch.failed(SendOutcome.permanent, 'HTTP $code: ${_msg(data)}');
      }
      return HistoryFetch.failed(SendOutcome.transient, 'HTTP $code');
    } on DioException catch (e) {
      return HistoryFetch.failed(SendOutcome.transient, _dioMsg(e));
    }
  }

  /// In-app update check: returns the latest {version, build, url, notes} or null.
  Future<Map<String, dynamic>?> checkLatestVersion() async {
    try {
      final res = await _dio.get(K.versionPath);
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300 && res.data is Map) {
        return (res.data as Map).map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      AppLog.w(_tag, 'version check failed: $e');
    }
    return null;
  }

  bool _looksDuplicate(dynamic data) {
    if (data is Map) {
      final s = (data['status'] ?? data['result'] ?? '').toString().toLowerCase();
      return s.contains('duplicate');
    }
    return false;
  }

  String _msg(dynamic data) {
    if (data is Map) return (data['detail'] ?? data['message'] ?? data).toString();
    return data?.toString() ?? '';
  }

  String _dioMsg(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'timeout';
      case DioExceptionType.connectionError:
        return 'connection error';
      default:
        return e.message ?? e.type.name;
    }
  }
}
