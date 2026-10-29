#!/usr/bin/env bash
# Slowed + reverb façon YouTube : ralenti "vinyle" (tempo et tonalité baissent ensemble)
# + reverb à convolution (salle) mélangée au son sec, puis limiteur pour éviter l'écrêtage.
# Usage : tools/slowed_reverb.sh entree.(mp3|wav|flac|m4a) sortie.mp3 [vitesse=0.85] [reverb_mix=0.35]
set -euo pipefail
in="$1"; out="$2"; speed="${3:-0.85}"; mix="${4:-0.35}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Réponse impulsionnelle stéréo synthétique : bruit filtré à décroissance exponentielle (~2,8 s)
ffmpeg -v error -f lavfi -i "anoisesrc=d=3:c=pink:r=44100:a=0.5:s=1" \
       -f lavfi -i "anoisesrc=d=3:c=pink:r=44100:a=0.5:s=2" \
       -filter_complex "[0][1]amerge=inputs=2,volume='exp(-2.3*t)':eval=frame,\
lowpass=f=7000,highpass=f=200,afade=t=in:d=0.02[ir]" -map "[ir]" -ac 2 "$tmp/ir.wav"

sr=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$in")
# 1) Ralenti seul (fichier intermédiaire sans perte)
ffmpeg -v error -y -i "$in" -af "aformat=sample_fmts=fltp:channel_layouts=stereo,asetrate=${sr}*${speed},aresample=44100" \
  -c:a pcm_f32le "$tmp/slow.wav"
# 2) Partie "reverb" seule (100 % mouillée)
ffmpeg -v error -y -i "$tmp/slow.wav" -i "$tmp/ir.wav" \
  -filter_complex "[0:a]adelay=25|25[d];[d][1:a]afir=dry=1:wet=1:length=1:gtype=gn,apad=pad_dur=3[w]" \
  -map "[w]" -c:a pcm_f32le "$tmp/wet.wav"
# 3) Mélange sec + reverb, limiteur à -1 dB, export MP3 320 kb/s
ffmpeg -v error -y -i "$tmp/slow.wav" -i "$tmp/wet.wav" -filter_complex \
  "[0:a][1:a]amix=inputs=2:duration=first:weights='1 ${mix}':normalize=0,alimiter=limit=0.89:level=false[o]" \
  -map "[o]" -c:a libmp3lame -b:a 320k -ar 44100 -id3v2_version 3 "$out"
