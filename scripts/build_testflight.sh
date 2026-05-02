#!/usr/bin/env bash
# Build Jobtree iOS app for TestFlight.
# Prerequisites: Apple Developer account, app in App Store Connect, signing configured in Xcode.
set -e

cd "$(dirname "$0")/.."

# Optional: override version for this build (e.g. 1.0.0 2)
BUILD_NAME="${1:-}"
BUILD_NUMBER="${2:-}"

echo "Building iOS app for TestFlight..."

if [[ -n "$BUILD_NAME" && -n "$BUILD_NUMBER" ]]; then
  flutter build ipa --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
else
  flutter build ipa
fi

IPA_PATH="build/ios/ipa/jobtree.ipa"
if [[ -f "$IPA_PATH" ]]; then
  echo ""
  echo "Build succeeded: $IPA_PATH"
  echo ""
  echo "Next steps:"
  echo "  1. Open Xcode → Window → Organizer"
  echo "  2. Select the archive (or drag $IPA_PATH into Transporter)"
  echo "  3. Distribute App → App Store Connect → Upload"
  echo "  4. In App Store Connect, open your app → TestFlight → wait for processing, then add testers"
  echo ""
  echo "Or upload via command line (requires Apple ID app-specific password):"
  echo "  xcrun altool --upload-app -f $IPA_PATH -t ios -u YOUR_APPLE_ID"
else
  echo "Expected IPA not found at $IPA_PATH"
  exit 1
fi
