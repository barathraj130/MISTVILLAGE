#!/bin/sh
# Every script parsed as the game loads them (a short headless start of the city): parse and type errors printed.
# (--check-only misses ":= of an untyped value"; this doesn't.)   sh tools/dev/gdcheck.sh
cd "$(dirname "$0")/../.." && /Applications/Godot.app/Contents/MacOS/Godot --headless --audio-driver Dummy --path godot \
	res://scenes/city_test.tscn --quit-after 30 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" -A1 | head -20
