#!/usr/bin/env bash
# Bakes the Kit's pictures: every asset rendered by the app's own renderer in the Ink Look (KitPicturesTests), written
# as `picture.png` beside its model in App/Resources/Kit. Needs a Mac with Xcode, so it runs in the Kit pictures workflow
# (.github/workflows/kit-pictures.yml), which commits the result. Run it again whenever the Kit or the Ink Look changes;
# `Tools/fetch-kit.py check` fails CI while an asset has no picture.
#
#   Tools/bake-kit-pictures.sh <simulator udid>
set -euo pipefail
UDID="${1:?the udid of an iPad simulator, from Tools/pick-simulator.py}"
cd "$(git rev-parse --show-toplevel)"
OUT="$PWD/App/Resources/Kit"
cd Packages/LoweyFeatures
set -o pipefail
TEST_RUNNER_KIT_PICTURES_OUTPUT="$OUT" xcodebuild test -scheme LoweyFeatures -destination "id=$UDID" \
  -derivedDataPath "${RUNNER_TEMP:-/tmp}/KitPicturesDD" -skipPackagePluginValidation \
  -only-testing:LoweyFeaturesTests/KitPicturesTests/testBakeTheKitsPictures \
  | tee "${RUNNER_TEMP:-/tmp}/kit-pictures.log" | grep -E "error:|Test Case|Executed|\*\* " || true
grep -q "\*\* TEST SUCCEEDED \*\*" "${RUNNER_TEMP:-/tmp}/kit-pictures.log"
find "$OUT" -name picture.png | wc -l
