"""
File analyzer — uses Ollama vision (llava:7b) for images and Claude for text/docs.
Returns structured analysis for each Eagle item.
"""

import base64
import re
from datetime import datetime
from typing import Optional
import requests
import anthropic

from config import OLLAMA_API_URL, VISION_MODEL, ANTHROPIC_API_KEY, CONFIDENCE_THRESHOLDS

_claude = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

IMAGE_EXTS = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic", "avif", "svg"}
VIDEO_EXTS = {"mp4", "mov", "avi", "mkv", "webm"}
DOC_EXTS = {"pdf", "docx", "doc", "txt", "md", "rtf", "xlsx", "csv"}


def _fetch_thumbnail_bytes(item: dict) -> Optional[bytes]:
    """Fetch thumbnail bytes from Eagle for vision analysis."""
    from tools.eagle_api import thumbnail_url
    url = thumbnail_url(item)
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            return resp.content
    except Exception:
        pass
    return None


def _analyze_image_with_ollama(image_bytes: bytes, filename: str) -> dict:
    """Send image to Ollama llava for vision analysis."""
    b64 = base64.b64encode(image_bytes).decode()
    prompt = (
        f"Analyze this image (filename: {filename}). Describe:\n"
        "1. What is shown in the image (objects, scene, people, text, UI elements, etc.)\n"
        "2. What type of image is it (photo, screenshot, diagram, artwork, meme, etc.)\n"
        "3. What was this likely saved for (design reference, memory, reminder, AI reference, "
        "project material, research, personal archive, inspiration)?\n"
        "4. Suggest a short descriptive filename (no extension, lowercase, hyphens only, max 5 words)\n"
        "5. Suggest 3-5 tags using these prefixes: use:, topic:, src:, q:\n"
        "Be concise. Format as: TYPE | SUMMARY | SUGGESTED_NAME | TAGS | CONFIDENCE(0-100)"
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
    """Use Claude to classify non-image files or enrich image analysis."""
    prompt = (
        f"Analyze this file for an Eagle asset library intake.\n"
        f"Filename: {filename}\n"
        f"File type: {ext}\n"
        f"Context: {context}\n\n"
        "Provide:\n"
        "1. Inferred type (screenshot/photo/diagram/document/reference/etc.)\n"
        "2. Short summary (1-2 sentences)\n"
        "3. Proposed filename (YYYY-MM-DD_topic_use_shortdesc format, no extension)\n"
        "4. Proposed tags (use prefixes: use:, topic:, src:, status:, q:, proj:)\n"
        "5. Suggested folder from: [26 Image Organization, Archer, Camera Roll, GroPhoTo, "
        "Ai_Tool_Diagrams, Art_Backgrounds, Work, Family, lookinto, idpics, Rabbit holes, "
        "Screenshots, Psilly, Garden Pics, Fandom, The Pile]\n"
        "6. Confidence score 0-100\n"
        "7. Reasoning (1 sentence)\n\n"
        "Format exactly as:\n"
        "TYPE: ...\n"
        "SUMMARY: ...\n"
        "NAME: ...\n"
        "TAGS: tag1, tag2, tag3\n"
        "FOLDER: ...\n"
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
    lines = {
        k.strip(): v.strip()
        for line in raw.strip().split("\n")
        if ":" in line
        for k, v in [line.split(":", 1)]
    }

    confidence_raw = lines.get("CONFIDENCE", "50").strip().rstrip("%")
    try:
        confidence = int(re.sub(r"[^\d]", "", confidence_raw)) / 100.0
    except ValueError:
        confidence = 0.50

    tags_raw = lines.get("TAGS", "")
    tags = [t.strip() for t in tags_raw.split(",") if t.strip()]

    today = datetime.now().strftime("%Y-%m-%d")
    suggested_name = lines.get("NAME", f"{today}_unknown_file").strip()

    return {
        "original_name": filename,
        "ext": ext,
        "inferred_type": lines.get("TYPE", "unknown"),
        "summary": lines.get("SUMMARY", ""),
        "suggested_name": suggested_name,
        "suggested_tags": tags,
        "suggested_folder": lines.get("FOLDER", "The Pile"),
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
    Full analysis pipeline for one Eagle item.
    Returns structured analysis dict ready for approval table.
    """
    filename = item.get("name", "unknown")
    ext = item.get("ext", "").lower()
    item_id = item.get("id", "")

    raw_analysis = {}

    if ext in IMAGE_EXTS:
        img_bytes = _fetch_thumbnail_bytes(item)
        if img_bytes:
            raw_analysis = _analyze_image_with_ollama(img_bytes, filename)

    if not raw_analysis.get("raw"):
        context = f"width={item.get('width')}, height={item.get('height')}, annotation={item.get('annotation', '')}"
        raw_analysis = _analyze_with_claude(filename, ext, context)

    result = _parse_structured_response(raw_analysis.get("raw", ""), filename, ext)
    result["item_id"] = item_id
    result["analysis_source"] = raw_analysis.get("source", "unknown")

    if raw_analysis.get("error"):
        result["analysis_error"] = raw_analysis["error"]

    return result


def format_approval_table(analyses: list[dict]) -> str:
    """
    Format a batch of analyses as a markdown approval table for the chat UI.
    User responds with: 1y 2n 3edit etc.
    """
    header = (
        "**Intake Review** — respond with row numbers to approve/reject/edit:\n"
        "`1y` = approve row 1 | `1n` = reject | `1edit name=new-name tags=use:design-idea` = edit\n"
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
            f"   → **Folder**: {a['suggested_folder']} | **Tags**: {tags_str}\n"
            f"   → {conf_icon} {conf_pct}% — {a['reasoning']}\n"
        )

    return header + "\n".join(rows)


def parse_approval_response(response: str, analyses: list[dict]) -> tuple[list[dict], list[dict], list[str]]:
    """
    Parse user approval response into approved, rejected, and messages.
    Returns: (approved_changes, rejected_items, messages)
    """
    response = response.strip().lower()
    approved = []
    rejected = []
    messages = []

    if response == "all-y":
        for a in analyses:
            if a["confidence_label"] in ("high", "medium"):
                approved.append(_analysis_to_change(a))
            else:
                messages.append(f"Skipped #{analyses.index(a)+1} (confidence too low for auto-approve)")
        return approved, rejected, messages

    for token in response.split():
        if not token:
            continue

        row_match = re.match(r"^(\d+)(y|n|edit)", token)
        if not row_match:
            continue

        idx = int(row_match.group(1)) - 1
        action = row_match.group(2)

        if idx < 0 or idx >= len(analyses):
            messages.append(f"Row {idx+1} out of range")
            continue

        a = analyses[idx]
        if action == "y":
            approved.append(_analysis_to_change(a))
        elif action == "n":
            rejected.append({"item_id": a["item_id"], "original_name": a["original_name"]})

    return approved, rejected, messages


def _analysis_to_change(a: dict) -> dict:
    return {
        "id": a["item_id"],
        "name": a["suggested_name"],
        "tags": a["suggested_tags"],
        "annotation": a.get("summary", ""),
    }
