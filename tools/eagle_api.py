"""
Eagle Web API v2 wrapper.
All calls are read-safe by default. Writes only happen via apply_changes().
"""

import requests
from typing import Optional
from config import EAGLE_API_URL


def _get(endpoint: str, params: dict = None) -> dict:
    resp = requests.get(f"{EAGLE_API_URL}{endpoint}", params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()


def _post(endpoint: str, body: dict) -> dict:
    resp = requests.post(f"{EAGLE_API_URL}{endpoint}", json=body, timeout=10)
    resp.raise_for_status()
    return resp.json()


def is_running() -> bool:
    """Check if Eagle is open and the API is accessible."""
    try:
        data = _get("/api/application/info")
        return data.get("status") == "success"
    except Exception:
        return False


def get_library_info() -> dict:
    """Return current library name and path."""
    data = _get("/api/library/info")
    return data.get("data", {})


def get_folders() -> list[dict]:
    """Return the full flat folder list with id, name, parent, and item count."""
    data = _get("/api/folder/list")
    return data.get("data", [])


def get_items(
    folder_id: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    tags: Optional[list[str]] = None,
    keyword: Optional[str] = None,
    is_untagged: bool = False,
) -> list[dict]:
    """
    List items from Eagle.
    folder_id: restrict to one folder. None = all folders.
    is_untagged: True = only items with no tags (useful for intake).
    """
    params: dict = {"limit": limit, "offset": offset}
    if folder_id:
        params["folders"] = folder_id
    if tags:
        params["tags"] = ",".join(tags)
    if keyword:
        params["keyword"] = keyword

    data = _get("/api/item/list", params=params)
    items = data.get("data", [])

    if is_untagged:
        items = [i for i in items if not i.get("tags")]

    return items


def get_item(item_id: str) -> dict:
    """Return full metadata for a single item."""
    data = _get("/api/item/info", params={"id": item_id})
    return data.get("data", {})


def find_folder_by_name(name: str) -> Optional[dict]:
    """Find a folder by exact name (case-insensitive). Returns first match."""
    folders = get_folders()
    name_lower = name.lower()
    for folder in folders:
        if folder.get("name", "").lower() == name_lower:
            return folder
    return None


def get_staging_items(limit: int = 20, offset: int = 0, folder_name: str = None) -> tuple[list[dict], Optional[str]]:
    """
    Return untagged items for intake review.
    If folder_name is given, scopes to that folder. Otherwise searches all folders.
    Returns (items, folder_id).
    """
    folder_id = None
    if folder_name:
        folder = find_folder_by_name(folder_name)
        folder_id = folder["id"] if folder else None

    items = get_items(folder_id=folder_id, limit=limit, offset=offset, is_untagged=True)
    return items, folder_id


def thumbnail_url(item: dict) -> str:
    """Construct the thumbnail URL for an item via Eagle API."""
    item_id = item.get("id", "")
    return f"{EAGLE_API_URL}/api/item/thumbnail?id={item_id}"


def apply_changes(changes: list[dict]) -> list[dict]:
    """
    Apply a list of approved metadata changes to Eagle items.

    Each change dict:
        id (str): Eagle item ID
        name (str, optional): new filename without extension
        tags (list[str], optional): full tag list (replaces existing)
        annotation (str, optional): notes/description
        folders (list[str], optional): folder IDs to assign

    Returns list of results per item.
    """
    results = []
    for change in changes:
        item_id = change.get("id")
        if not item_id:
            continue

        body = {"id": item_id}
        if "name" in change:
            body["name"] = change["name"]
        if "tags" in change:
            body["tags"] = change["tags"]
        if "annotation" in change:
            body["annotation"] = change["annotation"]
        if "folders" in change:
            body["folders"] = change["folders"]

        try:
            result = _post("/api/item/update", body)
            results.append({"id": item_id, "status": "ok", "response": result})
        except Exception as e:
            results.append({"id": item_id, "status": "error", "error": str(e)})

    return results


def format_item_summary(item: dict) -> str:
    """One-line human-readable summary of an Eagle item."""
    name = item.get("name", "unknown")
    ext = item.get("ext", "?")
    tags = item.get("tags", [])
    tag_str = ", ".join(tags) if tags else "no tags"
    w = item.get("width", 0)
    h = item.get("height", 0)
    dims = f" {w}×{h}" if w and h else ""
    return f"{name}.{ext}{dims} | [{tag_str}]"
