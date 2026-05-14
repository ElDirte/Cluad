"""
File analyzer — uses Ollama vision (llava:7b) for images and Claude for text/docs.
Reads files directly from the filesystem. Returns structured analysis for each item.
"""

import base64
import re
from datetime import datetime
from pathlib import Path
from typing import Optional

import anthropic

from config import OLLAMA_API_URL, VISION_MODEL, ANTHROPIC_API_KEY, CONFIDENCE_THRESHOLDS

import requests

_claude = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

IMAGE_EXTS = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic", "avif", "svg"}
VIDEO_EXTS = {"mp4", "mov", "avi", "mkv", "webm"}
DOC_EXTS = {"pdf", "docx", "doc", "txt", "md", "rtf", "xlsx", "csv"}


def _read_file_bytes(path: str) -> Optional[bytes]:
    """Read raw bytes from the local filesystem for vision analysis."""
    try:
        return Path(path).read_bytes()
    except Exception:
        return None


def _analyze_image_with_ollama(image_bytes: bytes, filename: str) -> dict:
    """Send image to Ollama llava for vision analysis."""
    b64 = base64.b64encode(image_bytes).decode()
    prompt = (
        f"Analyze this image (filename: {filename}). Respond in this exact format:\n"
        "TYPE: photo/screenshot/diagram/artwork/meme/etc\n"
        "SUMMARY: one sentence describing what this is and why it was likely saved\n"
        "NAME: YYYY-MM-DD_topic_use_shortdesc (lowercase, hyphens, max 5 words in desc, no extension)\n"
        "TAGS: use:X, topic:X, src:X, q:X (3-5 tags using these prefixes only)\n"
        "QUALITY: keep/maybe/low\n"
        "CONFIDENCE: 0-100\n"
        "REASON: one sentence explaining your confidence level"
    )

    try:
        resp = requests.post(
            f"{OLLAMA_API_URL}/api/generate",
            json={"model": VISION_MODEL, "prompt": prompt, "images": [b64], "stream": False},
            timeout=60,
        )
        resp.raise_for_status()
        return {"raw": resp.json().get("response", ""), "source": "ollama_vision"}
    except Exception as e:
        return {"raw": "", "source": "ollama_vision", "error": str(e)}


def _analyze_with_claude(filename: str, ext: str, context: str = "") -> dict:
    """Use Claude to classify files or enrich analysis when vision isn't available."""
    prompt = (
        f"Analyze this file for a personal file catalog intake.\n"
        f"Filename: {filename}\n"
        f"File type: {ext}\n"
        f"Context: {context}\n\n"
        "Provide:\n"
        "1. Inferred type (screenshot/photo/diagram/document/reference/etc.)\n"
        "2. Short summary (1-2 sentences)\n"
        "3. Proposed filename (YYYY-MM-DD_topic_use_shortdesc format, no extension)\n"
        "4. Proposed tags (use prefixes: use:, topic:, src:, status:, q:, proj:)\n"
        "5. Quality rating: keep / maybe / low\n"
        "6. Confidence score 0-100\n"
        "7. Reasoning (1 sentence)\n\n"
        "Format exactly as:\n"
        "TYPE: ...\n"
        "SUMMARY: ...\n"
        "NAME: ...\n"
        "TAGS: tag1, tag2, tag3\n"
        "QUALITY: keep\n"
        "CONFIDENCE: 85\n"
        "REASON: ..."
    )

    try:
        msg = _claude.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=400,
            messages=[{"role": "user", "content": prompt}],
        )
        return {"raw": msg.content[0].text, "source": "claude"}
    except Exception as e:
        return {"raw": "", "source": "claude", "error": str(e)}


def _parse_structured_response(raw: str, filename: str, ext: str) -> dict:
    """Parse the structured text response into a clean dict."""
    lines = {}
    for line in raw.strip().split("\n"):
        if ":" in line:
            k, v = line.split(":", 1)
            lines[k.strip()] = v.strip()

    confidence_raw = lines.get("CONFIDENCE", "50").rstrip("%")
    try:
        confidence = int(re.sub(r"[^\d]", "", confidence_raw)) / 100.0
    except ValueError:
        confidence = 0.50

    tags_raw = lines.get("TAGS", "")
    tags = [t.strip() for t in tags_raw.split(",") if t.strip()]

    today = datetime.now().strftime("%Y-%m-%d")
    suggested_name = lines.get("NAME", f"{today}_unknown_file").strip()
    quality = lines.get("QUALITY", "maybe").strip().lower()
    if quality not in ("keep", "maybe", "low"):
        quality = "maybe"

    return {
        "original_name": filename,
        "ext": ext,
        "inferred_type": lines.get("TYPE", "unknown"),
        "summary": lines.get("SUMMARY", ""),
        "suggested_name": suggested_name,
        "suggested_tags": tags,
        "quality": quality,
        "confidence": confidence,
        "reasoning": lines.get("REASON", ""),
        "confidence_label": _confidence_label(confidence),
    }


def _confidence_label(score: float) -> str:
    if score >= CONFIDENCE_THRESHOLDS["auto_suggest"]:
        return "high"
    if score >= CONFIDENCE_THRESHOLDS["require_approval"]:
        return "medium"
    if score >= CONFIDENCE_THRESHOLDS["flag_uncertain"]:
        return "low"
    return "uncertain"


def analyze_item(item: dict) -> dict:
    """
    Full analysis pipeline for one file item.
    item: {path, name, ext, size, folder}
    Returns structured analysis dict ready for the approval table.
    """
    path = item.get("path", "")
    filename = item.get("name", "unknown")
    ext = item.get("ext", "").lower()

    raw_analysis: dict = {}

    if ext in IMAGE_EXTS:
        file_bytes = _read_file_bytes(path)
        if file_bytes:
            raw_analysis = _analyze_image_with_ollama(file_bytes, filename)

    if not raw_analysis.get("raw"):
        size = item.get("size", 0)
        context = f"size={size} bytes, folder={item.get('folder', '')}"
        raw_analysis = _analyze_with_claude(filename, ext, context)

    result = _parse_structured_response(raw_analysis.get("raw", ""), filename, ext)
    result["item_id"] = path  # file path is the unique identifier
    result["path"] = path
    result["analysis_source"] = raw_analysis.get("source", "unknown")

    if raw_analysis.get("error"):
        result["analysis_error"] = raw_analysis["error"]

    return result


def format_approval_table(analyses: list[dict]) -> str:
    """
    Format a batch of analyses as a markdown approval table for the chat UI.
    User responds with row numbers: 1y, 2n, 3edit, all-y, done.
    """
    header = (
        "**Intake Review** — respond with row numbers to approve/reject/edit:\n"
        "`1y` = approve | `1n` = reject | `1edit name=new-name tags=use:design-idea` = edit\n"
        "`all-y` = approve all high-confidence | `done` = finish this batch\n\n"
    )

    rows = []
    for i, a in enumerate(analyses, 1):
        conf_pct = int(a["confidence"] * 100)
        conf_icon = "🟢" if a["confidence_label"] == "high" else "🟡" if a["confidence_label"] == "medium" else "🔴"
        tags_str = ", ".join(a["suggested_tags"][:4]) or "none"
        rows.append(
            f"**{i}.** `{a['original_name']}.{a['ext']}`\n"
            f"   → **Name**: `{a['suggested_name']}`\n"
            f"   → **Quality**: {a.get('quality', '?')} | **Tags**: {tags_str}\n"
            f"   → {conf_icon} {conf_pct}% — {a['reasoning']}\n"
        )

    return header + "\n".join(rows)


def parse_approval_response(
    response: str, analyses: list[dict]
) -> tuple[list[dict], list[dict], list[str]]:
    """
    Parse user approval response into approved changes, rejected items, and messages.
    Returns: (approved_changes, rejected_items, messages)
    """
    response = response.strip().lower()
    approved: list[dict] = []
    rejected: list[dict] = []
    messages: list[str] = []

    if response == "all-y":
        for a in analyses:
            if a["confidence_label"] in ("high", "medium"):
                approved.append(_analysis_to_change(a))
            else:
                messages.append(f"Skipped `{a['original_name']}` (confidence too low for auto-approve)")
        return approved, rejected, messages

    # rejoin to handle multi-word edit commands, then re-split on row boundaries
    tokens = re.split(r"(?=\d+(?:y|n|edit))", response)

    for token in tokens:
        token = token.strip()
        row_match = re.match(r"^(\d+)(y|n|edit)(.*)", token, re.IGNORECASE)
        if not row_match:
            continue

        idx = int(row_match.group(1)) - 1
        action = row_match.group(2).lower()
        rest = row_match.group(3).strip()

        if idx < 0 or idx >= len(analyses):
            messages.append(f"Row {idx + 1} out of range")
            continue

        a = analyses[idx]
        if action == "y":
            approved.append(_analysis_to_change(a))
        elif action == "n":
            rejected.append({"item_id": a["item_id"], "original_name": a["original_name"]})
        elif action == "edit":
            change = _analysis_to_change(a)
            # parse name=... and tags=... overrides from rest of token
            name_match = re.search(r"name=([^\s]+)", rest)
            tags_match = re.search(r"tags=([^\s]+)", rest)
            if name_match:
                change["name"] = name_match.group(1)
            if tags_match:
                change["tags"] = [t.strip() for t in tags_match.group(1).split(",") if t.strip()]
            approved.append(change)
            messages.append(f"Row {idx + 1} edited before apply")

    return approved, rejected, messages


def _analysis_to_change(a: dict) -> dict:
    return {
        "path": a["path"],
        "name": a["suggested_name"],
        "tags": a["suggested_tags"],
        "annotation": a.get("summary", ""),
        "quality": a.get("quality", "maybe"),
        "confidence": a["confidence"],
        "analysis_source": a.get("analysis_source", "claude"),
    }
