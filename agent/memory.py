"""
Two-layer memory:
  1. mem0 — personal facts, style preferences, learned patterns (semantic, cross-session)
  2. SQLite — structured action log (every decision, queryable)
"""

import sqlite3
import json
from datetime import datetime
from pathlib import Path
from typing import Optional

from config import DB_PATH, AGENT_USER_ID

try:
    from mem0 import Memory
    _mem0 = Memory()
    MEM0_AVAILABLE = True
except Exception:
    _mem0 = None
    MEM0_AVAILABLE = False


# ─── SQLite decision log ───────────────────────────────────────────────────────

def _db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Create tables if they don't exist."""
    with _db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS decisions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                ts          TEXT NOT NULL,
                item_id     TEXT NOT NULL,
                original    TEXT,
                proposed    TEXT,
                approved    INTEGER,  -- 1=approved, 0=rejected, 2=edited
                final_name  TEXT,
                final_tags  TEXT,     -- JSON array
                final_folder TEXT,
                confidence  REAL,
                source      TEXT      -- 'ollama_vision' or 'claude'
            );

            CREATE TABLE IF NOT EXISTS sessions (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                ts      TEXT NOT NULL,
                summary TEXT
            );

            CREATE TABLE IF NOT EXISTS voice_profile (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                ts      TEXT NOT NULL,
                pattern TEXT NOT NULL,
                example TEXT
            );
        """)


def log_decision(
    item_id: str,
    original_name: str,
    proposed_name: str,
    approved: int,
    final_name: str,
    final_tags: list[str],
    final_folder: str,
    confidence: float,
    source: str,
):
    with _db() as conn:
        conn.execute(
            """INSERT INTO decisions
               (ts, item_id, original, proposed, approved, final_name, final_tags, final_folder, confidence, source)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                datetime.now().isoformat(),
                item_id, original_name, proposed_name, approved,
                final_name, json.dumps(final_tags), final_folder, confidence, source,
            ),
        )


def get_recent_decisions(limit: int = 20) -> list[dict]:
    with _db() as conn:
        rows = conn.execute(
            "SELECT * FROM decisions ORDER BY ts DESC LIMIT ?", (limit,)
        ).fetchall()
    return [dict(r) for r in rows]


def get_session_summary() -> str:
    """Generate a text summary of recent activity for session continuity."""
    recent = get_recent_decisions(10)
    if not recent:
        return "No previous decisions found. This appears to be a fresh start."

    approved = sum(1 for r in recent if r["approved"] == 1)
    rejected = sum(1 for r in recent if r["approved"] == 0)
    edited = sum(1 for r in recent if r["approved"] == 2)
    last_ts = recent[0]["ts"][:16].replace("T", " ")

    lines = [f"Last activity: {last_ts}"]
    lines.append(f"Recent decisions: {approved} approved, {rejected} rejected, {edited} edited")
    if recent:
        lines.append(f"Last file processed: {recent[0]['original']}")
    return "\n".join(lines)


def log_voice_pattern(pattern: str, example: str = ""):
    """Store a learned communication pattern."""
    with _db() as conn:
        conn.execute(
            "INSERT INTO voice_profile (ts, pattern, example) VALUES (?, ?, ?)",
            (datetime.now().isoformat(), pattern, example),
        )


# ─── mem0 personal memory ─────────────────────────────────────────────────────

def remember(content: str, metadata: Optional[dict] = None):
    """Store a new memory (preference, correction, pattern, fact)."""
    if not MEM0_AVAILABLE:
        return
    try:
        _mem0.add(content, user_id=AGENT_USER_ID, metadata=metadata or {})
    except Exception:
        pass


def recall(query: str, limit: int = 5) -> list[str]:
    """Retrieve relevant memories for a given context query."""
    if not MEM0_AVAILABLE:
        return []
    try:
        results = _mem0.search(query, user_id=AGENT_USER_ID, limit=limit)
        return [r["memory"] for r in results if "memory" in r]
    except Exception:
        return []


def recall_all() -> list[str]:
    """Retrieve all stored memories (for session start context)."""
    if not MEM0_AVAILABLE:
        return []
    try:
        results = _mem0.get_all(user_id=AGENT_USER_ID)
        return [r["memory"] for r in results if "memory" in r]
    except Exception:
        return []


# ─── init on import ───────────────────────────────────────────────────────────

init_db()
