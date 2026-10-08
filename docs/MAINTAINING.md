# Maintaining

How to build, test, check and release the SDK. For contributor expectations, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Layout

| Path | What |
|---|---|
| `Sources/LuxAnalytics/` | The SDK (one module, iOS 18+). `NetworkTransport.swift` is the only file that touches `URLSession`. |
| `Tests/LuxAnalyticsTests/` | Swift Testing suites. Suites that touch the SDK's singletons are nested under `GlobalStateTests`, which runs them one at a time. |
| `scripts/build.sh` | `build` (library and tests) or `test`, with `xcodebuild` against the iOS Simulator |
| `scripts/contract_facts.py` | The SDK's request bodies, for luxios's contract check against the server's `openapi.json` |
| `scripts/docs-check.py` | Compiles every Swift example in the docs |
| `docs/` | The documentation; `CHANGELOG.md` and `CONTRIBUTING.md` are at the root |

## Make targets

| Target | What it does |
|---|---|
| `make ios-check` | The gate: docs-check, then luxios's lint, format, architecture, build (with 0 concurrency warnings allowed) and contract stages. Run it before every commit. |
| `make docs-check` | Compile every ` ```swift ` block in `README.md` and `docs/` against the SDK as an app would, and check every ` ```swift interface ` listing against the compiler's public interface. |
| `make test` | The test suite on the iOS Simulator (default `iPhone 17 Pro`; set `LUXANALYTICS_TEST_DEST` to change it). |
| `make integration` | The test suite, plus tests that send real requests to the dev server. |
| `make ios-format` | Rewrite sources to the canonical format (swift-format). |

## Local settings

Settings that name private hosts live in an untracked `Makefile.local`. Copy `Makefile.local.example` and fill in:

| Setting | Used by | Value |
|---|---|---|
| `LUXANALYTICS_OPENAPI_URL` | `make ios-check` (contract stage) | The dev server's `/openapi.json` |
| `LUXANALYTICS_DEV_URL` | `make integration` | The dev server's base URL |
| `LUXANALYTICS_DEV_DSN` | `make integration` | The DSN of the dev `sdk-integration` app |

Each target refuses to run without its settings rather than skip the check.

## The luxios gate

The SDK follows luxios, the fleet's iOS standard. The pin is `LUXIOS_VERSION` in the `Makefile`, and the luxios checkout defaults to `../luxios` (override with `LUXIOS=`). `make ios-check` stops if that checkout's `VERSION` doesn't match the pin.

The contract stage checks `AnalyticsEvent` and the batch body against the server's `EventCreate` and `BatchEventRequest`. When the wire format changes on either side, update `scripts/contract_facts.py` in the same change. Editing that file is the contract change.

## Tests

- `make test` runs everything that doesn't need a server. The dev-server suites report themselves skipped.
- `make integration` also sends real requests to the dev server: refused credentials, accepted and compressed batches, duplicate event ids, validation errors, and a full track-then-flush.
- Two Keychain-backed encryption tests skip under `make test`, because the SwiftPM test bundle has no Keychain entitlement.

## Releasing

1. Update `VERSION`, `LuxAnalyticsVersion.current` and the `CHANGELOG.md` heading together.
2. `make ios-check` and `make integration` must pass.
3. Tag the release commit `vX.Y.Z`. Tags are immutable: never move or reuse one.
4. Versions on this repository start at 1.1.0. The 1.0.x numbers belonged to the old history and are never reused: SwiftPM caches would point one version at two different commits.

Work is tracked in the **LuxAnalytics** project in LuxPM.
