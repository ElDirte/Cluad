"""
Notion File Catalog API wrapper.
Replaces eagle_api.py. Files stay on the filesystem — metadata lives in Notion.
"""

from datetime import datetime
from pathlib import Path
from typing import Optional

from notion_client import Client

from config import NOTION_API_KEY, FILE_CATALOG_DB_ID, INTAKE_FOLDERS, INTAKE_BATCH_SIZE

_notion = Client(auth=NOTION_API_KEY)

SUPPORTED_EXTS = {
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic", "avif", "svg",
    "mp4", "mov", "avi", "mkv", "webm",
    "pdf", "docx", "doc", "txt", "md", "rtf", "xlsx", "csv",
}

_EXT_OPTIONS = {"jpg", "png", "gif", "webp", "mp4", "mov", "pdf", "docx", "txt", "md"}


def is_connected() -> bool:
    """Check if Notion API is accessible and catalog database exists."""
    try:
        _notion.databases.retrieve(database_id=FILE_CATALOG_DB_ID)
        return True
    except Exception:
        return False


def get_catalog_info() -> dict:
    """Return catalog name and count of staged entries."""
    try:
        db = _notion.databases.retrieve(database_id=FILE_CATALOG_DB_ID)
        name = db.get("title", [{}])[0].get("plain_text", "NEXUS File Catalog")
        resp = _notion.databases.query(
            database_id=FILE_CATALOG_DB_ID,
            filter={"property": "Status", "select": {"equals": "staged"}},
        )
        return {"name": name, "staged": len(resp.get("results", []))}
    except Exception as e:
        return {"name": "NEXUS File Catalog", "error": str(e)}


def _get_cataloged_paths() -> set[str]:
    """Return all file paths already in the catalog (any status)."""
    paths: set[str] = set()
    has_more = True
    cursor = None
    while has_more:
        kwargs: dict = {"database_id": FILE_CATALOG_DB_ID, "page_size": 100}
        if cursor:
            kwargs["start_cursor"] = cursor
        resp = _notion.databases.query(**kwargs)
        for page in resp.get("results", []):
            texts = page.get("properties", {}).get("File Path", {}).get("rich_text", [])
            if texts:
                paths.add(texts[0].get("plain_text", ""))
        has_more = resp.get("has_more", False)
        cursor = resp.get("next_cursor")
    return paths


def get_staging_items(limit: int = 15, offset: int = 0) -> tuple[list[dict], str]:
    """
    Scan INTAKE_FOLDERS for files not yet in the catalog.
    Returns (items, source_folder). Each item: {path, name, ext, size, folder}.
    """
    cataloged = _get_cataloged_paths()
    new_files: list[dict] = []

    for folder_str in INTAKE_FOLDERS:
        folder = Path(folder_str)
        if not folder.exists():
            continue
        for f in sorted(folder.rglob("*")):
            if not f.is_file():
                continue
            ext = f.suffix.lstrip(".").lower()
            if ext not in SUPPORTED_EXTS:
                continue
            if str(f) in cataloged:
                continue
            new_files.append({
                "path": str(f),
                "name": f.stem,
                "ext": ext,
                "size": f.stat().st_size,
                "folder": str(f.parent),
            })

    page = new_files[offset: offset + limit]
    return page, INTAKE_FOLDERS[0] if INTAKE_FOLDERS else ""


def get_items(
    keyword: Optional[str] = None,
    tags: Optional[list[str]] = None,
    status: Optional[str] = None,
    limit: int = 20,
) -> list[dict]:
    """Query the Notion File Catalog with optional filters."""
    filters = []
    if status:
        filters.append({"property": "Status", "select": {"equals": status}})
    if tags:
        for tag in tags:
            filters.append({"property": "Tags", "multi_select": {"contains": tag}})
    if keyword:
        filters.append({"property": "File", "title": {"contains": keyword}})

    query_filter = None
    if len(filters) == 1:
        query_filter = filters[0]
    elif len(filters) > 1:
        query_filter = {"and": filters}

    kwargs: dict = {"database_id": FILE_CATALOG_DB_ID, "page_size": min(limit, 100)}
    if query_filter:
        kwargs["filter"] = query_filter

    resp = _notion.databases.query(**kwargs)
    results = []
    for page in resp.get("results", []):
        props = page.get("properties", {})
        results.append({
            "page_id": page["id"],
            "name": _get_title(props, "File"),
            "path": _get_text(props, "File Path"),
            "ext": _get_select(props, "Extension"),
            "status": _get_select(props, "Status"),
            "tags": _get_multiselect(props, "Tags"),
            "summary": _get_text(props, "Summary"),
            "confidence": props.get("Confidence", {}).get("number"),
        })
    return results


def apply_changes(changes: list[dict]) -> list[dict]:
    """
    Write approved metadata to the Notion File Catalog.
    Creates a new page if path isn't cataloged yet, updates if it is.

    Each change dict:
        path (str): full file path — used as unique key
        name (str): suggested filename without extension
        tags (list[str]): tag list using prefix schema
        annotation (str): AI-generated summary
        quality (str, optional): keep / maybe / low
        confidence (float): 0.0–1.0
        analysis_source (str): ollama_vision / claude / manual
    """
    existing = _get_pages_by_path([c["path"] for c in changes])
    results = []

    for change in changes:
        path = change.get("path", "")
        p = Path(path) if path else Path("unknown")
        name = change.get("name", p.stem)
        tags = change.get("tags", [])
        annotation = change.get("annotation", "")
        quality = change.get("quality", "")
        raw_conf = change.get("confidence", 0.0)
        confidence = int(raw_conf * 100) if raw_conf <= 1.0 else int(raw_conf)
        source = change.get("analysis_source", "claude")
        ext = p.suffix.lstrip(".").lower()

        properties: dict = {
            "File": {"title": [{"text": {"content": name}}]},
            "File Path": {"rich_text": [{"text": {"content": path}}]},
            "Original Name": {"rich_text": [{"text": {"content": p.name}}]},
            "Extension": {"select": {"name": ext if ext in _EXT_OPTIONS else "other"}},
            "Status": {"select": {"name": "reviewed"}},
            "Tags": {"multi_select": [{"name": t} for t in tags]},
            "Source Folder": {"rich_text": [{"text": {"content": str(p.parent)}}]},
            "Summary": {"rich_text": [{"text": {"content": annotation}}]},
            "Confidence": {"number": confidence},
            "Analysis Source": {"select": {"name": source if source in ("ollama_vision", "claude", "manual") else "manual"}},
            "Intake Date": {"date": {"start": datetime.now().strftime("%Y-%m-%d")}},
        }
        if quality in ("keep", "maybe", "low"):
            properties["Quality"] = {"select": {"name": quality}}

        try:
            page_id = existing.get(path)
            if page_id:
                _notion.pages.update(page_id=page_id, properties=properties)
                results.append({"path": path, "status": "ok", "action": "updated"})
            else:
                _notion.pages.create(
                    parent={"database_id": FILE_CATALOG_DB_ID},
                    properties=properties,
                )
                results.append({"path": path, "status": "ok", "action": "created"})
        except Exception as e:
            results.append({"path": path, "status": "error", "error": str(e)})

    return results


def _get_pages_by_path(paths: list[str]) -> dict[str, str]:
    """Return {file_path: notion_page_id} for already-cataloged paths."""
    found: dict[str, str] = {}
    for path in paths:
        try:
            resp = _notion.databases.query(
                database_id=FILE_CATALOG_DB_ID,
                filter={"property": "File Path", "rich_text": {"equals": path}},
                page_size=1,
            )
            if resp.get("results"):
                found[path] = resp["results"][0]["id"]
        except Exception:
            pass
    return found


def format_item_summary(item: dict) -> str:
    """One-line human-readable summary of a file item."""
    name = item.get("name", "unknown")
    ext = item.get("ext", "?")
    size = item.get("size", 0)
    size_str = f"{size // 1024}KB" if size > 1024 else f"{size}B"
    folder = Path(item.get("folder", item.get("path", ""))).name
    return f"{name}.{ext} ({size_str}) — {folder}"


# ─── Property read helpers ────────────────────────────────────────────────────

def _get_title(props: dict, key: str) -> str:
    items = props.get(key, {}).get("title", [])
    return items[0].get("plain_text", "") if items else ""


def _get_text(props: dict, key: str) -> str:
    items = props.get(key, {}).get("rich_text", [])
    return items[0].get("plain_text", "") if items else ""


def _get_select(props: dict, key: str) -> str:
    sel = props.get(key, {}).get("select")
    return sel.get("name", "") if sel else ""


def _get_multiselect(props: dict, key: str) -> list[str]:
    items = props.get(key, {}).get("multi_select", [])
    return [i.get("name", "") for i in items]
