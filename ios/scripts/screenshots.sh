#!/usr/bin/env bash
# Builds for the simulator, launches the app in fixed states and saves screenshots to ./shots.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${UDID:?set UDID}"
BID=com.theventus.fx
OUT="$(pwd)/../shots"; mkdir -p "$OUT"

xcodebuild -project FX.xcodeproj -scheme FX -configuration Debug -destination "id=$UDID" \
  -derivedDataPath build/sim build -quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" build/sim/Build/Products/Debug-iphonesimulator/FX.app

shot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BID" -list "INR,USD,EUR,AED,GBP,JPY" -active USD -expr 250 -showPicker NO "$@" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "shot $name"
}

xcrun simctl ui "$UDID" appearance light
shot light
shot light-expression -expr "1200+350×2"
shot picker -showPicker YES
xcrun simctl ui "$UDID" appearance dark
shot dark
shot dark-expression -expr "1200+350×2"
