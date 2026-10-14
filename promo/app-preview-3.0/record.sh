#!/bin/zsh
# Records the App Store preview footage on the test iPhone 16 simulator.
# Usage: zsh promo/app-preview-3.0/record.sh <ru|en> <raw folder>
# Builds for testing first, then records the screen while AppPreviewRecording drives the app.
set -e
LANG_CODE=$1
RAW=$2
U=EA8D289A-ABB1-47F2-8C0E-C403A1776965
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$RAW"
xcrun simctl status_bar $U override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl ui $U content_size large
# The app keeps this run's data apart (-isolatedStore) in its own tmp folder; cleared before and after.
CONTAINER=$(xcrun simctl get_app_container $U com.minorailifegroup.MinorAI data)
ISOLATED="$CONTAINER/tmp/isolated-preview-$LANG_CODE"
rm -rf "${ISOLATED:?}"
xcrun simctl io $U recordVideo --codec=h264 --force "$RAW/$LANG_CODE.mp4" 2> "$RAW/$LANG_CODE.rec.log" &
REC=$!
until grep -q "Recording started" "$RAW/$LANG_CODE.rec.log" 2>/dev/null; do sleep 0.1; done
python3 -c 'import time; print(time.time())' > "$RAW/$LANG_CODE.start"
TEST_RUNNER_PREVIEW_RECORD=1 TEST_RUNNER_PREVIEW_LANG=$LANG_CODE xcodebuild test-without-building \
  -project "$ROOT/Minor Ai.xcodeproj" -scheme "Minor Ai UI Checks" -destination "id=$U" \
  -only-testing:"Minor AiUITests/AppPreviewRecording" -parallel-testing-enabled NO \
  -collect-test-diagnostics never > "$RAW/$LANG_CODE.test.log" 2>&1 || true
kill -INT $REC
wait $REC 2>/dev/null || true
rm -rf "${ISOLATED:?}"
grep "PREVIEW|" "$RAW/$LANG_CODE.test.log" | sed 's/.*PREVIEW|/PREVIEW|/' > "$RAW/$LANG_CODE.marks"
echo "recorded $(wc -l < "$RAW/$LANG_CODE.marks") marks"
