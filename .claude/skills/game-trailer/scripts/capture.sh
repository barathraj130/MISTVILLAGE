#!/bin/zsh
# Record one clip of the game with Godot's Movie Maker (real rendered frames at a fixed 30 fps, however slowly the
# machine draws them, plus the game's own sound).
#
#   capture.sh OUT_DIR NAME SECONDS [WxH] -- <args for the game after "--">
#
# e.g. capture.sh trailer/clips rain_drive 30 1920x1080 -- --testdrive --weather=rain
#      capture.sh trailer/clips day3_court 40 -- --story --storyskip --storyfrom=212 --storystop=230
#
# Writes OUT_DIR/NAME.avi (MJPEG + PCM), OUT_DIR/NAME.log, and OUT_DIR/NAME.mark if the game printed
# "TRAILER_MARK frame=N" (the moment the shot is ready, e.g. --flyover once the city has loaded): the editor cuts
# from there. SECONDS caps the clip (--quit-after); a mode that quits by itself (--flyover) may end sooner.
set -e
out=$1; name=$2; secs=$3; shift 3
size=1920x1080
if [[ "$1" != "--" ]]; then size=$1; shift; fi
[[ "$1" == "--" ]] && shift
root=${GAME_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
godot=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
scene=${SCENE:-scenes/city_test.tscn}
mkdir -p "$out"
out=$(cd "$out" && pwd)
frames=$(( secs * 30 + 30 ))
echo "capturing $name: ${secs}s at $size → $out/$name.avi"
perl -e "alarm $(( secs * 40 + 600 )); exec @ARGV" "$godot" --path "$root/godot" --resolution "$size" \
  --fixed-fps 30 --write-movie "$out/$name.avi" --quit-after $frames "$scene" -- "$@" > "$out/$name.log" 2>&1 || true
grep -o 'TRAILER_MARK frame=[0-9]*' "$out/$name.log" | head -1 | sed 's/.*=//' > "$out/$name.mark" || true
[[ -s "$out/$name.mark" ]] || rm -f "$out/$name.mark"
if grep -q 'SCRIPT ERROR' "$out/$name.log"; then
  echo "warning: script errors in $out/$name.log:"; grep -A1 'SCRIPT ERROR' "$out/$name.log" | head -6
fi
ls -lh "$out/$name.avi"
