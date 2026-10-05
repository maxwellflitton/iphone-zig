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

# Start a simulator from Xcode first if none is running.
open -a Simulator
xcrun simctl bootstatus booted >/dev/null 2>&1 || {
    echo "Built $APP.app. Boot a simulator, then run:"
    echo "  xcrun simctl install booted $APP.app && xcrun simctl launch booted $BUNDLE_ID"
    exit 0
}
xcrun simctl install booted "$APP.app"
xcrun simctl launch booted "$BUNDLE_ID"
