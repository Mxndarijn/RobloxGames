#!/usr/bin/env bash
# Assembles the store-page video from captured frame folders (see README.md, "Re-render").
#   bash render.sh <clips-dir> <out-dir>
# <clips-dir> holds one folder of f0000.jpg... frames per shot (s1 s2 s3 s4 s6), captured at 30 fps.
set -euo pipefail
CLIPS=${1:?clips dir}; OUT=${2:?out dir}
FONT_SRC=${FONT_SRC:-C:/Windows/Fonts/seguibl.ttf}  # Segoe UI Black
TMP=$(mktemp -d); if command -v cygpath >/dev/null; then TMP=$(cygpath -m "$TMP"); fi
# shot  first-frame  last-frame  caption
SHOTS=(
  "s1 0 107 STEAL rare slimes"
  "s2 8 95 Catch wild slimes"
  "s3 0 107 Collect Divine and Rainbow slimes"
  "s4 0 107 Merge for rarer slimes"
  "s6 0 125 "
)
seg() { # name first last caption captioned(0/1)
  local name=$1 a=$2 b=$3 cap=$4 withcap=$5 n=$(( $3 - $2 + 1 )) vf
  vf="scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,setsar=1"
  if [ "$withcap" = 1 ] && [ -n "$cap" ]; then
    printf '%s' "$cap" > "$TMP/$name.txt"
    vf="$vf,drawtext=fontfile=font.ttf:textfile=$name.txt:fontsize=84:fontcolor=white:borderw=7:bordercolor=0x10302a:x=(w-text_w)/2:y=h-200:alpha='min(1,t/0.25)'"
  fi
  if [ "$withcap" = 1 ] && [ "$name" = s6 ]; then
    printf 'STEAL A SLIME' > "$TMP/title.txt"
    vf="$vf,drawtext=fontfile=font.ttf:textfile=title.txt:fontsize=150:fontcolor=white:borderw=10:bordercolor=0x10302a:x=(w-text_w)/2:y=(h-text_h)/2-60:alpha='min(1,max(0,(t-1.6)/0.5))'"
  fi
  (cd "$TMP" && ffmpeg -y -loglevel error -framerate 30 -start_number "$a" -i "$CLIPS/$name/f%04d.jpg" -frames:v "$n" -vf "$vf" \
    -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -r 30 "$name-$withcap.mp4")
  echo "file '$TMP/$name-$withcap.mp4'" >> "$TMP/list-$withcap.txt"
}
cp "$FONT_SRC" "$TMP/font.ttf"
case "$CLIPS" in /*|?:*) ;; *) CLIPS="$PWD/$CLIPS" ;; esac
for withcap in 1 0; do
  for s in "${SHOTS[@]}"; do set -- $s; seg "$1" "$2" "$3" "${*:4}" "$withcap"; done
done
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list-1.txt" -c copy -movflags +faststart "$OUT/steal-a-slime-store-video-draft.mp4"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list-0.txt" -c copy -movflags +faststart "$OUT/steal-a-slime-store-video-draft-nocaptions.mp4"
rm -rf "$TMP"
ls -la "$OUT"/*.mp4
