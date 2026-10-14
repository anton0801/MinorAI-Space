#!/bin/zsh
# Opens every screen in screens.txt on the simulator with an iPhone-like main-thread stack.
# The simulator's main thread has 8 MB of stack, an iPhone's 1 MB: 3.0.0 passed every test and
# crashed on phones. This builds with Release optimization (plus the DEBUG demo flags), cuts the
# app's stack (default 512 KB, half an iPhone's) and reports screens that die.
#
#   zsh tools/stack-check/check.sh <simulator udid> [stack bytes, e.g. 0x80000]
set -u
U=$1; SIZE=${2:-0x80000}
ROOT=${0:A:h}/../..
DD=${TMPDIR:-/tmp}/minor-stack-check
B=com.minorailifegroup.MinorAI
xcodebuild build -project "$ROOT/Minor Ai.xcodeproj" -scheme "Minor Ai" -configuration Release \
  -destination "id=$U" -derivedDataPath "$DD" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG' ONLY_ACTIVE_ARCH=YES -quiet || exit 1
A="$DD/Build/Products/Release-iphonesimulator/Minor Ai.app"
python3 "${0:A:h}/setstack.py" "$A/Minor Ai" $SIZE && codesign -f -s - "$A" >/dev/null 2>&1
xcrun simctl install $U "$A"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  xcrun simctl terminate $U $B 2>/dev/null
  pid=$(xcrun simctl launch $U $B -didOnboard YES -appLanguage en -auditSignedOut -noResume -demoPlus -isolatedStore stack-check ${=line} | awk '{print $NF}')
  sleep 7
  if kill -0 $pid 2>/dev/null; then echo "ok    $line"; else echo "DIED  $line"; fi
done < "${0:A:h}/screens.txt"
xcrun simctl terminate $U $B 2>/dev/null
echo "Reinstall the normal Debug build afterwards: this one has a cut stack."
