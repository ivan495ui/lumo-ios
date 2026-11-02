#!/bin/bash
set -euo pipefail
mkdir -p build/artifacts
runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(sorted(r,key=lambda x:tuple(map(int,x["version"].split("."))))[-1]["identifier"])')
# Always create an empty simulator; never use an existing device container.
device=$(xcrun simctl create "lumo isolated preview" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$runtime")
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance dark
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
set -o pipefail
xcodebuild -project lumo.xcodeproj -scheme lumo -configuration Debug -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/simulator -resultBundlePath build/ui-tests.xcresult CODE_SIGNING_ALLOWED=NO test 2>&1 | tee build/artifacts/simulator-tests.log
xcrun xcresulttool export attachments --path build/ui-tests.xcresult --output-path build/artifacts/screenshots
# A separate simulator launch demonstrates the actual compiled app without the test runner.
SIMCTL_CHILD_LUMO_DEMO=1 xcrun simctl launch "$device" app.lumo.wallet
sleep 2
xcrun simctl io "$device" screenshot build/artifacts/lumo-overview.png
