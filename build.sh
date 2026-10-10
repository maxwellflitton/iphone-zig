#!/bin/sh
# Builds HelloZig.app for the iPhone simulator and launches it.
# Needs a Mac with Xcode (for Apple's SDK and the simulator) and Zig 0.16.
set -eu
cd "$(dirname "$0")"

APP=HelloZig
BUNDLE_ID=dev.example.hellozig

case "$(uname -m)" in
    arm64) ARCH=aarch64 ;;
    *)     ARCH=x86_64 ;;
esac

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

# With --sysroot, Zig resolves -L inside the SDK but takes -F as given,
# so the library path is SDK-relative and the framework path is absolute.
mkdir -p build
zig build-exe src/main.zig \
    -target "$ARCH-ios.16.0-simulator" \
    -O ReleaseSafe \
    --sysroot "$SDK" \
    -L/usr/lib \
    -F"$SDK/System/Library/Frameworks" \
    -framework UIKit \
    -framework Foundation \
    -lobjc -lc \
    -femit-bin="build/$APP"

# An iOS app is a folder holding the executable and Info.plist.
rm -rf "$APP.app"
mkdir "$APP.app"
cp "build/$APP" Info.plist "$APP.app/"
codesign --force --sign - "$APP.app"

# Use the booted simulator, or boot the first available iPhone if none is.
UDID="$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}' || true)"
if [ -z "$UDID" ]; then
    UDID="$(xcrun simctl list devices available | grep -m1 iPhone | grep -oE '[0-9A-F-]{36}')"
    echo "Booting simulator $UDID..."
    xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator

xcrun simctl install "$UDID" "$APP.app"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
