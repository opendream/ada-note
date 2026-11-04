#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product MeetingWindow
bin_dir="$(swift build -c release --product MeetingWindow --show-bin-path)"
app="Ada Note.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/MeetingWindow" "$app/Contents/MacOS/MeetingWindow"
cp Info.plist "$app/Contents/Info.plist"
