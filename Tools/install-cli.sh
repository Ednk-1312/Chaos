#!/bin/bash
# Builds the Chaos CLI in release mode and installs it as
# Chaos.app/Contents/Helpers/chaos (a separate folder avoids the case-insensitive
# collision with the GUI binary named Chaos), giving `chaos` GUI-independent
# access to the same experiment engine.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product chaos
BIN=".build/release/chaos"

APP="build/Debug/Chaos.app/Contents/Helpers"
mkdir -p "$APP"
cp "$BIN" "$APP/chaos"
chmod +x "$APP/chaos"

echo "CLI installed at $APP/chaos"
echo "Install on PATH with: sudo cp $APP/chaos /usr/local/bin/chaos"
