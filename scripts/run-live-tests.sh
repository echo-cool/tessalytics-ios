#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: %s <base-url> [xcode-destination]\n' "$0" >&2
    exit 64
fi

live_base_url="${1%/}"
destination="${2:-platform=iOS Simulator,name=iPhone 17 Pro}"
derived_path="build/LiveServerDerivedData"
source_run="$derived_path/Build/Products/Tessalytics_iphonesimulator26.5-arm64.xctestrun"
ephemeral_run="$derived_path/Build/Products/Tessalytics-live-ephemeral.xctestrun"

read -r -s -p 'Bearer token: ' live_api_token
printf '\n'

cleanup() {
    unset live_api_token
    if [[ -f "$ephemeral_run" ]]; then
        python3 -c 'import plistlib,sys; path=sys.argv[1]; data=plistlib.load(open(path,"rb")); env=data.get("TessalyticsTests",{}).get("EnvironmentVariables",{}); env.pop("TESSALYTICS_TEST_API_TOKEN",None); env.pop("TESSALYTICS_TEST_BASE_URL",None); plistlib.dump(data,open(path,"wb"))' "$ephemeral_run" 2>/dev/null || true
        unlink "$ephemeral_run"
    fi
}
trap cleanup EXIT INT TERM

xcodebuild \
    -project Tessalytics.xcodeproj \
    -scheme Tessalytics \
    -destination "$destination" \
    -derivedDataPath "$derived_path" \
    build-for-testing

if [[ ! -f "$source_run" ]]; then
    source_run=$(find "$derived_path/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)
fi
if [[ -z "$source_run" || ! -f "$source_run" ]]; then
    printf 'No xctestrun file was produced.\n' >&2
    exit 1
fi

cp "$source_run" "$ephemeral_run"
chmod 600 "$ephemeral_run"
printf '%s\n%s\n' "$live_base_url" "$live_api_token" | python3 -c 'import plistlib,sys; path=sys.argv[1]; base=sys.stdin.readline().rstrip("\n"); token=sys.stdin.readline().rstrip("\n"); data=plistlib.load(open(path,"rb")); env=data["TessalyticsTests"]["EnvironmentVariables"]; env["TESSALYTICS_TEST_BASE_URL"]=base; env["TESSALYTICS_TEST_API_TOKEN"]=token; plistlib.dump(data,open(path,"wb"))' "$ephemeral_run"
unset live_api_token

xcodebuild \
    -xctestrun "$ephemeral_run" \
    -destination "$destination" \
    -only-testing:TessalyticsTests/LiveServerCompatibilityTests \
    test-without-building
