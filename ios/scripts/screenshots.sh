#!/usr/bin/env bash
# Builds for the simulator, launches the app in fixed states and saves screenshots to ./shots.
# Morph checks: -slowmo stretches animations 6x and bursts capture frames mid-transition.
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

BASE=(-list "INR,USD,EUR,AED,GBP,JPY,SGD" -active USD -expr 250 -showPicker NO)
launch() {
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BID" "${BASE[@]}" "$@" >/dev/null
}
shot() { local name=$1; shift; launch "$@"; sleep 5; xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null; echo "shot $name"; }
# record <name> <launch args>: 8s screen recording -> frames at 3 fps (morph check)
record() {
  local name=$1; shift
  launch "$@"
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/$name.mov" &
  local pid=$!
  sleep 8; kill -INT $pid; wait $pid || true
  mkdir -p "$OUT/$name"
  ffmpeg -loglevel error -i "$OUT/$name.mov" -vf "fps=3,scale=330:-1" "$OUT/$name/%02d.png"
  rm -f "$OUT/$name.mov"
  echo "record $name ($(ls "$OUT/$name" | wc -l) frames)"
}

for mode in dark light; do
  xcrun simctl ui "$UDID" appearance $mode
  shot "main-$mode"
  shot "expr-$mode" -expr "1200+350×2"
  shot "collapsed-$mode" -startCollapsed YES
done
shot system-light -bg system
xcrun simctl ui "$UDID" appearance dark
shot system-dark -bg system
shot picker -showPicker YES
record lens -slowmo YES -demoSelect INR
record dock -slowmo YES -demoCollapse YES
