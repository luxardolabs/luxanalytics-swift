# LuxAnalytics Swift SDK
VERSION := $(shell cat VERSION)

# Per-site settings that must not be committed (private hostnames). See Makefile.local.example.
-include Makefile.local

# iOS conformance standard (luxios), the iOS sibling of luxarch/luxlint/luxaudit.
# The pin is a committed fact, so it uses `:=` and can't be shadowed by a Makefile.local.
# The checkout PATH is per-site topology and stays overridable with `?=`.
LUXIOS_VERSION := 0.9.0
LUXIOS         ?= ../luxios

# The facts handed to the gate (no `#` comments inside the recipe: a `#` line ends make's
# logical line and silently unsets every fact above it):
#   APP_SRC    the library target, its tests, and the host-check app
#   NET_LAYER  the one file allowed to touch URLSession
#   VIEW_DIRS  none: a library has no view layer (luxios 0.8.0 declared skip; §2's view
#              check and §9 print a skip line). DESIGN_SYS is unset for the same reason.
#   BUILD_CMD  xcodebuild for the iOS Simulator (the package is iOS-only)
#   CONTRACT_FACTS  the SDK's request bodies vs the server's /openapi.json. The spec URL is
#              the dev server's (a private host), so it isn't committed: `export OPENAPI_URL = …`
#              in Makefile.local. Without it luxios fails the contract stage.
APP_SRC   := Sources/LuxAnalytics:Tests/LuxAnalyticsTests:Tests/HostApp
NET_LAYER := NetworkTransport.swift

.PHONY: help ios-check ios-format test integration host-check docs-check luxios-pin

help: ## Show this help message
	@echo "LuxAnalytics v$(VERSION)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

luxios-pin: ## Verify the luxios checkout matches LUXIOS_VERSION
	@test -f "$(LUXIOS)/scripts/ios-check.sh" || { echo "luxios not found at $(LUXIOS) (set LUXIOS=<path to a luxios checkout>)"; exit 1; }
	@have=$$(cat "$(LUXIOS)/VERSION"); [ "$$have" = "$(LUXIOS_VERSION)" ] || { echo "luxios at $(LUXIOS) is $$have, but this repo pins $(LUXIOS_VERSION) (check out v$(LUXIOS_VERSION) there)"; exit 1; }

ios-check: luxios-pin docs-check ## The gate: docs-check, then luxios $(LUXIOS_VERSION) (wiring + lint + format + arch + build + contract + decode)
	@APP_SRC="$(APP_SRC)" \
	 NET_LAYER="$(NET_LAYER)" \
	 VIEW_DIRS="none" \
	 BUILD_CMD="bash scripts/build.sh build" \
	 CONTRACT_FACTS="scripts/contract_facts.py" \
	 bash "$(LUXIOS)/scripts/ios-check.sh"

host-check: ## Checks that need a real app on the Simulator: Keychain, relaunch, reinstall, lifecycle
	@bash scripts/host-check.sh

docs-check: ## Compile every Swift example in README.md and docs/ against the SDK
	@python3 -I scripts/docs-check.py

ios-format: luxios-pin ## Rewrite sources to the canonical luxios style
	@APP_SRC="$(APP_SRC)" MODE=fix bash "$(LUXIOS)/scripts/format-check.sh"

test: ## Run the Swift Testing suite on an iOS Simulator
	@bash scripts/build.sh test

integration: ## The suite plus real-HTTP tests against the dev server (settings in Makefile.local)
	@[ -n "$(LUXANALYTICS_DEV_URL)" ] || { echo "LUXANALYTICS_DEV_URL is not set (see Makefile.local.example)"; exit 1; }
	@[ -n "$(LUXANALYTICS_DEV_DSN)" ] || { echo "LUXANALYTICS_DEV_DSN is not set: needs the dev sdk-integration app (LUXANALYTI-73)"; exit 1; }
	@TEST_RUNNER_LUXANALYTICS_DEV_URL="$(LUXANALYTICS_DEV_URL)" \
	 TEST_RUNNER_LUXANALYTICS_DEV_DSN="$(LUXANALYTICS_DEV_DSN)" \
	 bash scripts/build.sh test
