# LuxAnalytics Swift SDK
VERSION := $(shell cat VERSION)

# Per-site settings that must not be committed (private hostnames). See Makefile.local.example.
-include Makefile.local

# iOS conformance standard (luxios), the iOS sibling of luxarch/luxlint/luxaudit.
# The pin is a committed fact, so it uses `:=` and can't be shadowed by a Makefile.local.
# The checkout PATH is per-site topology and stays overridable with `?=`.
LUXIOS_VERSION := 0.7.3
LUXIOS         ?= ../luxios

# The facts handed to the gate (no `#` comments inside the recipe: a `#` line ends make's
# logical line and silently unsets every fact above it):
#   APP_SRC    the library target and its tests
#   NET_LAYER  the one file allowed to touch URLSession
#   VIEW_DIRS  none: a library has no views, so the name matches no directory and §2's
#              view check finds nothing to scan. DESIGN_SYS is unset for the same reason
#              and §9 reports itself skipped.
#   BUILD_CMD  xcodebuild for the iOS Simulator (the package is iOS-only)
#   CONTRACT_FACTS  the SDK's request bodies vs the server's /openapi.json. The spec URL
#              comes from LUXANALYTICS_OPENAPI_URL (Makefile.local); the gate refuses to run
#              without it rather than skip the stage.
APP_SRC   := Sources/LuxAnalytics:Tests/LuxAnalyticsTests
NET_LAYER := NetworkTransport.swift

.PHONY: help ios-check ios-format test integration luxios-pin contract-url

help: ## Show this help message
	@echo "LuxAnalytics v$(VERSION)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

luxios-pin: ## Verify the luxios checkout matches LUXIOS_VERSION
	@test -f "$(LUXIOS)/scripts/ios-check.sh" || { echo "luxios not found at $(LUXIOS) (set LUXIOS=<path to a luxios checkout>)"; exit 1; }
	@have=$$(cat "$(LUXIOS)/VERSION"); [ "$$have" = "$(LUXIOS_VERSION)" ] || { echo "luxios at $(LUXIOS) is $$have, but this repo pins $(LUXIOS_VERSION) (check out v$(LUXIOS_VERSION) there)"; exit 1; }

contract-url:
	@[ -n "$(LUXANALYTICS_OPENAPI_URL)" ] || { echo "LUXANALYTICS_OPENAPI_URL is not set: the contract stage needs the server's /openapi.json (copy Makefile.local.example to Makefile.local)"; exit 1; }

ios-check: luxios-pin contract-url ## The iOS gate (luxios $(LUXIOS_VERSION)): lint + format + arch + build + contract + decode
	@APP_SRC="$(APP_SRC)" \
	 NET_LAYER="$(NET_LAYER)" \
	 VIEW_DIRS="Views" \
	 BUILD_CMD="bash scripts/build.sh build" \
	 CONTRACT_FACTS="scripts/contract_facts.py" \
	 LUXANALYTICS_OPENAPI_URL="$(LUXANALYTICS_OPENAPI_URL)" \
	 bash "$(LUXIOS)/scripts/ios-check.sh"

ios-format: luxios-pin ## Rewrite sources to the canonical luxios style
	@APP_SRC="$(APP_SRC)" MODE=fix bash "$(LUXIOS)/scripts/format-check.sh"

test: ## Run the Swift Testing suite on an iOS Simulator
	@bash scripts/build.sh test

integration: ## The suite plus real-HTTP tests against the dev server (settings in Makefile.local)
	@[ -n "$(LUXANALYTICS_DEV_URL)" ] || { echo "LUXANALYTICS_DEV_URL is not set (see Makefile.local.example)"; exit 1; }
	@[ -n "$(LUXANALYTICS_DEV_DSN)" ] || { echo "LUXANALYTICS_DEV_DSN is not set: needs the dev sdk-integration app (LUXANALYTI-73)"; exit 1; }
	@pin=$$(bash scripts/leaf-pin.sh "$(LUXANALYTICS_DEV_URL)") || exit 1; \
	 TEST_RUNNER_LUXANALYTICS_DEV_URL="$(LUXANALYTICS_DEV_URL)" \
	 TEST_RUNNER_LUXANALYTICS_DEV_DSN="$(LUXANALYTICS_DEV_DSN)" \
	 TEST_RUNNER_LUXANALYTICS_DEV_PIN="$$pin" \
	 bash scripts/build.sh test
