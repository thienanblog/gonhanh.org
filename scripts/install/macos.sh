#!/bin/bash
# Replace /Applications/GoNhanh.app with the app built by scripts/build/macos.sh and
# relaunch it. Needs no sudo, so it also runs from non-interactive shells (agents).
# The input method stops only between the kill and the relaunch (a few seconds).
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$PROJECT_ROOT/platforms/macos/build/Release/GoNhanh.app"
DEST="/Applications/GoNhanh.app"
BINARY="$DEST/Contents/MacOS/GoNhanh"

if [ ! -d "$SRC" ]; then
    echo "❌ $SRC not found. Build it first: ./scripts/build/macos.sh"
    exit 1
fi
codesign --verify --deep --strict "$SRC"

# Remove stale login items that point at a build-directory copy (older make build runs).
# Bounded to 5s: without Automation permission for System Events, macOS shows a prompt
# and osascript would block a non-interactive install until someone answers it.
osascript -e 'tell application "System Events"' \
    -e 'repeat with i from (count of every login item) to 1 by -1' \
    -e 'set li to login item i' \
    -e 'if name of li is "GoNhanh" and path of li contains "/build/" then delete login item i' \
    -e 'end repeat' -e 'end tell' > /dev/null 2>&1 &
OSA_PID=$!
for _ in $(seq 1 50); do
    kill -0 "$OSA_PID" 2>/dev/null || break
    sleep 0.1
done
kill "$OSA_PID" 2>/dev/null || true

wait_until_gone() {
    for _ in $(seq 1 "$1"); do
        pgrep -x GoNhanh > /dev/null 2>&1 || return 0
        sleep 0.1
    done
    return 1
}

# Quit every running GoNhanh (installed or build copy) and wait until it is gone, so the
# launch check below cannot see the old process.
pkill -x GoNhanh 2>/dev/null || true
if ! wait_until_gone 20; then
    pkill -9 -x GoNhanh 2>/dev/null || true
    if ! wait_until_gone 30; then
        echo "❌ Could not stop the running GoNhanh"
        exit 1
    fi
fi

# Keep the old copy until the new one is in place, so a failed copy can be rolled back.
BACKUP_DIR="$(mktemp -d)"
if [ -d "$DEST" ]; then
    mv "$DEST" "$BACKUP_DIR/GoNhanh.app"
fi
restore_backup() {
    rm -rf "$DEST"
    if [ -d "$BACKUP_DIR/GoNhanh.app" ]; then
        mv "$BACKUP_DIR/GoNhanh.app" "$DEST"
        open "$DEST" || true
        echo "↩️  Restored the previous GoNhanh"
    fi
}
if ! ditto "$SRC" "$DEST"; then
    echo "❌ Copying the new app failed"
    restore_backup
    exit 1
fi
if ! open "$DEST"; then
    echo "❌ Could not launch the new GoNhanh"
    restore_backup
    exit 1
fi

for _ in $(seq 1 50); do
    pgrep -f "$BINARY" > /dev/null 2>&1 && break
    sleep 0.1
done
if ! pgrep -f "$BINARY" > /dev/null 2>&1; then
    echo "❌ The new GoNhanh did not start from $DEST"
    restore_backup
    exit 1
fi
rm -rf "$BACKUP_DIR"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist" 2>/dev/null || echo "?")
COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "?")
# The build may include uncommitted changes to the app or engine.
if [ -n "$(git -C "$PROJECT_ROOT" status --porcelain -- core platforms/macos 2>/dev/null)" ]; then
    COMMIT="$COMMIT+uncommitted changes"
fi
echo "✅ Installed GoNhanh $VERSION ($COMMIT) and relaunched it"
if codesign -dv "$DEST" 2>&1 | grep -q "Signature=adhoc"; then
    echo "⚠️  Ad-hoc signed: re-enable GoNhanh in System Settings > Privacy & Security > Accessibility."
fi
