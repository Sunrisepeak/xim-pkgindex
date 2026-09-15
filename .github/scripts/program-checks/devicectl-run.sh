#!/usr/bin/env bash
# Runs the installed devicectl-run ($DEVICECTL_RUN) through every refusal a
# macOS runner with no iOS device attached can reach: no operand, an operand
# that is not a bundle, a simulator bundle, a bundle with no CFBundleIdentifier,
# a device named that devicectl does not know, and no connected device at all.
# Installing and launching on hardware needs a device this runner does not have
# and is not claimed here. Every criterion prints one READING line; the script
# exits non-zero on the first criterion that does not hold.
set -uo pipefail
: "${DEVICECTL_RUN:?DEVICECTL_RUN must name the installed program}"

W="$RUNNER_TEMP/devicectl-run"
rm -rf "$W"; mkdir -p "$W"
cd "$W" || exit 1

reading() { printf 'READING %s: %s\n' "$1" "$2"; }
fail() { echo "::error::$*"; exit 1; }
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

expect_refusal() {  # expect_refusal <label> <expected substring> [env...] -- <argv...>
    local label="$1" want="$2"; shift 2
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    local out rc
    out=$(env "${envs[@]+"${envs[@]}"}" "$DEVICECTL_RUN" "$@" 2>&1); rc=$?
    reading "$label" "exit=$rc $(printf '%s' "$out" | tr '\n' ' ')"
    [ "$rc" -eq 2 ] || fail "$label: expected exit 2, got $rc"
    contains "$out" "$want" || fail "$label: the refusal does not say '$want'"
}

plist() {  # plist <bundle> <platform|-> [identifier|-]
    local app="$1" platform="$2" id="${3:-org.xim-pkgindex.devicectl-run.probe}"
    mkdir -p "$app"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        [ "$id" = "-" ] || echo "<key>CFBundleIdentifier</key><string>$id</string>"
        echo '<key>CFBundleExecutable</key><string>probe</string>'
        [ "$platform" = "-" ] || echo "<key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>"
        echo '</dict></plist>'
    } > "$app/Info.plist"
}

command -v xcrun > /dev/null || fail "this runner has no xcrun"
reading "devicectl" "$(xcrun devicectl --version 2>&1 | head -1)"

expect_refusal "no operand" "usage:" --
expect_refusal "an operand that is not a bundle" "is not a .app bundle" -- "$W/not-a-bundle.txt"
touch "$W/file.app"
expect_refusal "a .app that is a file" "is not a .app bundle" -- "$W/file.app"

plist "$W/Simulator.app" iPhoneSimulator
expect_refusal "a simulator bundle" "run it with simctl-run" -- "$W/Simulator.app"

plist "$W/NoIdentifier.app" iPhoneOS -
expect_refusal "a bundle with no CFBundleIdentifier" "could not read CFBundleIdentifier" -- "$W/NoIdentifier.app"

plist "$W/Device.app" iPhoneOS
# With no device attached, `devicectl list devices` either lists none (the
# refusal names that) or cannot reach CoreDevice at all (the refusal names the
# listing); both are exit 2 and both say which. The named-device case is the
# same split.
out=$("$DEVICECTL_RUN" "$W/Device.app" 2>&1); rc=$?
reading "a device bundle with no device attached" "exit=$rc $(printf '%s' "$out" | tr '\n' ' ')"
[ "$rc" -eq 2 ] || fail "expected exit 2 with no device attached, got $rc"
contains "$out" "no connected iOS device" || contains "$out" "devicectl list devices\` failed" \
    || fail "the refusal names neither the missing device nor the failed listing"

out=$(DEVICECTL_RUN_DEVICE=no-such-device "$DEVICECTL_RUN" "$W/Device.app" 2>&1); rc=$?
reading "a named device devicectl does not know" "exit=$rc $(printf '%s' "$out" | tr '\n' ' ')"
[ "$rc" -eq 2 ] || fail "expected exit 2 for an unknown device, got $rc"
contains "$out" "no iOS device named 'no-such-device'" || contains "$out" "devicectl list devices\` failed" \
    || fail "the refusal names neither the unknown device nor the failed listing"
