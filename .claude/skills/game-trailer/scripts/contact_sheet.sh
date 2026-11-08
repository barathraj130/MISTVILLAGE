#!/bin/zsh
# Contact sheets of a clip: one frame every STEP seconds (default 2), 4 across and 5 down, left to right, top to
# bottom, so the good moments can be picked without watching the whole clip. Tile k (from 0) on sheet n (from 1) is
# at (n-1)*20*STEP + k*STEP seconds (printed below). If the clip has a .mark, times start at the mark, as the edit's
# "from" does.
#   contact_sheet.sh CLIP.avi [STEP]   → CLIP.sheet01.jpg, CLIP.sheet02.jpg ...
set -e
clip=$1; step=${2:-2}
base=${clip%.*}
skip=0
[[ -s "$base.mark" ]] && skip=$(( $(cat "$base.mark") / 30.0 ))
rm -f "$base".sheet*.jpg(N)
ffmpeg -v error -y -ss $skip -i "$clip" -vf "fps=1/$step,scale=480:-2,pad=iw+6:ih+6:3:3:black,tile=4x5" "$base.sheet%02d.jpg"
for f in "$base".sheet*.jpg; do
  n=${${f##*sheet}%.jpg}
  echo "$f: tiles from $(( (n - 1) * 20 * step ))s, every ${step}s"
done
