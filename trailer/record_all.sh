#!/bin/zsh
# The clips for the GTA-style cut (game-trailer skill). One at a time: Godot instances fight over the GPU.
cd "$(dirname "$0")/.."
C=trailer/clips
cap() {                                  # (resumable: a clip already recorded is skipped)
  [[ -f $C/$2.done ]] && return
  .claude/skills/game-trailer/scripts/capture.sh "$@" && touch $C/$2.done
}
cap $C fly_dusk_high 22 -- --nohud --clock=17:50 --flyover=-160,520,420,-25,-14,80,490,-120,12,-8,14
cap $C fly_dusk_low 22 -- --nohud --clock=17:55 --flyover=60,462,260,15,-9,20,456,-160,-5,-6,14
cap $C drive_dusk 45 -- --nohud --testdrive --long --clock=18:05
cap $C drive_rain_night 45 -- --nohud --testdrive --long --weather=rain --clock=19:40
for lang in en ta; do
  ta=(); [[ $lang == ta ]] && ta=(--storyta)
  cap $C funeral_$lang 45 -- --nohud --story --storyskip --storyfrom=89 --storystop=96 $ta
  cap $C watchman_$lang 35 -- --nohud --story --storyskip --storyfrom=104 --storystop=106 $ta
  cap $C gate_$lang 35 -- --nohud --story --storyskip --storyfrom=168 --storystop=170 $ta
  cap $C chase_$lang 50 -- --nohud --story --storyskip --storyfrom=381 --storystop=383 $ta
  cap $C suresh_$lang 45 -- --nohud --story --storyskip --storyfrom=460 --storystop=466 $ta
  cap $C court_$lang 45 -- --nohud --story --storyskip --storyfrom=541 --storystop=546 $ta
  cap $C station_$lang 35 -- --nohud --story --storyskip --storyfrom=88 --storystop=89 $ta
done
echo ALL_DONE

