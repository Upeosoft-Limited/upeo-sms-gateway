/// App-wide constants. No secrets here — those live in secure storage.
class K {
  K._();

  static const String appName = 'UPEO SMS Gateway';

  // ----- MethodChannels (must match the Kotlin side) -----
  static const String nativeChannel = 'upeo/native';
  static const String smsEventsChannel = 'upeo/sms_events';

  // ----- Backend endpoints (relative to the configured base URL) -----
  static const String incomingPath = '/api/sms/incoming';
  static const String heartbeatPath = '/api/sms/heartbeat';
  static const String versionPath = '/api/app/version';
  static const String historyPath = '/api/sms/history';

  // Most messages one "Restore from server" asks for (the server caps it too).
  static const int historyLimit = 500;

  // ----- Defaults -----
  static const List<String> defaultAllowlist = ['MPESA'];
  static const int defaultRetentionDays = 14;

  // ----- Sync / retry policy -----
  static const int maxRetries = 8;
  static const Duration baseBackoff = Duration(seconds: 15);
  static const Duration maxBackoff = Duration(hours: 1);
  static const int syncBatchSize = 25;

  // ----- Background timers (foreground-service isolate) -----
  static const Duration heartbeatInterval = Duration(minutes: 5);
  // Sweep often so any SMS that failed to send during a brief server blip
  // (e.g. a backend deploy/restart) is retried within seconds. The per-message
  // exponential backoff still prevents hammering a server that is actually down.
  static const Duration sweepInterval = Duration(seconds: 15);

  // ----- Replay window the server should also enforce -----
  static const Duration sentAtSkew = Duration(minutes: 5);

  // ----- Device-inbox backfill (recover SMS the live receiver never saw, e.g.
  //       a message that arrived while the DB was briefly closed or the service
  //       was dead). Scans content://sms/inbox and ingests anything missing. -----
  static const Duration inboxScanInterval = Duration(seconds: 60);
  // Furthest back a scan ever looks. Bounded well under the retention window so a
  // synced-then-purged message can never be resurrected and re-sent.
  static const Duration inboxInitialLookback = Duration(days: 2);
  // Re-scan a little before the high-water mark to tolerate clock skew between
  // the PDU timestamp and the inbox `date`; content dedup makes overlap safe.
  static const Duration inboxScanOverlap = Duration(minutes: 10);
  static const int inboxScanLimit = 200;

  // ----- WorkManager backstop -----
  static const String backstopTaskName = 'upeo_backstop_sweep';
  static const String backstopUniqueName = 'upeo_backstop_periodic';

  // ----- Watchdog: service considered "stale" if no tick within this window -----
  static const Duration watchdogStaleAfter = Duration(minutes: 3);
}
