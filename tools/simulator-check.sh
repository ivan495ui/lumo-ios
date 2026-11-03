#!/bin/bash
set -euo pipefail
mkdir -p build/artifacts
mode="${1:-all}"
if [ "$mode" = all ]; then
  bash tools/simulator-check.sh prepare
  bash tools/simulator-check.sh test
  exit
fi
if [ "$mode" = prepare ]; then
  xcrun simctl list -j > build/artifacts/simulator-inventory.json
  read -r runtime device_type < <(python3 tools/select-simulator.py < build/artifacts/simulator-inventory.json)
  device=$(xcrun simctl create "lumo isolated preview" "$device_type" "$runtime")
  printf '%s\n' "$device" > build/sim-device.txt
  # Compile before booting iOS to keep memory available on the standard free runner.
  python3 tools/run-bounded.py 360 xcodebuild -project lumo.xcodeproj -scheme lumo -configuration Debug -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | tee build/artifacts/simulator-build.log
  xcrun simctl boot "$device"
  python3 tools/run-bounded.py 180 xcrun simctl bootstatus "$device" -b
  xcrun simctl ui "$device" appearance dark
  xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
  xcrun simctl install "$device" build/simulator/Build/Products/Debug-iphonesimulator/lumo.app
  SIMCTL_CHILD_LUMO_DEMO=1 xcrun simctl launch "$device" app.lumo.wallet
  sleep 3
  xcrun simctl io "$device" screenshot --display=1 build/artifacts/lumo-overview.png
elif [ "$mode" = test ]; then
  device=$(cat build/sim-device.txt)
  selection=()
  if [ "${LUMO_UI_TEST:-all}" = crypto ]; then
    selection=(-only-testing:LumoUITests/LumoUITests/testReceiveAndWithdrawUSDTKeepFiatAndEnvelopesSeparate)
  fi
  set +e
  python3 tools/run-bounded.py 600 xcodebuild -project lumo.xcodeproj -scheme lumo -configuration Debug -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/simulator -resultBundlePath build/ui-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 180 "${selection[@]}" CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | tee build/artifacts/simulator-tests.log
  test_result=${PIPESTATUS[0]}
  set -e
  xcrun xcresulttool export attachments --path build/ui-tests.xcresult --output-path build/artifacts/screenshots || true
  exit "$test_result"
else
  echo 'Expected prepare or test' >&2
  exit 2
fi
