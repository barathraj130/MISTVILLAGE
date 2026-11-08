#!/bin/zsh
# The clips for the narrated gameplay video (game-trailer skill). Resumable: a clip already done is skipped.
cd "$(dirname "$0")/../.."
C=trailer/clips
cap() { [[ -f $C/$2.done ]] && return; .claude/skills/game-trailer/scripts/capture.sh "$@" && touch $C/$2.done }
B=/private/tmp/claude-501/-Users-barathraj-Downloads-mist-village/0fe62673-1724-4b16-90fc-a7b0a40d7dd1/scratchpad/bailshots
# the city (no HUD: the world itself)
cap $C night_drive 45 -- --nohud --testdrive --long --clock=21:00
cap $C fly_night2 20 -- --clock=20:45 --flyover=-60,500,200,-15,-12,60,480,-60,10,-8,12
# its systems (HUD on: they show themselves)
cap $C police_check 45 -- --testdrive --long --police --clock=11:00
cap $C bail_evening 60 -- --bailtest=$B
cap $C crash_traffic 40 -- --crashtest
for lang in en ta; do
  ta=(); [[ $lang == ta ]] && ta=(--storyta)
  cap $C record_$lang 40 -- --story --storyskip --storyfrom=110 --storystop=112 $ta
  cap $C board_$lang 35 -- --story --storyskip --storyfrom=115 --storystop=116 $ta
  cap $C cctv_$lang 35 -- --story --storyskip --storyfrom=185 --storystop=186 $ta
  cap $C tea_$lang 35 -- --story --storyskip --storyfrom=107 --storystop=108 $ta
  cap $C ask_$lang 40 -- --story --storyskip --storyfrom=407 --storystop=409 $ta
  cap $C covert_$lang 40 -- --story --storyskip --storyfrom=520 --storystop=522 $ta
  cap $C gigs_$lang 40 -- --story --storyskip --storyfrom=54 --storystop=56 $ta
  cap $C home_$lang 35 -- --story --storyskip --storyfrom=15 --storystop=17 $ta
done
cp -n /private/tmp/claude-501/-Users-barathraj-Downloads-mist-village/0fe62673-1724-4b16-90fc-a7b0a40d7dd1/scratchpad/night/fly_night.* $C/ 2>/dev/null
echo ALL_DONE
