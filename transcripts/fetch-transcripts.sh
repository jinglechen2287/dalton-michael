#!/bin/bash
# Fetch Dalton & Michael transcripts from YouTube via yt-dlp
# Usage: ./fetch-transcripts.sh

set -e

export PATH="$PATH:/Users/jingle/Library/Python/3.9/bin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAW_DIR="$SCRIPT_DIR/raw"
CLEAN_DIR="$SCRIPT_DIR/clean"
mkdir -p "$RAW_DIR" "$CLEAN_DIR"

# --- Step 1: Scrape video IDs from both channels ---

echo "=== Scraping YC channel for Dalton/Michael videos ==="
yt-dlp --cookies-from-browser chrome --flat-playlist --print "%(id)s\t%(title)s" \
  "https://www.youtube.com/@ycombinator/videos" 2>/dev/null \
  | grep -iE "dalton|michael|seibel" > "$SCRIPT_DIR/yc_videos.tsv" || true
echo "Found $(wc -l < "$SCRIPT_DIR/yc_videos.tsv" | tr -d ' ') videos from YC channel"

echo ""
echo "=== Scraping @daltonplusmichael channel ==="
yt-dlp --cookies-from-browser chrome --flat-playlist --print "%(id)s\t%(title)s" \
  "https://www.youtube.com/@daltonplusmichael/videos" 2>/dev/null \
  > "$SCRIPT_DIR/dpm_videos.tsv" || true
echo "Found $(wc -l < "$SCRIPT_DIR/dpm_videos.tsv" | tr -d ' ') videos from Dalton + Michael channel"

# Combine into one list (deduplicate by video ID)
cat "$SCRIPT_DIR/yc_videos.tsv" "$SCRIPT_DIR/dpm_videos.tsv" \
  | sort -t$'\t' -k1,1 -u > "$SCRIPT_DIR/all_videos.tsv"

TOTAL=$(wc -l < "$SCRIPT_DIR/all_videos.tsv" | tr -d ' ')
echo ""
echo "=== Total unique videos to process: $TOTAL ==="
echo ""

# --- Step 2: Download subtitles for each video ---

COUNT=0
FAILED=""

while IFS=$'\t' read -r vid title; do
  COUNT=$((COUNT + 1))
  # Sanitize title for filename
  safe_title=$(echo "$title" | sed 's/[^a-zA-Z0-9 _-]//g' | sed 's/  */ /g' | head -c 100)

  echo "[$COUNT/$TOTAL] $title"

  # Skip if already downloaded
  if ls "$RAW_DIR"/"$vid"*.vtt 1>/dev/null 2>&1; then
    echo "  -> already downloaded, skipping"
    continue
  fi

  # Download auto-generated English subtitles only (no video)
  yt-dlp \
    --cookies-from-browser chrome \
    --write-auto-sub \
    --sub-lang "en" \
    --skip-download \
    --no-warnings \
    -o "$RAW_DIR/${vid}_%(title)s.%(ext)s" \
    "https://www.youtube.com/watch?v=$vid" 2>/dev/null || {
      echo "  -> FAILED"
      FAILED="$FAILED\n$vid\t$title"
    }
done < "$SCRIPT_DIR/all_videos.tsv"

# --- Step 3: Convert .vtt to clean plain text ---

echo ""
echo "=== Cleaning transcripts ==="

for vtt_file in "$RAW_DIR"/*.vtt; do
  [ -f "$vtt_file" ] || continue

  basename=$(basename "$vtt_file" .en.vtt)
  out_file="$CLEAN_DIR/${basename}.txt"

  # Strip VTT headers, timestamps, positioning, and deduplicate lines
  python3 -c "
import sys, re

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Remove WEBVTT header and metadata
content = re.sub(r'WEBVTT\n.*?\n\n', '', content, count=1, flags=re.DOTALL)
# Remove timestamp lines
content = re.sub(r'\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}.*\n', '', content)
# Remove positioning tags
content = re.sub(r'<[^>]+>', '', content)
# Remove blank lines and deduplicate consecutive identical lines
lines = [l.strip() for l in content.split('\n') if l.strip()]
deduped = []
for line in lines:
    if not deduped or line != deduped[-1]:
        deduped.append(line)

print(' '.join(deduped))
" "$vtt_file" > "$out_file"

  echo "  Cleaned: $(basename "$out_file")"
done

# --- Summary ---

CLEAN_COUNT=$(ls "$CLEAN_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "=== Done ==="
echo "Raw subtitles: $RAW_DIR/"
echo "Clean transcripts: $CLEAN_DIR/"
echo "Total transcripts: $CLEAN_COUNT"

if [ -n "$FAILED" ]; then
  echo ""
  echo "=== Failed videos (no captions available): ==="
  echo -e "$FAILED"
fi
