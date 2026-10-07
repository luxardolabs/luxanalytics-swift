# LuxAnalytics

A **privacy-first**, **high-performance** analytics SDK for iOS 18+ built with Swift 6. Zero compilation warnings with full strict concurrency compliance.

## ✨ Key Features

- 🔒 **Privacy-First** - Automatic PII filtering, encrypted storage
- ⚡ **100% Async/Await** - Modern Swift concurrency throughout  
- 🎯 **Swift 6 Compliant** - Full actor isolation and data race safety
- 📦 **Smart Batching** - Automatic event batching with offline support
- 🔐 **Simple Setup** - Single DSN configuration string
- 🛡️ **Production Ready** - Circuit breaker, retry logic, comprehensive error handling

## 🚀 Quick Start

### Installation

```swift
dependencies: [
    .package(url: "https://github.com/luxardolabs/luxanalytics-swift", from: "1.1.0")
]
```

### Setup

```swift
import LuxAnalytics

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
```

### Track Events

```swift
let analytics = await LuxAnalytics.shared

// Track events
try await analytics.track("user_signup", metadata: [
    "method": "email",
    "source": "app"
])

// Set user context
await analytics.setUser("user-123")
await analytics.setSession("session-456")
```

Releases on this repository start at **1.1.0**. The product and module are still `LuxAnalytics`, so `import LuxAnalytics` is unchanged.

## 🖥️ Server

LuxAnalytics needs a backend to receive events. The server is a separate, self-hostable project: **[luxardolabs/luxanalytics](https://github.com/luxardolabs/luxanalytics)** (AGPL-3.0).

The wire format the SDK sends is specified once, in the server repository: **[Event format](https://github.com/luxardolabs/luxanalytics#event-formats)**.

## 📋 Requirements

- **iOS 18.0+** 
- **Swift 6.0+**
- **Xcode 16.0+**

## 📚 Documentation

| Topic | Description |
|-------|-------------|
| [📖 **Complete Guide**](docs/wiki/) | Comprehensive documentation and tutorials |
| [⚡ **Quick Start**](docs/wiki/Quick-Start.md) | Get running in under 5 minutes |
| [🔧 **Configuration**](docs/wiki/Configuration.md) | Detailed setup and customization options |
| [🔒 **Privacy & Security**](docs/wiki/Privacy-Security.md) | Privacy-first architecture and data protection |
| [🚀 **API Reference**](docs/wiki/API-Reference.md) | Complete API documentation |
| [🐛 **Troubleshooting**](docs/wiki/Troubleshooting.md) | Common issues and solutions |

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## 📞 Support

- 🐛 [GitHub Issues](https://github.com/luxardolabs/luxanalytics-swift/issues)
- 💬 [GitHub Discussions](https://github.com/luxardolabs/luxanalytics-swift/discussions)
- 📧 support@luxardolabs.com

## 📄 License

The SDK is released under the [MIT License](LICENSE). Copyright (c) 2025-2026 Luxardo Labs.

The [server](https://github.com/luxardolabs/luxanalytics) is a separate project under AGPL-3.0; the SDK you ship in your app is covered by the MIT License alone.
