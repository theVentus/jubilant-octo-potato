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
# burst <name> <delays...> -- <launch args>: frame i taken after cumulative delay i
burst() {
  local name=$1; shift; local delays=()
  while [ "$1" != "--" ]; do delays+=("$1"); shift; done; shift
  launch "$@"
  local i=0
  for d in "${delays[@]}"; do sleep "$d"; xcrun simctl io "$UDID" screenshot "$OUT/$name-$i.png" >/dev/null; i=$((i+1)); done
  echo "burst $name ($i frames)"
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
burst lens 2.5 0.8 0.8 0.8 2.5 -- -slowmo YES -demoSelect INR
burst dock 2.5 0.8 0.8 0.8 2.5 -- -slowmo YES -demoCollapse YES
