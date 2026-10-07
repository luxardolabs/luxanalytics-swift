# Contributing to LuxAnalytics

Thank you for your interest in contributing to LuxAnalytics! 

## Development Setup

### Requirements
- macOS 14.0+
- Xcode 16.0+
- Swift 6.0 with strict concurrency enabled
- iOS 18.0+ deployment target
- **Zero compilation warnings** standard

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/LuxAnalytics.git
   cd LuxAnalytics
   ```

3. Open in Xcode:
   ```bash
   open Package.swift
   ```

4. Build for iOS:
   ```bash
   xcodebuild -scheme LuxAnalytics -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```

## Code Style

- Follow Swift 6 strict concurrency rules
- Use `async/await` for all asynchronous code
- No force unwrapping (`!`) except in tests
- Use `actor` for shared mutable state
- Document all public APIs

## Pull Request Process

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following these guidelines:
   - Write tests for new functionality
   - Update documentation as needed
   - Ensure all tests pass
   - Follow existing code patterns

3. Commit with clear messages:
   ```bash
   git commit -m "Add feature: description of what you added"
   ```

4. Push and create PR:
   ```bash
   git push origin feature/your-feature-name
   ```

## Testing

Run tests before submitting:
```bash
xcodebuild test -scheme LuxAnalytics -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
```

## What We're Looking For

- **Bug fixes** with tests
- **Performance improvements** with benchmarks
- **Documentation improvements**
- **New features** that align with the SDK's goals
- **Security enhancements**

## What We Won't Accept

- Breaking changes to existing APIs
- iOS 17 or earlier compatibility code
- Synchronous/callback-based APIs
- Features that compromise user privacy

## Questions?

Open an issue for discussion before making large changes.

## License

By contributing, you agree that your contributions will be licensed under the GNU General Public License v3.0.