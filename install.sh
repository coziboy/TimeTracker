#!/bin/zsh
# Build TimeTracker and install it to /Applications, then relaunch it.
#
# Run with no Xcode UI involved:
#   ./install.sh
set -e
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }

echo "==> Generating project"
xcodegen generate

echo "==> Building"
xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Release build \
  | grep -E "^\*\* BUILD" || { echo "build failed"; exit 1; }

BUILT=$(xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Release \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/TimeTracker.app

echo "==> Installing to /Applications"
# Quit the running copy first; you cannot replace a bundle that is in use.
pkill -x TimeTracker 2>/dev/null || true
sleep 1
rm -rf /Applications/TimeTracker.app
cp -R "$BUILT" /Applications/

echo "==> Launching"
open -a /Applications/TimeTracker.app
echo "TimeTracker is in your menu bar."
