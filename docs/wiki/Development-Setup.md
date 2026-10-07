# Development Setup Guide

Complete guide to setting up LuxAnalytics for development, contributing, and testing.

## Prerequisites

### Required Tools

- **macOS 14.0+** (Sonoma or later)
- **Xcode 16.0+** with iOS 18.0+ SDK
- **Swift 6.0+** with strict concurrency enabled
- **Git** for version control

### Optional Tools

- **SwiftFormat** for code formatting
- **SwiftLint** for code quality
- **Instruments** for performance profiling
- **Charles Proxy** or **Proxyman** for network debugging

## Initial Setup

### 1. Fork and Clone

```bash
# Fork the repository on GitHub first, then clone your fork
git clone https://github.com/YOUR_USERNAME/LuxAnalytics.git
cd LuxAnalytics

# Add upstream remote
git remote add upstream https://github.com/luxardolabs/LuxAnalytics.git

# Verify remotes
git remote -v
```

### 2. Project Structure

```
LuxAnalytics/
├── Sources/
│   └── LuxAnalytics/           # Main SDK source code
│       ├── LuxAnalytics.swift  # Main SDK interface
│       ├── Configuration/      # Configuration classes
│       ├── Queue/              # Event queue management
│       ├── Network/            # Network layer
│       ├── Security/           # Security and encryption
│       └── Utilities/          # Helper utilities
├── Tests/
│   └── LuxAnalyticsTests/      # Unit and integration tests
├── docs/                       # Documentation
│   ├── wiki/                   # Technical documentation
│   ├── CHANGELOG.md           # Version history
│   └── CONTRIBUTING.md        # Contribution guidelines
├── Package.swift              # Swift Package Manager manifest
├── LICENSE                    # MIT License
└── README.md                  # Project overview
```

### 3. Open in Xcode

```bash
# Open the package in Xcode
open Package.swift

# Or use Xcode command line tools
xed .
```

### 4. Verify Setup

```bash
# Build the project
swift build

# Run tests
swift test

# Build for iOS Simulator
xcodebuild -scheme LuxAnalytics \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

## Development Environment

### Swift 6 Configuration

Ensure your project is configured for Swift 6:

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LuxAnalytics",
    platforms: [
        .iOS(.v18)
    ],
    // ... rest of configuration
)
```

### Xcode Settings

**Build Settings to verify:**

| Setting | Value | Purpose |
|---------|-------|---------|
| Swift Language Version | Swift 6 | Enable strict concurrency |
| Swift Strict Concurrency | Complete | Data race safety |
| iOS Deployment Target | 18.0 | Required minimum |
| Enable Testability | Yes (Debug) | Unit testing support |
| Code Coverage | Yes | Test coverage metrics |

### Environment Variables

Create a `.env` file for development (not committed):

```bash
# .env (for local development)
LUX_ANALYTICS_TEST_DSN=https://test-key@localhost:8000/api/v1/events/test-project
LUX_ANALYTICS_DEBUG=true
LUX_ANALYTICS_LOG_LEVEL=debug
```

## Code Style and Standards

### SwiftFormat Configuration

Create `.swiftformat` file:

```
# .swiftformat
--swiftversion 6.0
--indent 4
--importgrouping testable-bottom
--header strip
--disable redundantSelf
--disable strongOutlets
--disable trailingCommas
--maxwidth 120
--wraparguments before-first
--wrapcollections before-first
--closingparen same-line
--funcattributes prev-line
--typeattributes prev-line
--varattributes prev-line
```

### SwiftLint Configuration

Create `.swiftlint.yml` file:

```yaml
# .swiftlint.yml
included:
  - Sources
  - Tests

excluded:
  - docs
  - .build

disabled_rules:
  - todo
  - line_length

opt_in_rules:
  - force_unwrapping
  - implicitly_unwrapped_optional
  - strong_iboutlet

force_unwrapping:
  severity: error

line_length:
  warning: 120
  error: 150

identifier_name:
  min_length: 1
  max_length: 50

type_name:
  min_length: 3
  max_length: 50

custom_rules:
  no_print:
    name: "No Print Statements"
    regex: 'print\('
    message: "Use SecureLogger instead of print()"
    severity: error
```

### Code Standards

**Swift 6 Concurrency:**
- Use `async/await` for all asynchronous operations
- Mark shared mutable state with `actor`
- Use `@Sendable` for types crossing actor boundaries
- Avoid `@unchecked Sendable` unless absolutely necessary

**Naming Conventions:**
- Use descriptive names for functions and variables
- Prefix internal types with `Lux` to avoid conflicts
- Use `Protocol` suffix for protocols
- Use `Error` suffix for error types

**Documentation:**
- Document all public APIs with DocC comments
- Include code examples in documentation
- Explain complex algorithms and design decisions

## Testing Setup

### Test Structure

```
Tests/
└── LuxAnalyticsTests/
    ├── ConfigurationTests.swift    # Configuration testing
    ├── QueueTests.swift            # Queue management tests
    ├── NetworkTests.swift          # Network layer tests
    ├── SecurityTests.swift         # Security and encryption tests
    ├── IntegrationTests.swift      # End-to-end tests
    ├── PerformanceTests.swift      # Performance benchmarks
    └── TestHelpers.swift           # Test utilities
```

### Test Configuration

```swift
// TestHelpers.swift
import Foundation
@testable import LuxAnalytics

class TestHelper {
    static func createTestConfiguration() throws -> LuxAnalyticsConfiguration {
        return try LuxAnalyticsConfiguration(
            dsn: "https://test@localhost:8000/api/v1/events/test",
            debugLogging: true,
            requestTimeout: 5.0 // Shorter timeout for tests
        )
    }
    
    static func resetLuxAnalytics() async {
        // Reset global state between tests
        await LuxAnalyticsStorage.shared.setInstance(nil)
        await LuxAnalyticsStorage.shared.setConfiguration(nil)
        await LuxAnalyticsQueue.shared.clear()
        await GlobalCircuitBreaker.shared.clear()
    }
}

// Base test class
class LuxAnalyticsTestCase: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        await TestHelper.resetLuxAnalytics()
    }
    
    override func tearDown() async throws {
        await TestHelper.resetLuxAnalytics()
        try await super.tearDown()
    }
}
```

### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter LuxAnalyticsConfigurationTests

# Run tests with coverage
swift test --enable-code-coverage

# Generate coverage report
xcrun llvm-cov show \
  .build/debug/LuxAnalyticsPackageTests.xctest/Contents/MacOS/LuxAnalyticsPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  Sources/ -format html -output-dir coverage-report

# Run performance tests
swift test --filter PerformanceTests
```

### Mock Server for Testing

```swift
// MockAnalyticsServer.swift
import Foundation
import Network

@available(iOS 13.0, *)
class MockAnalyticsServer {
    private var listener: NWListener?
    private let port: UInt16
    
    var receivedEvents: [(endpoint: String, events: [[String: Any]])] = []
    
    init(port: UInt16 = 8000) {
        self.port = port
    }
    
    func start() throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(port)!)
        
        listener?.newConnectionHandler = { connection in
            self.handleConnection(connection)
        }
        
        listener?.start(queue: .global())
    }
    
    func stop() {
        listener?.cancel()
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self.processRequest(data, connection: connection)
            }
            
            if isComplete {
                connection.cancel()
            } else if error == nil {
                self.handleConnection(connection)
            }
        }
    }
    
    private func processRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        
        // Parse HTTP request
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        if method == "POST" && path.contains("/api/v1/events/") {
            handleEventsRequest(request, connection: connection)
        } else {
            sendResponse(connection: connection, status: 404, body: "Not Found")
        }
    }
    
    private func handleEventsRequest(_ request: String, connection: NWConnection) {
        // Extract JSON body
        if let bodyStart = request.range(of: "\r\n\r\n") {
            let bodyString = String(request[bodyStart.upperBound...])
            
            if let bodyData = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) {
                
                // Store received events
                if let eventDict = json as? [String: Any] {
                    receivedEvents.append((endpoint: "", events: [eventDict]))
                } else if let eventsDict = json as? [String: Any],
                          let events = eventsDict["events"] as? [[String: Any]] {
                    receivedEvents.append((endpoint: "", events: events))
                }
            }
        }
        
        // Send success response
        sendResponse(connection: connection, status: 200, body: "OK")
    }
    
    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let response = """
        HTTP/1.1 \(status) OK\r
        Content-Type: text/plain\r
        Content-Length: \(body.count)\r
        \r
        \(body)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// Usage in tests
class NetworkTests: LuxAnalyticsTestCase {
    
    var mockServer: MockAnalyticsServer!
    
    override func setUp() async throws {
        try await super.setUp()
        mockServer = MockAnalyticsServer()
        try mockServer.start()
    }
    
    override func tearDown() async throws {
        mockServer.stop()
        try await super.tearDown()
    }
    
    func testEventSending() async throws {
        let config = try LuxAnalyticsConfiguration(
            dsn: "https://test@localhost:8000/api/v1/events/test"
        )
        
        try await LuxAnalytics.initialize(with: config)
        
        let analytics = await LuxAnalytics.shared
        try await analytics.track("test_event")
        
        await LuxAnalytics.flush()
        
        // Wait for network request
        try await Task.sleep(for: .seconds(1))
        
        XCTAssertEqual(mockServer.receivedEvents.count, 1)
    }
}
```

## Development Workflow

### Branch Strategy

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes and commit
git add .
git commit -m "feat: add new feature

- Implement feature X
- Add tests for feature X
- Update documentation

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to your fork
git push origin feature/your-feature-name

# Create pull request on GitHub
```

### Commit Message Convention

Use conventional commits:

```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation changes
- `test`: Test additions/modifications
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Maintenance tasks

**Examples:**
```
feat(queue): add compression for large batches
fix(network): handle timeout errors gracefully
docs(api): update configuration examples
test(security): add encryption test cases
```

### Pre-commit Hooks

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash

# Run SwiftFormat
if which swiftformat >/dev/null; then
    swiftformat .
else
    echo "warning: SwiftFormat not installed"
fi

# Run SwiftLint
if which swiftlint >/dev/null; then
    swiftlint
else
    echo "warning: SwiftLint not installed"
fi

# Run tests
swift test
if [ $? -ne 0 ]; then
    echo "Tests failed. Commit aborted."
    exit 1
fi

exit 0
```

```bash
# Make it executable
chmod +x .git/hooks/pre-commit
```

## Debugging and Profiling

### Debug Configuration

```swift
// DebugConfiguration.swift
#if DEBUG
extension LuxAnalyticsConfiguration {
    static func debug() throws -> LuxAnalyticsConfiguration {
        return try LuxAnalyticsConfiguration(
            dsn: "https://debug@localhost:8000/api/v1/events/debug",
            debugLogging: true,
            autoFlushInterval: 5.0, // Faster for debugging
            batchSize: 5,           // Smaller batches
            requestTimeout: 10.0    // Longer timeout for debugging
        )
    }
}

extension LuxAnalytics {
    static func debugStatus() async {
        let stats = await getQueueStats()
        let isOnline = await isNetworkAvailable()
        let metrics = await getPerformanceMetrics()
        
        print("🔍 LuxAnalytics Debug Status")
        print("═══════════════════════════")
        print("Initialized: \(isInitialized)")
        print("Online: \(isOnline)")
        print("Queue events: \(stats.totalEvents)")
        print("Queue size: \(stats.totalSizeBytes) bytes")
        print("Memory usage: \(metrics.memoryFootprint) bytes")
        print("Average latency: \(metrics.averageTrackingLatency * 1000)ms")
    }
}
#endif
```

### Performance Profiling

```swift
// PerformanceProfiler.swift
#if DEBUG
class PerformanceProfiler {
    
    static func profileEventTracking() async {
        print("🏃‍♂️ Profiling event tracking performance...")
        
        let iterations = 1000
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let analytics = await LuxAnalytics.shared
        
        for i in 0..<iterations {
            try? await analytics.track("perf_test_\(i)", metadata: [
                "iteration": i,
                "timestamp": Date().timeIntervalSince1970
            ])
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = totalTime / Double(iterations) * 1000 // ms
        
        print("📊 Results:")
        print("  Total time: \(String(format: "%.2f", totalTime))s")
        print("  Average per event: \(String(format: "%.2f", averageTime))ms")
        print("  Events per second: \(String(format: "%.0f", Double(iterations) / totalTime))")
    }
    
    static func profileMemoryUsage() async {
        print("💾 Profiling memory usage...")
        
        let initialMetrics = await LuxAnalytics.getPerformanceMetrics()
        let initialMemory = initialMetrics.memoryFootprint
        
        // Create load
        let analytics = await LuxAnalytics.shared
        for i in 0..<1000 {
            try? await analytics.track("memory_test_\(i)", metadata: [
                "data": String(repeating: "x", count: 1000) // 1KB each
            ])
        }
        
        let finalMetrics = await LuxAnalytics.getPerformanceMetrics()
        let memoryGrowth = finalMetrics.memoryFootprint - initialMemory
        
        print("📊 Memory Results:")
        print("  Initial: \(ByteCountFormatter.string(fromByteCount: Int64(initialMemory), countStyle: .memory))")
        print("  Final: \(ByteCountFormatter.string(fromByteCount: Int64(finalMetrics.memoryFootprint), countStyle: .memory))")
        print("  Growth: \(ByteCountFormatter.string(fromByteCount: Int64(memoryGrowth), countStyle: .memory))")
    }
}
#endif
```

### Network Debugging

```swift
// NetworkDebugger.swift
#if DEBUG
class NetworkDebugger {
    
    static func enableVerboseLogging() {
        // Enable detailed network logging
        setenv("CFNETWORK_DIAGNOSTICS", "3", 1)
        setenv("NSURLSession_DEBUG", "1", 1)
    }
    
    static func logRequest(_ request: URLRequest) {
        print("🌐 HTTP Request:")
        print("  URL: \(request.url?.absoluteString ?? "nil")")
        print("  Method: \(request.httpMethod ?? "nil")")
        print("  Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            print("    \(key): \(value)")
        }
        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            print("  Body: \(bodyString)")
        }
    }
    
    static func logResponse(_ response: URLResponse?, data: Data?) {
        print("🌐 HTTP Response:")
        if let httpResponse = response as? HTTPURLResponse {
            print("  Status: \(httpResponse.statusCode)")
            print("  Headers:")
            httpResponse.allHeaderFields.forEach { key, value in
                print("    \(key): \(value)")
            }
        }
        if let data = data,
           let bodyString = String(data: data, encoding: .utf8) {
            print("  Body: \(bodyString)")
        }
    }
}
#endif
```

## CI/CD Setup

### GitHub Actions

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '16.0'
    
    - name: Cache Swift packages
      uses: actions/cache@v3
      with:
        path: .build
        key: ${{ runner.os }}-spm-${{ hashFiles('Package.swift') }}
        restore-keys: ${{ runner.os }}-spm-
    
    - name: Build
      run: swift build -v
    
    - name: Run tests
      run: swift test --enable-code-coverage
    
    - name: Generate coverage report
      run: |
        xcrun llvm-cov export \
          .build/debug/LuxAnalyticsPackageTests.xctest/Contents/MacOS/LuxAnalyticsPackageTests \
          -instr-profile .build/debug/codecov/default.profdata \
          -format lcov > coverage.lcov
    
    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        file: coverage.lcov
        fail_ci_if_error: true

  build-ios:
    runs-on: macos-latest
    
    strategy:
      matrix:
        destination:
          - 'platform=iOS Simulator,name=iPhone 16,OS=18.0'
          - 'platform=iOS Simulator,name=iPad Air (5th generation),OS=18.0'
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '16.0'
    
    - name: Build for iOS
      run: |
        xcodebuild \
          -scheme LuxAnalytics \
          -sdk iphonesimulator \
          -destination '${{ matrix.destination }}' \
          build
    
    - name: Run iOS tests
      run: |
        xcodebuild \
          -scheme LuxAnalytics \
          -sdk iphonesimulator \
          -destination '${{ matrix.destination }}' \
          test

  lint:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install SwiftLint
      run: brew install swiftlint
    
    - name: Run SwiftLint
      run: swiftlint lint --reporter github-actions-logging

  format-check:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install SwiftFormat
      run: brew install swiftformat
    
    - name: Check formatting
      run: swiftformat --lint .
```

## Documentation

### DocC Integration

```swift
// Example of proper DocC documentation
/**
 * Analytics SDK for iOS applications with privacy-first design.
 *
 * LuxAnalytics provides secure, reliable event tracking with automatic batching,
 * offline support, and enterprise-grade features.
 *
 * ## Quick Start
 *
 * ```swift
 * // Initialize the SDK
 * try await LuxAnalytics.quickStart(
 *     dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id"
 * )
 *
 * // Track events
 * let analytics = await LuxAnalytics.shared
 * try await analytics.track("user_signup", metadata: [
 *     "method": "email",
 *     "source": "app"
 * ])
 * ```
 *
 * ## Topics
 *
 * ### Configuration
 * - ``LuxAnalyticsConfiguration``
 * - ``LuxAnalyticsDefaults``
 *
 * ### Event Tracking
 * - ``track(_:metadata:)``
 * - ``setUser(_:)``
 * - ``setSession(_:)``
 *
 * ### Queue Management
 * - ``flush()``
 * - ``getQueueStats()``
 * - ``clearQueue()``
 */
public actor LuxAnalytics {
    // Implementation...
}
```

### Generate Documentation

```bash
# Generate DocC documentation
swift package generate-documentation \
  --target LuxAnalytics \
  --output-path ./docs/generated \
  --hosting-base-path LuxAnalytics

# Preview documentation
swift package --disable-sandbox preview-documentation \
  --target LuxAnalytics
```

## Contributing Guidelines

### Pull Request Process

1. **Fork** the repository
2. **Create** a feature branch
3. **Implement** your changes with tests
4. **Ensure** all tests pass
5. **Update** documentation if needed
6. **Submit** a pull request

### Code Review Checklist

- [ ] **Functionality**: Does the code work as intended?
- [ ] **Tests**: Are there adequate tests with good coverage?
- [ ] **Performance**: Are there any performance implications?
- [ ] **Security**: Are there any security concerns?
- [ ] **API Design**: Is the API intuitive and consistent?
- [ ] **Documentation**: Is the code properly documented?
- [ ] **Style**: Does the code follow project conventions?

### Review Process

1. **Automated checks** must pass (CI, tests, linting)
2. **Manual review** by core team members
3. **Address feedback** and update PR
4. **Final approval** and merge

## Troubleshooting

### Common Issues

**Build Failures:**
```bash
# Clean build artifacts
rm -rf .build
swift package clean

# Reset package cache
rm -rf ~/Library/Caches/org.swift.swiftpm
swift package reset
```

**Test Failures:**
```bash
# Run tests with verbose output
swift test --verbose

# Run specific test
swift test --filter LuxAnalyticsConfigurationTests.testValidDSN
```

**Xcode Issues:**
```bash
# Clean Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset package caches in Xcode
# File → Packages → Reset Package Caches
```

### Getting Help

- **Documentation**: Check [docs/wiki/](../wiki/) for detailed guides
- **Issues**: Search [GitHub Issues](https://github.com/luxardolabs/LuxAnalytics/issues)
- **Discussions**: Join [GitHub Discussions](https://github.com/luxardolabs/LuxAnalytics/discussions)
- **Contributing**: See [CONTRIBUTING.md](../CONTRIBUTING.md)

## Next Steps

- [🧪 Testing Guide](Testing.md) - Advanced testing strategies
- [🏗️ Custom Extensions](Custom-Extensions.md) - Extend the SDK
- [💡 Best Practices](Best-Practices.md) - Production development patterns
- [🔧 API Reference](API-Reference.md) - Complete API documentation