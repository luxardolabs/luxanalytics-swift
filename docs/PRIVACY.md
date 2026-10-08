# Privacy

What the SDK collects, where it keeps it, and the tools it gives you to limit it. Each claim here is checked against the code; the ones about runtime behaviour were tested on the iOS 26.5 simulator.

## What is collected

Each event carries the event name, its metadata, a timestamp, an event id, the user and session ids if you set them, and this context, gathered once per launch:

| Key | Value |
|---|---|
| `device_model` | Hardware identifier, e.g. `iPhone17,1` |
| `device_type` | `iPhone` or `iPad` |
| `screen_resolution` | Screen size in points, e.g. `402x874` |
| `system_version` | iOS version |
| `app_version`, `build_number` | From your app's Info.plist |
| `locale`, `timezone` | The device's current locale and time zone identifiers |
| `device_id` | The SDK's device ID (below) |
| `is_testflight` | `true` when the app bundle contains `embedded.mobileprovision`, as development and ad hoc builds do; App Store builds don't. Despite the name, whether TestFlight builds include one hasn't been verified. |
| `platform` | `ios` |

Your own metadata is merged over this context, so a key you set replaces the SDK's value. The SDK sends nothing else: no IDFA, no location, no contacts.

## The device ID


Every event carries a `device_id` in its context. It is a SHA-256 hash, so the value it was made from is never sent:

- **First launch:** the ID is derived from `identifierForVendor`.
- **Storage:** it is kept in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). It is never backed up or synced to another device, and it stays readable while the device is locked after first unlock, so background flushes work.
- **Reinstall:** a Keychain item survives the app being deleted and reinstalled on the same device, so **a user who reinstalls keeps the same device ID**, even though `identifierForVendor` itself may change. Verified on the iOS 26.5 simulator: an ID set by `resetDeviceID()` came back after an uninstall and reinstall. That is deliberate (analytics continuity), but your privacy policy should say so.

To give a user a fresh identity, call:

```swift
func resetAnalyticsIdentity() async {
    await LuxAnalytics.resetDeviceID()
}
```

The new ID is random, not re-derived from `identifierForVendor`. Events already queued keep the old ID, and events tracked afterwards carry the new one. A natural place to call it is when a user withdraws analytics consent or asks you to reset their data:

```swift
func optOut() async {
    await AnalyticsSettings.shared.setEnabled(false)
    await LuxAnalytics.clearQueue()
    await LuxAnalytics.resetDeviceID()
}
```

## Personal data in event metadata

The SDK does **not** filter what you pass to `track`. Keep personal data out of event names and metadata, or redact it on the way in:

```swift
func trackSearch(query: String, email: String) async throws {
    let analytics = await LuxAnalytics.shared

    // Replace anything that looks like an email, phone number, card number,
    // US SSN or IP address in every key and value.
    try await analytics.trackSanitized("search", metadata: ["query": query])

    // Replace named fields with "[REDACTED]".
    try await analytics.trackWithRedaction(
        "contact_saved", metadata: ["email": email, "source": "form"], redactFields: ["email"])

    // Or use the filter directly.
    let cleaned = PIIFilter.sanitizeMetadata(["note": query])
    let hasPII = PIIFilter.containsPII(query)
    print(cleaned, hasPII)
}
```

The patterns are regular expressions for common formats. They will miss some personal data and flag some harmless strings, so treat them as a safety net, not a guarantee. `PIIFilter.commonPIIFields` lists field names that usually hold personal data, for use with `redactFields`.

## Storage on the device

- **The event queue** is saved to `UserDefaults`, encrypted with AES-GCM. The 256-bit key is generated on the device and kept in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). If the Keychain can't be used, the queue isn't saved and lives in memory only.
- **The opt-out setting** is saved in `UserDefaults`.
- **The device ID** is in the Keychain (above).
- `clearQueue()` deletes queued events; `resetDeviceID()` replaces the device ID.

## Logs

Logging is off unless you set `debugLogging: true` or call `LuxAnalytics.enableDiagnosticMode()`. Logs go to the unified log (subsystem `com.luxardolabs.LuxAnalytics`), and the SDK redacts email addresses, IP addresses, UUIDs, things that look like API keys or passwords, card numbers, phone numbers and US SSNs from its messages before logging them.

`LuxAnalyticsDebug.status()`, `validateSetup()` and `printSampleCode()` always log, at notice level, because you asked for them.

## Privacy manifest

The SDK bundles `PrivacyInfo.xcprivacy`, which Xcode merges into your app's privacy report:

| Data type | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|
| Device ID | No | No | Analytics |
| Product interaction | No | No | Analytics |
| Other usage data | No | No | Analytics |

`NSPrivacyTracking` is false, with no tracking domains. The required-reason API is `UserDefaults` (reason `CA92.1`), the only one the SDK uses.

This is how comparable anonymous analytics SDKs declare the same data: TelemetryDeck (product interaction and device ID), Aptabase and PostHog all ship **not linked, not tracking, analytics**. "Not linked" holds because the SDK sends no account data: the device ID is a one-way hash (of `identifierForVendor`, or of a random value after a reset), and nothing the SDK sends ties events to a name, email or account.

## Your App Store privacy answers

In App Store Connect, declare the SDK's data the same way its manifest does:

| Category → data type | Collected | Linked to the user | Used to track | Purpose |
|---|---|---|---|---|
| Identifiers → Device ID | Yes | No | No | Analytics |
| Usage Data → Product Interaction | Yes | No | No | Analytics |
| Usage Data → Other Usage Data | Yes | No | No | Analytics |

Then add what your app itself passes in:

- **`setUser`**: declare **Identifiers → User ID**, purpose Analytics. If the value is a random ID your app generates (a UUID kept on the device), it's **not linked**. If it's an account ID, email or anything else that identifies a person, it's **linked**, and so is the usage data sent with it, so change those rows to **Yes**.
- **Event metadata**: whatever personal data you put in it (see above), declared under its own data type.

The SDK sends data only to your own server and shares nothing with third parties, so it doesn't make your app "track" users in Apple's sense.

## Opting out

`AnalyticsSettings.shared.setEnabled(false)` stops all tracking and sending until it's turned back on, and is remembered across launches. See [Guide → Opting out](GUIDE.md#opting-out).

## TLS

Events are sent over HTTPS with the system's standard certificate validation (iOS requires TLS 1.2 or later). The SDK has no certificate pinning of its own.

## Pinning your own server

The SDK has no certificate pinning of its own: it uses the system's standard TLS validation. If you run your own server and want to pin it, use **App Transport Security's `NSPinnedDomains`** in your app's Info.plist (iOS 14+). It applies to all of your app's URL Loading System traffic, the SDK's included. That was verified on iOS 26.5: with a wrong pin, the SDK's requests fail with `NSURLErrorSecureConnectionFailed` (-1200).

`NSPinnedDomains` pins the certificate's **public key** (an SPKI SHA-256 hash), not the whole certificate, and it can pin your CA as well as your leaf. Compute a hash from your live server:

```bash
echo | openssl s_client -connect analytics.example.com:443 -servername analytics.example.com 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary | base64
```

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSPinnedDomains</key>
    <dict>
        <key>analytics.example.com</key>
        <dict>
            <key>NSPinnedLeafIdentities</key>
            <array>
                <dict>
                    <key>SPKI-SHA256-BASE64</key>
                    <string>CURRENT-KEY-HASH=</string>
                </dict>
                <dict>
                    <key>SPKI-SHA256-BASE64</key>
                    <string>BACKUP-KEY-HASH=</string>
                </dict>
            </array>
        </dict>
    </dict>
</dict>
```

> **Pins ship inside your app.** When the server's key stops matching every pin, installed copies of your app can't send analytics until users install an update, and nothing tells you. Before you pin:
>
> - **Pin a backup key** you have generated and stored offline, or pin your CA with `NSPinnedCAIdentities` instead of (or as well as) the leaf.
> - **Check your certificate tooling.** Certbot, for example, issues a new private key at every renewal by default (its `--reuse-key` option is off unless set), so a leaf pin with no backup breaks at the next renewal, which is every 90 days with Let's Encrypt.
>
> If you can't commit to managing keys like this, don't pin: standard TLS validation already rejects certificates that don't chain to a trusted CA.
