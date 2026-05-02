#!/usr/bin/env bash
# Build Jobtree Android app for Play Store internal/closed testing (or sideload).
# Output: AAB (recommended for Play) and optionally APK.
set -e

cd "$(dirname "$0")/.."

# Optional: override version (e.g. 1.0.0 2)
BUILD_NAME="${1:-}"
BUILD_NUMBER="${2:-}"

echo "Building Android app (release)..."

if [[ -n "$BUILD_NAME" && -n "$BUILD_NUMBER" ]]; then
  flutter build appbundle --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
else
  flutter build appbundle
fi

AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
if [[ -f "$AAB_PATH" ]]; then
  echo ""
  echo "Build succeeded: $AAB_PATH"
  echo ""
  echo "Next steps (Google Play internal testing):"
  echo "  1. Go to Google Play Console → your app → Testing → Internal testing"
  echo "  2. Create release → Upload $AAB_PATH"
  echo "  3. Add testers (email list) and save"
  echo ""
  echo "Optional: build APK for direct install (e.g. Firebase App Distribution):"
  echo "  flutter build apk --release"
  echo "  Output: build/app/outputs/flutter-apk/app-release.apk"
else
  echo "Expected AAB not found at $AAB_PATH"
  exit 1
fi
