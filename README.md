# LuxAnalytics

A privacy-conscious analytics SDK for iOS 18+, written in Swift 6 with strict concurrency. It queues events on the device, sends them in batches to a self-hosted [LuxAnalytics server](https://github.com/luxardolabs/luxanalytics), and keeps working offline.

- **Batched and offline-first**: events are queued, encrypted at rest (AES-GCM, key in the Keychain), and sent in batches when the network is available
- **Reliable delivery**: retries with exponential backoff, honours the server's `Retry-After`, and a circuit breaker stops hammering a server that's down
- **Idempotent**: every event carries an id, so a retried batch isn't stored twice
- **Compact**: batches over 1 KB are zlib-compressed
- **Privacy tools**: opt-in PII redaction for event metadata, redacted debug logs, a resettable device ID, and a bundled privacy manifest
- **One-line setup** from a DSN string

## Installation

Add the package in Xcode (**File → Add Package Dependencies…**, URL `https://github.com/luxardolabs/luxanalytics-swift`), or in `Package.swift`:

```swift ignore
dependencies: [
    .package(url: "https://github.com/luxardolabs/luxanalytics-swift", from: "1.1.0")
]
```

Releases on this repository start at **1.1.0**. The product and module are named `LuxAnalytics`.

## Quick start

Initialize once at launch with your project's DSN, then track events from anywhere:

```swift
@main
struct MyApp: App {
    init() {
        Task {
            try await LuxAnalytics.quickStart(
                dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id"
            )
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    var body: some View {
        Button("Sign up") {
            Task {
                try await LuxAnalytics.shared.track("signup_tapped", metadata: ["source": "home"])
            }
        }
    }
}
```

Metadata is `[String: String]`: convert numbers and booleans to strings. See the [Guide](docs/GUIDE.md) for users and sessions, when events are sent, and opting out.

## Documentation

| | |
|---|---|
| [Guide](docs/GUIDE.md) | Setup, tracking, users and sessions, delivery, opt-out, observing events |
| [Configuration](docs/CONFIGURATION.md) | The DSN, every option and its default, Info.plist keys |
| [Privacy](docs/PRIVACY.md) | What's collected, the device ID, PII redaction, encryption, the privacy manifest, pinning your server |
| [Reference](docs/REFERENCE.md) | The public API |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Events not arriving, crashes at startup, background flushing |
| [Maintaining](docs/MAINTAINING.md) | Building, testing and releasing the SDK |

Every Swift example in these docs is compiled against the SDK by `make docs-check`.

## Server

LuxAnalytics needs a backend to receive events: **[luxardolabs/luxanalytics](https://github.com/luxardolabs/luxanalytics)** (AGPL-3.0), which you host yourself. The wire format, responses, and the event names and keys the dashboard reads are specified once, in the server repository: **[Event format](https://github.com/luxardolabs/luxanalytics/blob/main/docs/event-format.md)**.

## Requirements

- iOS 18.0+
- Swift 6 (swift-tools-version 6.0), Xcode 16+

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report bugs on [GitHub Issues](https://github.com/luxardolabs/luxanalytics-swift/issues).

## License

The SDK is released under the [MIT License](LICENSE). Copyright (c) 2025-2026 Luxardo Labs.

The [server](https://github.com/luxardolabs/luxanalytics) is a separate project under AGPL-3.0; the SDK you ship in your app is covered by the MIT License alone.
