#!/bin/sh
# Prerequisites: paired, unlocked Watch; same Wi-Fi as Mac. If the transfer stalls,
# turn iPhone Bluetooth off in Settings before retrying, then restore it after use.
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ]; then
    echo 'Usage: ./Scripts/install-watch-release.sh <Watch-CoreDevice-ID>' >&2
    echo 'Find the ID with: xcrun devicectl list devices' >&2
    exit 2
fi
watch_device="$1"
xcodebuild -project LvLian.xcodeproj -scheme LvLianWatch -configuration Release \
  -destination 'generic/platform=watchOS' -derivedDataPath .build/WatchRelease \
  -allowProvisioningUpdates build
watch_app="$PWD/.build/WatchRelease/Build/Products/Release-watchos/LvLianWatch.app"
test ! -f "$watch_app/__preview.dylib"
codesign --verify --deep --strict "$watch_app"
xcrun devicectl --timeout 240 device install app --device "$watch_device" \
  --json-output .build/watch-release-install.json "$watch_app"
