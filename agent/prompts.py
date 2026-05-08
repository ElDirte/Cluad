"""
Builds the system prompt for each session by combining:
  - CLAUDE.md (living project memory)
  - mem0 personal memories
  - SQLite session summary
  - Current date/context
"""

from datetime import datetime

from config import CLAUDE_MD_PATH
from agent.memory import recall_all, get_session_summary


def build_system_prompt(task_context: str = "") -> str:
    today = datetime.now().strftime("%Y-%m-%d %H:%M")

    claude_md = ""
    if CLAUDE_MD_PATH.exists():
        claude_md = CLAUDE_MD_PATH.read_text(encoding="utf-8")

    memories = recall_all()
    memory_block = ""
    if memories:
        memory_block = "\n## Learned Preferences (from past sessions)\n" + "\n".join(
            f"- {m}" for m in memories[:15]
        )

    session_block = "\n## Last Session\n" + get_session_summary()
    task_block = f"\n## Current Task Context\n{task_context}" if task_context else ""

    return f"""You are The System — a personal AI agent acting as extended executive function for Kenneth (Allen Watts).

Today: {today}

Your role:
- You control software on Kenneth's PC to perform tasks as he would, but more efficiently
- You hold memory of his decisions, preferences, and communication style across sessions
- You learn from every interaction — his corrections, preferences, and patterns
- You surface continuity: always remind what was last happening, what's pending, what's next
- You match his tone: direct, no fluff, precise about the system, casual in conversation

Core rules:
- Never make file changes without showing a dry-run table first
- Wait for explicit approval before executing any rename/tag/move
- When uncertain, ask one focused question — not a list
- Label your confidence level explicitly (high/medium/low/uncertain)
- Prefer the smallest safe action when in doubt
- If Notion catalog is unreachable, say so clearly and stop

Current capabilities:
- File intake from configured folders (scan, analyze, tag, catalog)
- Notion File Catalog management (tag, rename suggestions, status tracking)
- File analysis (vision AI for images via Ollama, Claude for docs)
- Memory of past decisions and routing patterns (mem0 + SQLite)
- Session continuity (pick up where we left off)

{claude_md}
{memory_block}
{session_block}
{task_block}

When starting a session, always:
1. Check if the Notion File Catalog is connected
2. Surface the last session summary
3. Ask if they want to continue previous work or start something new
"""


TOOL_DEFINITIONS = [
    {
        "name": "catalog_status",
        "description": "Check if the Notion File Catalog is connected and get entry counts",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "catalog_get_staging",
        "description": "Scan intake folders for files not yet in the Notion File Catalog",
        "input_schema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "description": "Number of files to fetch (default 15)", "default": 15},
                "offset": {"type": "integer", "description": "Pagination offset", "default": 0},
            },
            "required": [],
        },
    },
    {
        "name": "catalog_analyze_batch",
        "description": "Analyze a batch of files and generate an approval table with suggested names, tags, and quality ratings",
        "input_schema": {
            "type": "object",
            "properties": {
                "paths": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "List of file paths to analyze",
                }
            },
            "required": ["paths"],
        },
    },
    {
        "name": "catalog_apply_approved",
        "description": "Write approved metadata to the Notion File Catalog. Only call after explicit user approval.",
        "input_schema": {
            "type": "object",
            "properties": {
                "changes": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string"},
                            "name": {"type": "string"},
                            "tags": {"type": "array", "items": {"type": "string"}},
                            "annotation": {"type": "string"},
                            "quality": {"type": "string"},
                        },
                        "required": ["path"],
                    },
                }
            },
            "required": ["changes"],
        },
    },
    {
        "name": "catalog_search",
        "description": "Search the Notion File Catalog by keyword, tags, or status",
        "input_schema": {
            "type": "object",
            "properties": {
                "keyword": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "status": {"type": "string", "description": "staged / reviewed / needs-action / archived / done"},
                "limit": {"type": "integer", "default": 20},
            },
            "required": [],
        },
    },
    {
        "name": "remember_preference",
        "description": "Store a learned preference or pattern in long-term memory",
        "input_schema": {
            "type": "object",
            "properties": {
                "content": {"type": "string"},
            },
            "required": ["content"],
        },
    },
    {
        "name": "get_session_summary",
        "description": "Get a summary of recent activity and decisions for continuity",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
]
