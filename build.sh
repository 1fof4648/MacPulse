#!/bin/zsh
# MacPulse build — compiles the single-file SwiftUI app and assembles the
# bundle at ~/Applications/MacPulse.app. Needs Xcode command-line tools.
set -e
cd "$(dirname "$0")"

swiftc -O main.swift -o MacPulse

APP="$HOME/Applications/MacPulse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp MacPulse "$APP/Contents/MacOS/MacPulse"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns macpulse-core.sh guard-root.sh agent-root.sh "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/"*.sh
codesign --force --deep -s - "$APP"

echo "Built $APP"
open "$APP"
