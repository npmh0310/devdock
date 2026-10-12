#!/bin/bash
# One-step install: checks requirements, builds DevDock from source, installs it to ~/Applications.
# Usage: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

fail() { echo "✗ $1" >&2; exit 1; }
ok() { echo "✓ $1"; }

macos_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$macos_major" -ge 15 ] || fail "DevDock needs macOS 15 or newer (this Mac has $(sw_vers -productVersion))."
ok "macOS $(sw_vers -productVersion)"

# Command Line Tools alone can't build apps; the full Xcode is required.
xcodebuild -version >/dev/null 2>&1 \
    || fail "Xcode is required. Install it from the App Store, open it once, then run: sudo xcode-select -s /Applications/Xcode.app"
xcode_major=$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)
[ "$xcode_major" -ge 26 ] || fail "DevDock needs Xcode 26 or newer (Swift 6.2); found $(xcodebuild -version | head -1)."
ok "$(xcodebuild -version | head -1)"

if ! command -v xcodegen >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || fail "XcodeGen is required. Install Homebrew (https://brew.sh) or XcodeGen, then rerun."
    echo "→ Installing XcodeGen with Homebrew…"
    brew install xcodegen
fi
ok "XcodeGen $(xcodegen --version 2>/dev/null | awk '{print $NF}')"

echo "→ Building DevDock (first build fetches Swift packages, takes a minute)…"
make install

cat <<'MSG'

✓ DevDock is running. Look for it in the menu bar (top right).
  • Can't see it? A crowded menu bar hides items behind the notch: hold ⌘ and drag
    other icons, or press ⌃⌥D to open the panel.
  • Allow notifications when macOS asks, to hear when an AI quota runs low or resets.
  • It starts at login automatically; turn that off in DevDock › Settings.
MSG
