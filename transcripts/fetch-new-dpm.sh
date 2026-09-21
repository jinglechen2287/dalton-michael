#!/bin/bash
# Fetch NEW Dalton + Michael podcast videos and transcripts from @daltonplusmichael
# Checks what's already downloaded, only grabs new ones

set -e

export PATH="$PATH:/Users/jingle/Library/Python/3.9/bin"

DIR="/Users/jingle/Projects/dalton-michael/transcripts"
RAW_DIR="$DIR/raw"
CLEAN_DIR="$DIR/clean"
mkdir -p "$RAW_DIR" "$CLEAN_DIR"

echo "=== Checking @daltonplusmichael for new videos ==="

# Get current video list from channel (ID only, one per line)
yt-dlp --cookies-from-browser chrome --flat-playlist --print "%(id)s" \
  "https://www.youtube.com/@daltonplusmichael/videos" 2>/dev/null \
  > "$DIR/dpm_latest_ids.txt" || { echo "Failed to scrape channel"; exit 1; }

TOTAL=$(wc -l < "$DIR/dpm_latest_ids.txt" | tr -d ' ')
echo "Channel has $TOTAL videos"

# Build set of already-downloaded video IDs from clean/ filenames.
# YouTube IDs are exactly 11 chars of [A-Za-z0-9_-]; take that prefix rather than
# splitting on a separator (BSD sed treats \t in a bracket as literal '\' and 't').
EXISTING_IDS=$(ls "$CLEAN_DIR" 2>/dev/null | sed -E 's/^([A-Za-z0-9_-]{11}).*/\1/' | sort -u)

# Find new videos
NEW=0
while read -r vid; do
  # Skip if this video ID already exists in clean/
  if echo "$EXISTING_IDS" | grep -q "^${vid}$"; then
    continue
  fi

  # Get title for display
  title=$(yt-dlp --cookies-from-browser chrome --print "%(title)s" \
    "https://www.youtube.com/watch?v=$vid" 2>/dev/null || echo "Unknown")

  NEW=$((NEW + 1))
  echo ""
  echo "[NEW] $title ($vid)"

  # Download auto-generated English subtitles
  yt-dlp \
    --cookies-from-browser chrome \
    --write-auto-sub \
    --sub-lang "en" \
    --skip-download \
    --no-warnings \
    -o "$RAW_DIR/${vid}_%(title)s.%(ext)s" \
    "https://www.youtube.com/watch?v=$vid" 2>/dev/null && {
      echo "  -> subtitles downloaded"
    } || {
      echo "  -> FAILED (no captions?)"
      continue
    }

  # Clean the .vtt to plain text
  for vtt_file in "$RAW_DIR"/${vid}*.vtt; do
    [ -f "$vtt_file" ] || continue
    basename=$(basename "$vtt_file" .en.vtt)
    out_file="$CLEAN_DIR/${basename}.txt"

    python3 -c "
import sys, re

with open(sys.argv[1], 'r') as f:
    content = f.read()

content = re.sub(r'WEBVTT\n.*?\n\n', '', content, count=1, flags=re.DOTALL)
content = re.sub(r'\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}.*\n', '', content)
content = re.sub(r'<[^>]+>', '', content)
lines = [l.strip() for l in content.split('\n') if l.strip()]
deduped = []
for line in lines:
    if not deduped or line != deduped[-1]:
        deduped.append(line)
print(' '.join(deduped))
" "$vtt_file" > "$out_file"

    echo "  -> cleaned: $(basename "$out_file")"
  done

done < "$DIR/dpm_latest_ids.txt"

# --- Update the markdown tracking list ---

VIDEO_LIST="/Users/jingle/Projects/dalton-michael/dalton-michael-video-list.md"

if [ "$NEW" -gt 0 ] && [ -f "$VIDEO_LIST" ]; then
  echo ""
  echo "=== Updating video list ==="

  # Get current highest episode number in section B only (the file has other tables after it)
  LAST_NUM=$(sed -n '/^## B\. "Dalton + Michael"/,/^Note: May have/p' "$VIDEO_LIST" \
    | grep -E '^\| [0-9]+ \|' | tail -1 | awk -F'|' '{print $2}' | tr -d ' ')
  LAST_NUM=${LAST_NUM:-0}

  # Channel listing is newest-first; section B is chronological, so walk it in reverse.
  # Only list videos whose transcript actually landed in clean/.
  while read -r vid; do
    if echo "$EXISTING_IDS" | grep -q "^${vid}$"; then
      continue
    fi
    ls "$CLEAN_DIR"/"${vid}"* >/dev/null 2>&1 || continue

    LAST_NUM=$((LAST_NUM + 1))
    info=$(yt-dlp --cookies-from-browser chrome --print "%(title)s" --print "%(upload_date)s" \
      "https://www.youtube.com/watch?v=$vid" 2>/dev/null || printf "Unknown\n00000000")
    vtitle=$(echo "$info" | sed -n '1p')
    raw_date=$(echo "$info" | sed -n '2p')

    # Format date from YYYYMMDD to Mon DD, YYYY
    if command -v gdate &>/dev/null; then
      fdate=$(gdate -d "$raw_date" "+%b %-d, %Y" 2>/dev/null || echo "$raw_date")
    else
      fdate=$(date -j -f "%Y%m%d" "$raw_date" "+%b %-d, %Y" 2>/dev/null || echo "$raw_date")
    fi

    # Insert new row before the "Note:" line in section B
    sed -i '' "/^Note: May have/i\\
| ${LAST_NUM} | ${vtitle} | ${fdate} |
" "$VIDEO_LIST"

    echo "  Added to list: $vtitle ($fdate)"
  done < <(tail -r "$DIR/dpm_latest_ids.txt")

  # Update episode count in section B header
  sed -i '' "s/## B\. \"Dalton + Michael\" (Standard Capital era) -- [0-9]*+ episodes/## B. \"Dalton + Michael\" (Standard Capital era) -- ${LAST_NUM}+ episodes/" "$VIDEO_LIST"
fi

if [ "$NEW" -eq 0 ]; then
  echo "No new videos found."
else
  echo ""
  echo "=== Fetched $NEW new transcript(s) ==="
fi

# --- Commit and push to GitHub so the remote stays current ---

REPO_DIR="/Users/jingle/Projects/dalton-michael"

if [ -d "$REPO_DIR/.git" ] && [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  echo ""
  echo "=== Committing and pushing to GitHub ==="
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -q -m "Update transcripts: $NEW new video(s) ($(date '+%Y-%m-%d'))"
  git -C "$REPO_DIR" push -q origin HEAD && echo "  -> pushed" || echo "  -> PUSH FAILED (commit is local; will retry next run)"
fi
