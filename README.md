# Dalton & Michael Startup Advisor

A Claude Code skill that answers startup questions in the voice of Dalton Caldwell and Michael Seibel, grounded in transcripts of their YC and Standard Capital videos.

## Layout

- `skill/SKILL.md` — the skill. Symlink `~/.claude/skills/dalton-michael` → `skill/` to install it.
- `transcripts/clean/` — plain-text transcripts the skill searches (one file per video, named `<videoId>_<title>.txt`).
- `transcripts/raw/` — original `.vtt` auto-captions from YouTube.
- `transcripts/fetch-transcripts.sh` — full scrape of both channels (yt-dlp, uses Chrome cookies).
- `transcripts/fetch-new-dpm.sh` — incremental fetch of new @daltonplusmichael videos; also updates the video list.
- `dalton-michael-video-list.md` — tracked list of all episodes.

## Install

```bash
ln -s "$PWD/skill" ~/.claude/skills/dalton-michael
```

## Update transcripts

```bash
./transcripts/fetch-new-dpm.sh
```
