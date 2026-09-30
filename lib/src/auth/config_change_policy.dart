import '../config/app_config.dart';

/// Decides when saving the gateway configuration needs the admin password.
///
/// Every field is guarded, not just the secret: a wrong URL, Device ID or
/// allowlist stops forwarding just as surely as a wrong secret.
class ConfigChangePolicy {
  const ConfigChangePolicy();

  /// First-run setup (nothing saved yet) is free; after that, any change to a
  /// saved configuration needs the password. Re-saving identical values
  /// (e.g. Test Connection) does not.
  bool requiresPassword({required AppConfig saved, required AppConfig edited}) {
    if (!saved.isComplete) return false;
    return !_sameConfig(saved, edited);
  }

  bool _sameConfig(AppConfig a, AppConfig b) =>
      a.apiBaseUrl.trim() == b.apiBaseUrl.trim() &&
      a.deviceId.trim() == b.deviceId.trim() &&
      a.secretKey == b.secretKey &&
      _sameList(a.allowlist, b.allowlist) &&
      a.retentionDays == b.retentionDays &&
      a.allowInsecureHttp == b.allowInsecureHttp;

  bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
