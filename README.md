# Upeo SMS Gateway — Offline-First Android SMS-to-HTTP Forwarding Gateway 📲

> Turn any spare Android phone into a **reliable, self-hosted SMS gateway**: it
> captures incoming SMS, stores them **encrypted on-device**, and forwards each one
> to your backend over **HTTPS with an HMAC-signed payload**. Built for
> **M-Pesa payment notifications**, OTP relay, and any *receive-SMS-to-API* pipeline.

![Platform](https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white)
![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white)
![Language](https://img.shields.io/badge/Dart%20%2B%20Kotlin-0175C2?logo=dart&logoColor=white)
![Security](https://img.shields.io/badge/security-HMAC--SHA256%20%2B%20SQLCipher-informational)
![Distribution](https://img.shields.io/badge/distribution-sideload%20APK-orange)
![Status](https://img.shields.io/badge/status-production-success)

**Keywords:** android sms gateway · sms to http · sms forwarding app · receive sms to
API · sms webhook · self-hosted sms gateway · M-Pesa SMS parser · HMAC-signed SMS ·
offline-first · SMS to ERPNext / Frappe · Kenya M-Pesa till notifications · OTP relay.

---

## What is the Upeo SMS Gateway?

**Upeo SMS Gateway is a free, open-source Android app that forwards incoming SMS
messages to any HTTP(S) backend in real time, securely and reliably — even on cheap
phones with aggressive battery managers.** It is a **dumb, message-type-agnostic
pipe**: it forwards the *raw* SMS and does **no** business parsing on the device. All
M-Pesa / OTP / business semantics live in your backend, so one app serves every use
case.

It was built to solve a very concrete problem in Kenya: **M-Pesa Till/Paybill payment
confirmations arrive by SMS**, and Safaricom's Daraja API is not available to every
merchant. A dedicated "till phone" running this gateway turns those SMS into
structured, reconcilable payments in your POS or ERP — with cryptographic integrity
and exactly-once delivery.

> **Part of the [UpeoRetail](https://upeoretail.com) retail platform**, but
> **backend-agnostic** — it works with FastAPI, ERPNext/Frappe, Laravel, Node, or any
> endpoint that can verify an HMAC. Runnable reference receivers are in
> [`backend_sample/`](backend_sample/).

---

## Table of contents

- [Why use an SMS gateway?](#why-use-an-sms-gateway)
- [Features](#features)
- [How it works (architecture)](#how-it-works-architecture)
- [The reliability design (the landmines)](#the-reliability-design-the-landmines)
- [Security & canonicalization (byte-exact)](#security--canonicalization-byte-exact)
- [Backend API contract](#backend-api-contract)
- [Quick start](#quick-start)
- [First-run setup on the phone](#first-run-setup-on-the-phone)
- [Backend integration](#backend-integration)
- [Permissions rationale](#permissions-rationale)
- [Privacy & Kenya Data Protection Act](#privacy--kenya-data-protection-act)
- [Why sideload only (not Google Play)](#why-sideload-only-not-google-play)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Tech stack](#tech-stack)
- [Contributing](#contributing)
- [License](#license)

---

## Why use an SMS gateway?

| Problem | Without a gateway | With Upeo SMS Gateway |
|---|---|---|
| M-Pesa Till/Paybill confirmations | Manual entry, cashier reads the SMS | Auto-parsed into payments in your POS/ERP |
| No Daraja / API access | Reconcile by hand at day-end | Real-time, cryptographically verified |
| OTP / alert relay to a server | Copy-paste, screenshots | Forwarded to your endpoint in seconds |
| Cheap phone kills background apps | Messages missed silently | Foreground service + WorkManager backstop |
| SMS security | Plaintext, spoofable | HMAC-SHA256 signed, replay-proof, encrypted at rest |

**Ideal for:** retail POS, ERPNext/Frappe merchants, fintech reconciliation, OTP
bridges, SMS-based IoT alerts, and anyone who needs *receive-SMS-to-webhook* on
Android without a paid SaaS.

---

## Features

- 📡 **Real-time SMS → HTTPS forwarding** — immediate send on receipt, not polling.
- 🔒 **HMAC-SHA256 signed payloads** — every request is authenticated per-device; the
  backend rejects anything it can't verify.
- 🗄️ **Encrypted-at-rest queue** — messages persist in a **SQLCipher** database, so
  nothing is lost across reboots, crashes, or offline periods.
- 🔁 **Exactly-once semantics** — dedup by `message_hash` + single-use `nonce`; a
  double-send returns *duplicate = success*.
- 🔋 **Survives Doze & OEM battery killers** — persistent foreground service +
  WorkManager backstop + boot receiver.
- 📶 **Offline-first** — queues when offline, drains automatically on reconnect with
  **exponential backoff + full jitter**.
- 🎛️ **Sender allowlist** — forward only the senders you care about (default `MPESA`).
- 📊 **Live dashboard** — pending/failed counts, last heartbeat, battery, connectivity,
  in-app logs, manual "Sync now" / "Test Connection" / retry.
- 🔄 **In-app updates** — the app checks a version feed and can self-update the APK.
- 🌍 **Backend-agnostic** — FastAPI + ERPNext/Frappe reference receivers included.
- 🧩 **Multi-SIM aware** — records the SIM slot each SMS arrived on.

---

## How it works (architecture)

```
        ┌─────────────────────────── Android phone ───────────────────────────┐
        │                                                                       │
  SMS ──►  SmsReceiver (manifest BroadcastReceiver)                             │
        │      │ parse + reassemble multipart                                   │
        │      ▼                                                                │
        │  SmsForegroundService (Kotlin, ongoing notification)                  │
        │      │ hosts a Flutter background isolate (entrypoint backgroundMain) │
        │      │ MethodChannel "upeo/sms_events" → onSmsReceived                │
        │      ▼                                                                │
        │  BackgroundRunner (Dart)                                              │
        │      │ allowlist filter → persist (SQLCipher) → immediate send        │
        │      │ periodic heartbeat + sweep timers + connectivity listener      │
        │      ▼                                                                │
        │  SyncService → ApiClient (Dio, HMAC) ─────────HTTPS───────────────────┼──► Backend
        │                                                                       │
        │  WorkManager periodic backstop (~15 min) ─ sweep + heartbeat          │
        │  BootReceiver ─ restart service on reboot / app update                │
        │  MainActivity ─ "upeo/native" control channel (UI)                    │
        └───────────────────────────────────────────────────────────────────────┘
```

**Two engines, one encrypted database:**

- **Foreground-service isolate** (`backgroundMain`) — the *primary* path. Always alive
  because the foreground service is always alive. Captures SMS, persists, syncs
  immediately, and runs the heartbeat + sweep timers.
- **UI isolate** (`main`) — the dashboard/settings. Opens its own connection to the
  same SQLCipher DB for display and manual actions.
- **WorkManager isolate** — the ~15-minute backstop sweep for anything the immediate
  path missed.

Concurrent sends from two isolates are safe: the backend dedups on
`message_hash`/`nonce`, so a double-send returns *duplicate = success*.

### Project layout

```
lib/
├── main.dart                       # UI + background isolate entrypoints
└── src/
    ├── config/                     # AppConfig + secure config repository
    ├── core/                       # canonicalization, constants, logging, time
    ├── data/                       # SQLCipher database, SMS model + repository
    ├── services/                   # api_client, sync, background_runner,
    │                               #   workmanager_backstop, native_bridge,
    │                               #   permissions, device_status
    ├── state/                      # Riverpod providers, controllers, actions
    └── ui/                         # screens (dashboard, setup, settings,
                                    #   reliability, logs, about) + widgets
android/app/src/main/               # Kotlin foreground service, SMS + boot receivers
backend_sample/                     # runnable FastAPI + ERPNext receivers + test client
test/                               # canonicalization parity tests
```

---

## The reliability design (the landmines)

Getting SMS delivery *reliable* on real-world Android is the hard part. The design
deliberately addresses each failure mode:

1. **Persistent foreground service is mandatory.** A manifest `BroadcastReceiver`
   alone is unreliable — OEM battery managers and Doze kill background processes, and
   after a force-stop the receiver won't fire until the app is reopened. The Kotlin
   foreground service keeps the process alive, owns the SMS receiver, and triggers
   immediate sync. WorkManager is only the periodic backstop.
2. **Encrypt-then-queue, never fire-and-forget.** Every SMS is written to the
   SQLCipher DB *before* any network attempt, so a crash or offline window never loses
   data.
3. **Idempotent delivery.** `message_hash` (content) and `nonce` (per-request) let the
   backend accept exactly once even when both isolates send the same row.
4. **Backoff with full jitter.** Failed sends retry at `15s · 2^n` (capped at 1h, max
   8 attempts) to avoid thundering-herd reconnects.
5. **Boot & update resilience.** A `BootReceiver` restarts the service on reboot and
   after an app update.
6. **Battery-optimization exemption + OEM autostart.** The Reliability screen walks the
   operator through the per-manufacturer settings that keep the pipe alive.

---

## Security & canonicalization (byte-exact)

Every request is signed with a **per-device shared secret** using **HMAC-SHA256**. The
strings that get signed are canonicalized **byte-for-byte** and must match on both
sides (`lib/src/core/canonical.dart` ↔ your backend). **Do not change one side without
the other.**

**Message hash** — integrity of the SMS itself (pipe-joined):

```
message_hash = SHA256( "{sender}|{message}|{received_at}" )
```

**Incoming string-to-sign** — newline-joined, in this exact field order:

```
device_id \n sender \n message \n received_at \n sim_slot \n message_hash \n nonce \n sent_at
```

**Heartbeat string-to-sign** — newline-joined:

```
device_id \n nonce \n sent_at
```

**History string-to-sign** — newline-joined; the literal `history` ties the
signature to that endpoint:

```
history \n device_id \n nonce \n sent_at \n days \n limit
```

**Signature** = `HMAC_SHA256(secret, string_to_sign)`, lowercase hex.

The secret is generated by the operator, entered once on the phone (stored in
`flutter_secure_storage` / Android Keystore) and registered on the backend. **It never
travels over the wire.**

---

## Backend API contract

The app calls **four fixed paths** — the operator configures only the base URL:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/sms/incoming` | One signed SMS. Verify → store → (parse). |
| `POST` | `/api/sms/heartbeat` | Signed heartbeat / "Test Connection" handshake. |
| `GET`  | `/api/app/version` | In-app update feed `{version, build, url, notes}`. |
| `POST` | `/api/sms/history` | Signed. This device's already-delivered messages, newest first, as `{status, messages: [{sender, message, received_at, sim_slot, message_hash, created_at}]}`. Powers **Log → Restore from server** after a reinstall; restored rows are stored as synced and never re-sent. |

**Incoming request body:**

```json
{
  "device_id": "PHONE_001",
  "sender": "MPESA",
  "message": "raw SMS body",
  "received_at": "2026-06-19T12:30:00+03:00",
  "sim_slot": 1,
  "message_hash": "…sha256 hex…",
  "nonce": "uuid-v4",
  "sent_at": "2026-06-19T12:30:01+03:00",
  "signature": "…hmac sha256 hex…"
}
```

**The backend must:**

1. Reject **unknown device** → `401`.
2. Recompute and reject **`message_hash` mismatch** → `400`.
3. Reject **invalid signature** → `401`.
4. Reject **stale `sent_at`** (> 5 min skew) → `400`.
5. Reject **reused `nonce`** → `409` (replay).
6. Return **`{"status":"duplicate"}`** (`200`) if `message_hash` already stored.
7. Else store and return **`{"status":"accepted"}`** (`200`).

The client marks a message *synced* only on a `2xx` accept or a documented
`duplicate`. Everything else stays queued with exponential backoff + full jitter.

> **Runnable receivers:** see [`backend_sample/`](backend_sample/) for FastAPI +
> ERPNext/Frappe implementations and a signing test client.

---

## Quick start

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **3.12+**
- Android SDK / Android Studio
- A dedicated Android phone (**Android 7.0 / API 24+**) with a SIM

### Build & sideload the APK

```bash
git clone git@github.com:Upeosoft-Limited/upeo-sms-gateway.git
cd upeo-sms-gateway

flutter pub get

# Debug run on a connected phone:
flutter run

# Signed release APK:
#   1) create a keystore (once) and android/key.properties  (see below)
#   2) build:
flutter build apk --release
# output → build/app/outputs/flutter-apk/app-release.apk

adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Release signing** (never commit these — they're gitignored):

```bash
keytool -genkey -v -keystore android/app/upeo-sms-gateway.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upeo
```

Create `android/key.properties`:

```properties
storePassword=********
keyPassword=********
keyAlias=upeo
storeFile=upeo-sms-gateway.jks
```

> ⚠️ **Back up the keystore.** Losing it means you can never ship a signed update that
> installs over the existing app.

---

## First-run setup on the phone

1. **Grant permissions** — SMS, phone state, notifications.
2. **Backend config** — API base URL (HTTPS), Device ID, secret key (masked), sender
   allowlist (default `MPESA`), retention days.
3. **Test Connection** — sends a signed heartbeat handshake; a green result proves URL
   + Device ID + secret + signing all line up.
4. **Save** — the foreground service starts automatically.
5. **Create the admin password** — asked for once, right after the first save
   (and on first launch after upgrading an already-configured phone).
6. **Reliability screen** — exempt from battery optimization + open the OEM
   autostart / protected-apps screen (per-manufacturer guidance is shown). **This step
   is what keeps the gateway alive long-term** — don't skip it.

### Admin password

Once the gateway is configured, **any change to its settings needs the admin
password**: the device secret, Device ID, API URL, allowlist, retention, and the
HTTP switch. Any of those, changed by mistake, stops sync. Re-saving unchanged
values (e.g. Test Connection) does not ask. Change the password under
**Settings → Change admin password** (the current one is required).

It is stored only as a salted PBKDF2-SHA256 hash in the Keystore-backed secure
storage. Five wrong attempts lock it for 5 minutes, surviving app restarts. It is
local to the phone; the backend never sees it, and background sync never needs it.

**Forgotten password:** clear the app's data (Android Settings → Apps → UPEO SMS
Gateway → Storage → Clear data) and set the gateway up again. This also clears
the on-device queue, so let pending messages sync first.

---

## Backend integration

1. Register the device on your backend (Device ID + the same shared secret).
2. Verify the HMAC per the [canonicalization rules](#security--canonicalization-byte-exact).
3. Store the raw SMS; parse downstream (e.g. extract M-Pesa code/amount/phone) into
   your own payment records.

Using **ERPNext / Frappe**? A complete porting guide that recreates the three
doctypes, the receiver, the routing rewrite, the settings, and the scheduled jobs
lives in the UpeoRetail app repo. The [`backend_sample/erpnext/`](backend_sample/erpnext/)
folder here is a self-contained starting point.

---

## Permissions rationale

| Permission | Why it's needed |
|---|---|
| `RECEIVE_SMS`, `READ_SMS` | Capture incoming SMS (the core function). |
| `INTERNET`, `ACCESS_NETWORK_STATE` | Forward messages and detect connectivity. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Keep the capture/sync process alive. |
| `RECEIVE_BOOT_COMPLETED` | Restart the service after reboot. |
| `READ_PHONE_STATE` | Identify the SIM slot a message arrived on. |
| `POST_NOTIFICATIONS` | Show the required ongoing service notification. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prompt for the battery exemption that ensures reliability. |
| `ACCESS_FINE_LOCATION` | Some OEMs gate multi-SIM info behind location; used only for SIM identification. |
| `REQUEST_INSTALL_PACKAGES` | In-app APK self-update. |

---

## Privacy & Kenya Data Protection Act

- Messages are **stored encrypted (SQLCipher)** on-device and pruned per your retention
  setting.
- Only **allowlisted senders** are forwarded — everything else is ignored on-device.
- Traffic is **HTTPS + HMAC-signed**; secrets live in Android Keystore, never in
  transit.
- Deploy on a **dedicated device you control**, disclose processing to data subjects,
  and register with the ODPC where applicable. You are the data controller for the SMS
  you forward.

---

## Why sideload only (not Google Play)

Google Play forbids `READ_SMS` / `RECEIVE_SMS` for apps that are **not** the default
SMS handler, and grants no exception when an official API exists (M-Pesa has Daraja).
This app is intended for **private/internal APK distribution** on devices you own.
That's a policy constraint, not a technical one — the app is fully production-grade.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| All requests **404** | Backend routing not wired to the three fixed paths. |
| **401 unknown device** | Device ID mismatch, device disabled, or no secret set. |
| **401 invalid signature** | Secret differs between phone and backend, or canonicalization altered on one side. |
| **400 stale sent_at** | Phone clock drift — fix NTP or widen the skew window. |
| **400 message_hash mismatch** | `sender`/`message`/`received_at` mutated in transit. |
| SMS captured but **not sent** | Offline (queued — will drain), or battery optimization killed the service → do the Reliability steps. |
| Service dies overnight | OEM autostart not enabled / battery not exempted (Xiaomi, Oppo, Vivo, Samsung are common offenders). |
| Duplicate payments | Backend not deduping on `message_hash`/`nonce`. |
| Forgot the admin password | Clear the app's data and set up again (see [Admin password](#admin-password)). |

---

## FAQ

**What does the Upeo SMS Gateway do?**
It captures incoming SMS on a dedicated Android phone and forwards each message to your
HTTP(S) backend as an HMAC-signed JSON payload, with an encrypted on-device queue for
reliability.

**Is it a paid SaaS?**
No. It's a self-hosted, open-source Android app — you run it on your own phone and
point it at your own server. No per-message fees.

**Can it parse M-Pesa SMS?**
The app forwards raw SMS; **M-Pesa parsing happens on your backend**. Reference parsers
(extracting transaction code, amount, phone, name, time) are included in the backend
samples and the UpeoRetail ERPNext integration.

**Which backends are supported?**
Any backend that can verify an HMAC over the documented canonical strings. Runnable
FastAPI and ERPNext/Frappe receivers ship in [`backend_sample/`](backend_sample/).

**Will it keep running when the screen is off?**
Yes — a persistent foreground service plus a WorkManager backstop and boot receiver
keep it alive, provided you complete the battery-optimization + OEM autostart steps.

**Does it work offline?**
Yes. Messages are stored encrypted and queued; they sync automatically when
connectivity returns, with exponential backoff.

**Is it secure?**
Every request is HMAC-SHA256 signed with a per-device secret, protected against replay
(single-use nonce) and tampering (message hash), and stored encrypted at rest
(SQLCipher).

**Which Android versions are supported?**
Android **7.0 (API 24)** and above.

**Can I use it for OTP forwarding or alerts, not just M-Pesa?**
Yes — it's message-type-agnostic. Allowlist the sender and parse on your backend.

---

## Tech stack

**Flutter (Dart)** UI + background isolates · **Kotlin** foreground service & receivers
· **Dio** HTTP · **SQLCipher** (`sqflite_sqlcipher`) encrypted storage ·
**flutter_secure_storage** (Android Keystore) · **WorkManager** backstop ·
**Riverpod** state · **crypto** HMAC · **connectivity_plus** / **battery_plus** /
**device_info_plus** telemetry.

---

## Contributing

Issues and pull requests are welcome. Please keep the **canonicalization contract**
(`lib/src/core/canonical.dart` and the backend) byte-identical — parity tests in
[`test/`](test/) guard it. If you find this project useful, **please ⭐ star the repo**
to help others discover it.

## License

Copyright © Upeo Soft Limited. See [`LICENSE`](LICENSE) if present, or contact
[Upeosoft-Limited](https://github.com/Upeosoft-Limited) for licensing terms.

---

<sub>**Topics:** android-sms-gateway · sms-to-http · sms-forwarding · sms-webhook ·
mpesa · m-pesa · flutter · dart · kotlin · offline-first · hmac · sqlcipher · erpnext ·
frappe · pos · fintech · kenya · otp · receive-sms · self-hosted. Built by
[Upeosoft Limited](https://upeosoft.com) for the [UpeoRetail](https://upeoretail.com) platform.</sub>
