import 'dart:convert';
import 'package:crypto/crypto.dart';

/// The signing / hashing spec. This MUST stay byte-for-byte identical to the
/// server implementation (see README "Signing & canonicalization").
class Canonical {
  Canonical._();

  /// `message_hash = SHA256( sender | message | received_at )` hex-encoded.
  ///
  /// `received_at` here is the PDU/SMSC timestamp string (EAT ISO-8601). Using
  /// the network timestamp (not arrival time) means a duplicate delivery or a
  /// double receiver-fire collapses, while two genuinely distinct messages do
  /// not.
  static String messageHash({
    required String sender,
    required String message,
    required String receivedAt,
  }) {
    final canonical = '$sender|$message|$receivedAt';
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// The exact string that gets HMAC-signed for an incoming-SMS payload.
  ///
  ///   device_id\nsender\nmessage\nreceived_at\nsim_slot\nmessage_hash\nnonce\nsent_at
  ///
  /// (Newline-joined, no trailing newline. The `signature` field is excluded.)
  static String incomingStringToSign({
    required String deviceId,
    required String sender,
    required String message,
    required String receivedAt,
    required int simSlot,
    required String messageHash,
    required String nonce,
    required String sentAt,
  }) {
    return [
      deviceId,
      sender,
      message,
      receivedAt,
      '$simSlot',
      messageHash,
      nonce,
      sentAt,
    ].join('\n');
  }

  /// The string signed for a heartbeat: `device_id\nnonce\nsent_at`.
  static String heartbeatStringToSign({
    required String deviceId,
    required String nonce,
    required String sentAt,
  }) {
    return [deviceId, nonce, sentAt].join('\n');
  }

  /// The string signed for a history request:
  /// `history\ndevice_id\nnonce\nsent_at\ndays\nlimit`. The leading `history`
  /// stops a heartbeat signature being replayed against this endpoint.
  static String historyStringToSign({
    required String deviceId,
    required String nonce,
    required String sentAt,
    required int days,
    required int limit,
  }) {
    return ['history', deviceId, nonce, sentAt, '$days', '$limit'].join('\n');
  }

  /// HMAC-SHA256 over [stringToSign] with [secret], lowercase hex.
  static String sign({required String stringToSign, required String secret}) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(stringToSign)).toString();
  }
}
