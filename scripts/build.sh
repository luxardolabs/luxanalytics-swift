#!/usr/bin/env bash
# Build (library and tests) or test the LuxAnalytics package for iOS with xcodebuild. The
# package is iOS-only, so a host `swift build` would compile for macOS instead. The destination comes from env, never a UDID:
#   LUXANALYTICS_DEST       build destination (default: generic/platform=iOS Simulator)
#   LUXANALYTICS_TEST_DEST  test destination  (default: platform=iOS Simulator,name=iPhone 17 Pro)
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-build}" in
  build)
    xcodebuild -scheme LuxAnalytics \
      -destination "${LUXANALYTICS_DEST:-generic/platform=iOS Simulator}" \
      build-for-testing
    ;;
  test)
    xcodebuild -scheme LuxAnalytics \
      -destination "${LUXANALYTICS_TEST_DEST:-platform=iOS Simulator,name=iPhone 17 Pro}" \
      test
    ;;
  *)
    echo "usage: scripts/build.sh build|test" >&2
    exit 2
    ;;
esac
