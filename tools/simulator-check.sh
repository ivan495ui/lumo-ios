#!/bin/bash
set -euo pipefail
mkdir -p build/artifacts
read -r runtime device_type < <(xcrun simctl list -j | python3 tools/select-simulator.py)
# Always create an empty simulator; never use an existing device container.
device=$(xcrun simctl create "lumo isolated preview" "$device_type" "$runtime")
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance dark
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
set -o pipefail
set +e
xcodebuild -project lumo.xcodeproj -scheme lumo -configuration Debug -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/simulator -resultBundlePath build/ui-tests.xcresult CODE_SIGNING_ALLOWED=NO test 2>&1 | tee build/artifacts/simulator-tests.log
test_result=${PIPESTATUS[0]}
set -e
xcrun xcresulttool export attachments --path build/ui-tests.xcresult --output-path build/artifacts/screenshots || true
# A separate simulator launch demonstrates the actual compiled app without the test runner.
if [ -d build/simulator/Build/Products/Debug-iphonesimulator/lumo.app ]; then
  xcrun simctl install "$device" build/simulator/Build/Products/Debug-iphonesimulator/lumo.app
  xcrun simctl terminate "$device" app.lumo.wallet >/dev/null 2>&1 || true
  SIMCTL_CHILD_LUMO_DEMO=1 xcrun simctl launch "$device" app.lumo.wallet
  sleep 2
  xcrun simctl io "$device" screenshot build/artifacts/lumo-overview.png
fi
exit "$test_result"
