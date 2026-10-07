# Installation Guide

Complete guide to installing and setting up LuxAnalytics in your iOS project.

## Requirements

- **iOS 18.0+** (minimum deployment target)
- **Swift 6.0+** with strict concurrency enabled
- **Xcode 16.0+** 
- **macOS 14.0+** (for development)

## Installation Methods

### Swift Package Manager (Recommended)

#### Method 1: Xcode GUI

1. Open your project in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/luxardolabs/LuxAnalytics
   ```
4. Select version constraint:
   - **Up to Next Major**: `1.0.0 < 2.0.0` (recommended)
   - **Exact Version**: `1.0.0`
   - **Branch**: `main` (for latest development)
5. Click **Add Package**
6. Select **LuxAnalytics** target and click **Add Package**

#### Method 2: Package.swift

Add to your `Package.swift` file:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [
        .iOS(.v18)  // iOS 18.0 minimum
    ],
    dependencies: [
        .package(
            url: "https://github.com/luxardolabs/LuxAnalytics", 
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [
                "LuxAnalytics"
            ]
        )
    ]
)
```

#### Method 3: Xcode Project Dependencies

If you're using an Xcode project (not Swift Package):

1. Select your project in Project Navigator
2. Select your app target
3. Go to **General** tab
4. Scroll to **Frameworks, Libraries, and Embedded Content**
5. Click **+** and select **Add Package Dependency...**
6. Follow steps from Method 1

## Verification

### Import Check

Add to any Swift file:

```swift
import LuxAnalytics

// Verify SDK version
print("LuxAnalytics version: \(LuxAnalyticsVersion.current)")
```

### Build Verification

Ensure zero compilation warnings:

```bash
# From your project root
xcodebuild -scheme YourScheme -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build | grep -i warning
```

**Expected output**: No warnings related to LuxAnalytics

### Quick Functionality Test

```swift
import LuxAnalytics

@main
struct TestApp: App {
    init() {
        Task {
            do {
                try await LuxAnalytics.quickStart(
                    dsn: "https://test@example.com/api/v1/events/test"
                )
                print("✅ LuxAnalytics initialized successfully")
            } catch {
                print("❌ Initialization failed: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

## Project Configuration

### Update Deployment Target

Ensure your project targets iOS 18.0+:

**Xcode Project:**
1. Select project → Target → **General**
2. Set **Minimum Deployments** → **iOS** to `18.0`

**Package.swift:**
```swift
platforms: [
    .iOS(.v18)
]
```

### Enable Swift 6 Mode

**Xcode Project:**
1. Target → **Build Settings** 
2. Search "Swift Language Version"
3. Set to **Swift 6**

**Package.swift:**
```swift
swiftLanguageVersions: [.v6]
```

### Configure Build Settings

**Recommended build settings:**

| Setting | Value | Purpose |
|---------|-------|---------|
| Swift Language Version | Swift 6 | Enable strict concurrency |
| Swift Strict Concurrency | Complete | Data race safety |
| iOS Deployment Target | 18.0 | Required for LuxAnalytics |

## Integration Patterns

### SwiftUI App

```swift
import SwiftUI
import LuxAnalytics

@main
struct MySwiftUIApp: App {
    init() {
        Task {
            await initializeAnalytics()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func initializeAnalytics() async {
        do {
            try await LuxAnalytics.quickStart(
                dsn: Bundle.main.luxAnalyticsDSN ?? "fallback-dsn"
            )
        } catch {
            print("Analytics initialization failed: \(error)")
        }
    }
}

extension Bundle {
    var luxAnalyticsDSN: String? {
        object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String
    }
}
```

### UIKit App

```swift
import UIKit
import LuxAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication, 
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        Task {
            await initializeAnalytics()
        }
        
        return true
    }
    
    private func initializeAnalytics() async {
        do {
            try await LuxAnalytics.initializeFromPlist()
        } catch {
            print("Analytics initialization failed: \(error)")
        }
    }
}
```

## Troubleshooting Installation

### Common Issues

#### "Cannot find 'LuxAnalytics' in scope"

**Cause**: Import missing or package not added properly

**Solutions**:
1. Add `import LuxAnalytics` to your file
2. Verify package is in Project Navigator
3. Clean build folder: **Product** → **Clean Build Folder**
4. Reset packages: **File** → **Packages** → **Reset Package Caches**

#### "No such module 'LuxAnalytics'"

**Cause**: Build configuration issue

**Solutions**:
1. Check deployment target is iOS 18.0+
2. Verify Swift version is 6.0+
3. Ensure package is added to correct target
4. Try removing and re-adding the package

#### Build Warnings

**Cause**: Swift 6 strict concurrency warnings

**Solutions**:
1. Update to latest LuxAnalytics version
2. Enable Swift 6 mode in build settings
3. Check our [Troubleshooting Guide](Troubleshooting.md)

#### Linker Errors

**Cause**: Framework not properly embedded

**Solutions**:
1. Check **Frameworks, Libraries, and Embedded Content**
2. Ensure LuxAnalytics is set to "Do Not Embed"
3. Clean and rebuild project

### Getting Help

If installation issues persist:

1. **Check version compatibility**:
   ```swift
   print("iOS Version: \(UIDevice.current.systemVersion)")
   print("Swift Version: \(#if swift(>=6.0) "6.0+" #else "< 6.0" #endif)")
   ```

2. **Verify requirements**:
   - iOS 18.0+ deployment target
   - Swift 6.0+ language version
   - Xcode 16.0+

3. **Report issue**:
   - [GitHub Issues](https://github.com/luxardolabs/LuxAnalytics/issues)
   - Include Xcode version, iOS version, error messages
   - Provide minimal reproduction case

## Next Steps

After successful installation:

1. [🚀 Quick Start Tutorial](Quick-Start.md) - First implementation
2. [🔧 Configuration Guide](Configuration.md) - Setup options  
3. [📊 Event Tracking](Event-Tracking.md) - Track your first events
4. [💡 Best Practices](Best-Practices.md) - Production-ready patterns

---

## Version History

| Version | iOS | Swift | Xcode | Notes |
|---------|-----|-------|-------|-------|
| 1.0.0+ | 18.0+ | 6.0+ | 16.0+ | Initial release with full Swift 6 support |

For older platform support, consider alternative analytics solutions or contact support for enterprise licensing options.