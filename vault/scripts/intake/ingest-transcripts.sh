#!/usr/bin/env bash
# Picks up .txt / .vtt / .srt transcript files from the drop folder and moves them to 00-inbox/transcripts/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

DROP_DIR="${TRANSCRIPT_DROP_DIR:-$HOME/Downloads/transcripts}"
DEST_DIR="$VAULT_ROOT/00-inbox/transcripts"
LOG_FILE="$VAULT_ROOT/logs/intake.log"

mkdir -p "$DEST_DIR" "$VAULT_ROOT/logs"

if [ ! -d "$DROP_DIR" ]; then
  echo "[ingest-transcripts] Drop folder not found: $DROP_DIR — skipping"
  exit 0
fi

ingested=0

find "$DROP_DIR" -maxdepth 1 \( -name "*.txt" -o -name "*.vtt" -o -name "*.srt" -o -name "*.md" \) | while read -r f; do
  filename=$(basename "$f")
  ext="${filename##*.}"
  stem="${filename%.*}"
  file_date=$(date -r "$f" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
  line_count=$(wc -l < "$f" 2>/dev/null || echo "0")

  # Build dest filename
  dest_name="${file_date}_transcript_${stem}.${ext}"
  dest_path="$DEST_DIR/$dest_name"

  # If dest already exists, skip
  [ -f "$dest_path" ] && continue

  # Prepend frontmatter then copy content
  {
    echo "---"
    echo "src: transcript"
    echo "date: $file_date"
    echo "original_name: $filename"
    echo "line_count: $line_count"
    echo "status: staged"
    echo "---"
    echo ""
    cat "$f"
  } > "$dest_path"

  echo "$(date -Iseconds) INGEST transcript $dest_path" >> "$LOG_FILE"
  echo "[ingest-transcripts] $dest_name ($line_count lines)"
  ingested=$((ingested + 1))
done

echo "[ingest-transcripts] Done. New transcripts from $DROP_DIR"
