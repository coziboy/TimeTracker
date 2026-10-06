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
# Xcode 27 spews DVTCoreDeviceCore plug-in load failures on stderr — a broken
# device-discovery plug-in in the Xcode install itself. It plays no part in
# building a local Mac app, so the log goes to a file and only real
# diagnostics plus the result are shown.
LOG=$(mktemp -t timetracker-build)
if ! xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker \
     -configuration Release build > "$LOG" 2>&1; then
  echo "Build failed:"
  grep -E "error: " "$LOG" | grep -vE "DVTPlugIn|CoreDevice|DVTAssertions" | head -20
  echo "(full log: $LOG)"
  exit 1
fi
grep -E "^\*\* BUILD" "$LOG"
rm -f "$LOG"

BUILT=$(xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Release \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/TimeTracker.app

echo "==> Installing to /Applications"
# Quit the running copy first; you cannot replace a bundle that is in use.
pkill -x TimeTracker 2>/dev/null || true
sleep 1
rm -rf /Applications/TimeTracker.app
cp -R "$BUILT" /Applications/

# The CLI ships inside the app; link it rather than copy it so every
# reinstall updates it too. Override the directory with TIMETRACKER_BIN_DIR.
BIN_DIR="${TIMETRACKER_BIN_DIR:-$HOME/.local/bin}"
CLI=/Applications/TimeTracker.app/Contents/Helpers/timetracker
echo "==> Linking CLI: $BIN_DIR/timetracker"
mkdir -p "$BIN_DIR"
if [[ -e "$BIN_DIR/timetracker" && ! -L "$BIN_DIR/timetracker" ]]; then
  # A real file there is something the user put in place; leave it alone.
  echo "    $BIN_DIR/timetracker exists and is not a link; skipped"
else
  ln -sf "$CLI" "$BIN_DIR/timetracker"
fi
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "    $BIN_DIR is not on your PATH; add it to use 'timetracker'"
fi
echo "    Tab completion (zsh): add to ~/.zshrc"
echo '      eval "$(timetracker completion zsh)"'

echo "==> Launching"
open -a /Applications/TimeTracker.app
echo "TimeTracker is in your menu bar."
