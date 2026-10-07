# LuxAnalytics Swift SDK
VERSION := $(shell cat VERSION)

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
APP_SRC   := Sources/LuxAnalytics:Tests/LuxAnalyticsTests
NET_LAYER := NetworkTransport.swift

.PHONY: help ios-check ios-format test luxios-pin

help: ## Show this help message
	@echo "LuxAnalytics v$(VERSION)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

luxios-pin: ## Verify the luxios checkout matches LUXIOS_VERSION
	@test -f "$(LUXIOS)/scripts/ios-check.sh" || { echo "luxios not found at $(LUXIOS) (set LUXIOS=<path to a luxios checkout>)"; exit 1; }
	@have=$$(cat "$(LUXIOS)/VERSION"); [ "$$have" = "$(LUXIOS_VERSION)" ] || { echo "luxios at $(LUXIOS) is $$have, but this repo pins $(LUXIOS_VERSION) (check out v$(LUXIOS_VERSION) there)"; exit 1; }

ios-check: luxios-pin ## The iOS gate (luxios $(LUXIOS_VERSION)): lint + format + arch + build + contract + decode
	@APP_SRC="$(APP_SRC)" \
	 NET_LAYER="$(NET_LAYER)" \
	 VIEW_DIRS="Views" \
	 BUILD_CMD="bash scripts/build.sh build" \
	 bash "$(LUXIOS)/scripts/ios-check.sh"

ios-format: luxios-pin ## Rewrite sources to the canonical luxios style
	@APP_SRC="$(APP_SRC)" MODE=fix bash "$(LUXIOS)/scripts/format-check.sh"

test: ## Run the Swift Testing suite on an iOS Simulator
	@bash scripts/build.sh test
