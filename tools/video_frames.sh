#!/usr/bin/env bash
# Turns a technique video into contact sheets to read: frames at FPS, each stamped with its time,
# tiled COLSxROWS per sheet, plus the frames themselves for close looks.
#   tools/video_frames.sh clip.mp4 OUTDIR [FPS=2] [START=0] [DURATION=all] [COLS=5] [ROWS=4]
# Sheets land in OUTDIR/sheet_NN.jpg, frames in OUTDIR/frames/t_<seconds>.jpg. See
# docs/video-to-technique.md for how a sheet becomes a technique script.
set -euo pipefail
in="$1"; out="$2"; fps="${3:-2}"; start="${4:-0}"; dur="${5:-}"; cols="${6:-5}"; rows="${7:-4}"
mkdir -p "$out/frames"
range=(-ss "$start"); [ -n "$dur" ] && range+=(-t "$dur")
font=$(fc-match -f '%{file}' sans 2>/dev/null || true)
stamp="drawtext=text='%{pts\:hms\:$start}':x=6:y=6:fontsize=20:fontcolor=yellow:box=1:boxcolor=black@0.6"
[ -n "$font" ] && stamp="drawtext=fontfile=$font:text='%{pts\:hms\:$start}':x=6:y=6:fontsize=20:fontcolor=yellow:box=1:boxcolor=black@0.6"
ffmpeg -v error -y "${range[@]}" -i "$in" -vf "fps=$fps,scale=480:-2,$stamp" -q:v 3 "$out/frames/f_%05d.jpg"
# Rename by time so a frame can be found from the stamp on the sheet.
i=0; for f in "$out"/frames/f_*.jpg; do
  t=$(awk -v s="$start" -v i="$i" -v r="$fps" 'BEGIN{printf "%07.2f", s + i / r}'); mv "$f" "$out/frames/t_$t.jpg"; i=$((i+1)); done
ffmpeg -v error -y -pattern_type glob -i "$out/frames/t_*.jpg" -vf "scale=384:-2,tile=${cols}x${rows}:padding=4:color=white" -q:v 3 "$out/sheet_%02d.jpg"
ls "$out"/sheet_*.jpg
