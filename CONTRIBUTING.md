# Contributing to LuxAnalytics

Thank you for your interest in contributing to LuxAnalytics! 

## Development setup

You need macOS with Xcode 16 or later (Swift 6), and the iOS Simulator.

```bash
git clone https://github.com/YOUR_USERNAME/luxanalytics-swift.git
cd luxanalytics-swift
open Package.swift
```

Build, test and check with `make` (see [docs/MAINTAINING.md](docs/MAINTAINING.md)):

```bash
make test        # the test suite on the iOS Simulator
make docs-check  # every Swift example in the docs compiles
```

`make ios-check` (the full gate) also needs a luxios checkout and the settings in `Makefile.local`; maintainers run it before merging.

## Code Style

- Follow Swift 6 strict concurrency rules
- Use `async/await` for all asynchronous code
- No force unwrapping (`!`) except in tests
- Use `actor` for shared mutable state
- Document all public APIs, and update `docs/` when behaviour changes

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

Add tests with your change, and run `make test` before opening a pull request. If you change the docs, run `make docs-check`: every Swift example must compile against the SDK.

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

By contributing, you agree that your contributions will be licensed under the MIT License (see [LICENSE](LICENSE)).