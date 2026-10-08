#!/usr/bin/env bash
# Run Tests/HostApp on the iOS Simulator: checks that need a real app (Keychain, relaunch,
# reinstall, lifecycle notifications, BGTaskScheduler). Builds the app from the SDK's
# sources with swiftc, embeds simulator entitlements the way Xcode does (a __TEXT,
# __entitlements section), then runs five phases: legacy-queue migration and its relaunch, first launch, relaunch, and after
# uninstall + reinstall. Fails on any FAIL line, or if a phase doesn't report DONE. A check
# that can't run in this environment reports SKIP with its reason, counted separately.
#   LUXANALYTICS_HOST_DEVICE  simulator name or UDID (default: iPhone 17 Pro)
set -euo pipefail
cd "$(dirname "$0")/.."

device_name="${LUXANALYTICS_HOST_DEVICE:-iPhone 17 Pro}"
bundle_id="com.luxardolabs.LuxAnalytics.HostCheck"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
app="$work/HostCheck.app"
mkdir -p "$app"

echo "▶ building HostCheck.app"
xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -module-name HostCheck -o "$app/HostCheck" \
  Tests/HostApp/main.swift Sources/LuxAnalytics/*.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker Tests/HostApp/HostCheck.entitlements
cp Tests/HostApp/Info.plist "$app/Info.plist"
codesign -s - --force "$app" 2>/dev/null

# Resolve the simulator: a UDID, or the newest runtime's device with that name.
if [[ "$device_name" =~ ^[0-9A-F-]{36}$ ]]; then
  udid="$device_name"
else
  udid=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in devices if "iOS" in r), key=lambda r: [int(x) for x in r.split("iOS-")[-1].split("-")])
for runtime in reversed(runtimes):
    for d in devices[runtime]:
        if d["name"] == name:
            print(d["udid"]); sys.exit()
' "$device_name")
fi
[ -n "$udid" ] || { echo "❌ no available simulator named '$device_name'" >&2; exit 1; }

was_booted=$(xcrun simctl list devices | grep -c "$udid) (Booted)" || true)
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
cleanup() {
  xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
  [ "$was_booted" = 0 ] && xcrun simctl shutdown "$udid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

run_phase() {
  xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id" "$@" 2>&1 \
    | tr -d '\r' | grep '^HOSTCHECK' || true
}

xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
xcrun simctl install "$udid" "$app"
out_migrate=$(run_phase migrate)
out_migrated=$(run_phase migrated)
out_first=$(run_phase first)
device_id=$(sed -n 's/^HOSTCHECK DEVICE_ID //p' <<<"$out_first")
out_relaunch=$(run_phase relaunch "$device_id")
xcrun simctl uninstall "$udid" "$bundle_id"
xcrun simctl install "$udid" "$app"
out_reinstall=$(run_phase reinstall "$device_id")

all=$(printf '%s\n%s\n%s\n%s\n%s\n' "$out_migrate" "$out_migrated" "$out_first" "$out_relaunch" "$out_reinstall")
grep -E '^HOSTCHECK (PASS|FAIL|SKIP)' <<<"$all" | sed -e 's/^HOSTCHECK PASS/   ✅/' -e 's/^HOSTCHECK FAIL/   ❌/' -e 's/^HOSTCHECK SKIP/   ⏭ /'
done_count=$(grep -c '^HOSTCHECK DONE' <<<"$all" || true)
fail_count=$(grep -c '^HOSTCHECK FAIL' <<<"$all" || true)
pass_count=$(grep -c '^HOSTCHECK PASS' <<<"$all" || true)
skip_count=$(grep -c '^HOSTCHECK SKIP' <<<"$all" || true)
if [ "$done_count" != 5 ] || [ "$fail_count" != 0 ]; then
  echo "🔴 host-check: $fail_count failed, $pass_count passed, $done_count/5 phases finished"
  exit 1
fi
echo "🟢 host-check: $pass_count checks passed across 5 phases, $skip_count skipped (see ⏭ for why; a skip is not a pass)"
