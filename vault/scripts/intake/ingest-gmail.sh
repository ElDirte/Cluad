#!/usr/bin/env bash
# Ingests Gmail exports (.eml or Google Takeout .mbox) from the drop folder into 00-inbox/gmail/
# For Google Takeout: download mail as .mbox, place in $GMAIL_EXPORT_DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

SRC_DIR="${GMAIL_EXPORT_DIR:-$HOME/Downloads/gmail-exports}"
DEST_DIR="$VAULT_ROOT/00-inbox/gmail"
LOG_FILE="$VAULT_ROOT/logs/intake.log"
MANIFEST="$VAULT_ROOT/data/gmail-ingested.txt"

mkdir -p "$DEST_DIR" "$VAULT_ROOT/logs" "$VAULT_ROOT/data"
touch "$MANIFEST"

if [ ! -d "$SRC_DIR" ]; then
  echo "[ingest-gmail] Export folder not found: $SRC_DIR — skipping"
  echo "[ingest-gmail] To use: export Gmail via Google Takeout, place .mbox or .eml files in $SRC_DIR"
  exit 0
fi

ingested=0

# Process .eml files (individual emails)
find "$SRC_DIR" -name "*.eml" 2>/dev/null | while read -r eml; do
  file_hash=$(md5sum "$eml" | cut -d' ' -f1)
  grep -qF "$file_hash" "$MANIFEST" 2>/dev/null && continue

  file_date=$(date -r "$eml" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
  stem=$(basename "$eml" .eml | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  dest_path="$DEST_DIR/${file_date}_email_${stem:0:40}.md"

  {
    echo "---"
    echo "src: email"
    echo "date: $file_date"
    echo "original_file: $(basename "$eml")"
    echo "status: staged"
    echo "---"
    echo ""
    # Extract Subject + From + body (basic parse, no external deps)
    grep -m1 "^Subject:" "$eml" | sed 's/^Subject: /## /' || echo "## (no subject)"
    echo ""
    grep -m1 "^From:" "$eml" | sed 's/^/> /' || true
    echo ""
    # Body: skip headers (blank line separates headers from body in .eml)
    awk '/^$/{found=1; next} found{print}' "$eml" | head -200
  } > "$dest_path"

  echo "$file_hash  $eml" >> "$MANIFEST"
  echo "$(date -Iseconds) INGEST email $dest_path" >> "$LOG_FILE"
  echo "[ingest-gmail] $(basename "$dest_path")"
  ingested=$((ingested + 1))
done

# Process .mbox (Google Takeout bulk export) — split into individual files
find "$SRC_DIR" -name "*.mbox" 2>/dev/null | while read -r mbox; do
  file_hash=$(md5sum "$mbox" | cut -d' ' -f1)
  grep -qF "$file_hash" "$MANIFEST" 2>/dev/null && { echo "[ingest-gmail] $mbox already processed"; continue; }

  echo "[ingest-gmail] Splitting mbox: $(basename "$mbox") ..."
  python3 - "$mbox" "$DEST_DIR" <<'PYEOF'
import sys, mailbox, hashlib, re
from pathlib import Path
from datetime import datetime

mbox_path, dest = sys.argv[1], Path(sys.argv[2])
mb = mailbox.mbox(mbox_path)
count = 0
for msg in mb:
    subj = str(msg.get('Subject', 'no-subject'))
    date_str = str(msg.get('Date', ''))
    try:
        from email.utils import parsedate_to_datetime
        dt = parsedate_to_datetime(date_str).strftime('%Y-%m-%d')
    except:
        dt = datetime.now().strftime('%Y-%m-%d')
    slug = re.sub(r'[^a-z0-9-]', '-', subj.lower())[:40].strip('-')
    uid = hashlib.md5((subj + date_str).encode()).hexdigest()[:8]
    dest_file = dest / f"{dt}_email_{slug}_{uid}.md"
    if dest_file.exists():
        continue
    payload = msg.get_payload(decode=False)
    if isinstance(payload, list):
        body = '\n'.join(p.get_payload(decode=True).decode('utf-8','ignore')[:1000]
                        for p in payload if hasattr(p,'get_payload'))
    else:
        body = str(payload or '')[:2000]
    dest_file.write_text(
        f"---\nsrc: email\ndate: {dt}\nsubject: \"{subj[:80]}\"\nfrom: \"{msg.get('From','')}\"\nstatus: staged\n---\n\n## {subj}\n\n{body}\n"
    )
    count += 1
print(f"[ingest-gmail] Extracted {count} emails from {mbox_path}")
PYEOF

  echo "$file_hash  $mbox" >> "$MANIFEST"
  echo "$(date -Iseconds) INGEST mbox $mbox" >> "$LOG_FILE"
done

echo "[ingest-gmail] Done."
