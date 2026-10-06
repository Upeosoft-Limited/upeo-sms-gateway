# Upeo SMS Gateway — project notes

Flutter (Android-only) SMS-to-HTTPS gateway. See README for architecture.
The general rules in `~/projects/CLAUDE.md` apply; this file adds specifics.

## Toolchain (this machine)

- Flutter **3.44.2** (Dart 3.12.2), the version the project was created with,
  at `~/development/flutter`. Use it, not a newer SDK, so `pubspec.lock` holds.
- JDK 21 at `~/development/jdk21`, Android SDK at `~/Android/Sdk` (both set via
  `flutter config`). AGP 9 / Gradle 9.1 need JDK 17+.
- Checks: `flutter analyze`, `flutter test`. The repo predates `dart format`:
  most existing files are unformatted. Format new files; don't reformat old
  ones as a drive-by.

## Decisions

- **Admin password guards every config change** (not only the secret): a
  wrong URL, Device ID or allowlist stops sync just like a wrong secret.
  Logic: `lib/src/auth/config_change_policy.dart`; enforced in
  `ConfigForm._persist`, the only path that writes config. Any new
  config-writing path must go through the same policy.
- Password = PBKDF2-SHA256, 50k iterations. Pure Dart: 120k measured 0.64 s
  on a laptop (est. 2–3 s on a budget phone), 50k measured 0.27 s. The count
  is stored per hash, so it can be raised later.
- Configured installs without a password are routed to
  `CreatePasswordScreen` (upgrade path). Background isolates never read it.
- Forgotten password → clear app data. No backend recovery by design.
- **Log → Restore from server** (1.0.7) refills the log after a reinstall via
  signed `POST /api/sms/history`, served by the UpeoRetail core app
  (`upeoretail/api/sms_gateway.py`, `DeviceMessageHistory`). Restored rows are
  stored as `synced`, so they are never re-sent. The string-to-sign is
  `history\ndevice_id\nnonce\nsent_at\ndays\nlimit`; change both sides together.

## Test traps

- Widget tests: while the password dialog is open the form's busy bar animates
  forever, so `pumpAndSettle` times out. Pump fixed frames instead.
- PBKDF2 runs in `Isolate.run`, which widget tests' fake clock cannot drive;
  fake `AdminAuthRepository.verify` there, test the real one in unit tests.
- `FlutterSecureStorage.setMockInitialValues` backs storage in tests.

## Release signing

- Every release must be signed with `~/keys/upeo-sms-gateway-release.jks`
  (alias `upeo`, CN=Upeo Soft, cert SHA-256 `229235bd…6e325e`), created
  2026-09-30 for 1.0.6. Passwords live only in `android/key.properties`
  (gitignored). Android refuses an update signed with any other key.
- Without `key.properties` the build silently falls back to the debug key.
  Before shipping, check the signer:
  `apksigner verify --print-certs app-release.apk` (needs JDK 21 on PATH).
- Trap: the key that signed 1.0.0–1.0.5 was lost when the laptop was
  formatted, so 1.0.6 needed a one-time uninstall/reinstall on every phone.
  Keep off-machine backups of the keystore and its passwords.

## Deploy

Releases are shipped as an APK at a stable URL (first done for 1.0.7, 2026-10-06):

1. Check the signer (see Release signing) and `versionName` of the release APK.
2. On the droplet (`root@64.227.184.94`), in
   `/home/frappe/frappe-bench/sites/demo.upeoretail.com/public/files/`: copy
   the live `upeo-sms-gateway.apk` to `upeo-sms-gateway-<old>-backup.apk`,
   upload the new one as a dot-file, check its md5, `chown frappe:frappe`,
   then `mv` it over `upeo-sms-gateway.apk`. Rollback = move the backup back.
   The upload of ~70 MB takes 15+ minutes; run it in the background.
3. Bump `version` for UPEO SMS Gateway in `appDownloads` in the UpeoRetail
   website (`upeoretail/website/lib/site.ts`), push `main` (Vercel deploys).
4. Set `gateway_app_version` in demo's Upeo Retail Settings (the
   `/api/app/version` feed). Only demo has the feed set.
