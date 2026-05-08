"""
The System — Chainlit chat agent.

Run with:  chainlit run agent.py
Opens at:  http://localhost:8000
"""

import json
import chainlit as cl
import anthropic

from config import ANTHROPIC_API_KEY, PRIMARY_MODEL, INTAKE_BATCH_SIZE
from agent.prompts import build_system_prompt, TOOL_DEFINITIONS
from agent.memory import remember, recall, log_decision, log_voice_pattern
from tools.notion_catalog import (
    is_connected, get_catalog_info, get_staging_items, get_items,
    apply_changes, format_item_summary,
)
from tools.analyzer import analyze_item, format_approval_table, parse_approval_response

_client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

_pending_analyses: list[dict] = []


@cl.on_chat_start
async def on_start():
    """Initialize session: check Notion catalog, surface continuity, greet."""
    global _pending_analyses
    _pending_analyses = []

    system = build_system_prompt()
    cl.user_session.set("system", system)
    cl.user_session.set("history", [])
    cl.user_session.set("pending_analyses", [])

    if is_connected():
        info = get_catalog_info()
        staged = info.get("staged", 0)
        status_line = (
            f"Notion File Catalog connected — **{info.get('name', 'NEXUS File Catalog')}** "
            f"({staged} file{'s' if staged != 1 else ''} staged)"
        )
    else:
        status_line = "⚠️ Notion File Catalog **not reachable**. Check NOTION_API_KEY in .env."

    from agent.memory import get_session_summary
    session_note = get_session_summary()

    await cl.Message(
        content=(
            f"{status_line}\n\n"
            f"**Last session:**\n{session_note}\n\n"
            "Type `review` to start file intake, or tell me what you need."
        )
    ).send()


@cl.on_message
async def on_message(message: cl.Message):
    """Main message handler — routes to agent loop."""
    history: list = cl.user_session.get("history", [])
    system: str = cl.user_session.get("system", build_system_prompt())
    pending: list = cl.user_session.get("pending_analyses", [])

    user_text = message.content.strip()

    if pending and _looks_like_approval(user_text):
        await _handle_approval(user_text, pending)
        return

    history.append({"role": "user", "content": user_text})

    response_msg = cl.Message(content="")
    await response_msg.send()

    accumulated_text = ""
    tool_calls_to_execute = []

    with _client.messages.stream(
        model=PRIMARY_MODEL,
        max_tokens=4096,
        system=system,
        tools=TOOL_DEFINITIONS,
        messages=history,
    ) as stream:
        for event in stream:
            if hasattr(event, "type"):
                if event.type == "content_block_delta":
                    delta = getattr(event.delta, "text", "")
                    if delta:
                        accumulated_text += delta
                        await response_msg.stream_token(delta)

        final = stream.get_final_message()

    for block in final.content:
        if block.type == "tool_use":
            tool_calls_to_execute.append(block)

    if tool_calls_to_execute:
        await response_msg.update()
        tool_results = []
        for call in tool_calls_to_execute:
            result = await _execute_tool(call.name, call.input, pending)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": call.id,
                "content": json.dumps(result),
            })

        history.append({"role": "assistant", "content": final.content})
        history.append({"role": "user", "content": tool_results})

        follow_up = _client.messages.create(
            model=PRIMARY_MODEL,
            max_tokens=4096,
            system=system,
            tools=TOOL_DEFINITIONS,
            messages=history,
        )
        follow_text = "".join(b.text for b in follow_up.content if hasattr(b, "text"))
        if follow_text:
            await cl.Message(content=follow_text).send()
            history.append({"role": "assistant", "content": follow_text})
    else:
        if accumulated_text:
            history.append({"role": "assistant", "content": accumulated_text})

    cl.user_session.set("history", history[-40:])
    cl.user_session.set("pending_analyses", pending)


# ─── Tool execution ────────────────────────────────────────────────────────────

async def _execute_tool(name: str, inputs: dict, pending: list) -> dict:

    if name == "catalog_status":
        if is_connected():
            info = get_catalog_info()
            return {"status": "connected", **info}
        return {"status": "unreachable", "message": "Check NOTION_API_KEY in .env"}

    elif name == "catalog_get_staging":
        if not is_connected():
            return {"error": "Notion catalog unreachable"}
        limit = inputs.get("limit", INTAKE_BATCH_SIZE)
        offset = inputs.get("offset", 0)
        items, folder = get_staging_items(limit=limit, offset=offset)
        if not items:
            return {"message": "No new files found in intake folders. All caught up!"}
        summaries = [format_item_summary(i) for i in items]
        cl.user_session.set("_raw_items", items)
        return {
            "count": len(items),
            "source_folder": folder,
            "items": summaries,
            "paths": [i["path"] for i in items],
        }

    elif name == "catalog_analyze_batch":
        if not is_connected():
            return {"error": "Notion catalog unreachable"}

        raw_items = cl.user_session.get("_raw_items", [])
        requested_paths = set(inputs.get("paths", []))
        items_to_analyze = (
            [i for i in raw_items if i["path"] in requested_paths]
            if requested_paths
            else raw_items[:INTAKE_BATCH_SIZE]
        )

        if not items_to_analyze:
            return {"error": "No items found to analyze"}

        await cl.Message(content=f"Analyzing {len(items_to_analyze)} files... (this may take a moment)").send()

        analyses = [analyze_item(item) for item in items_to_analyze]
        pending.clear()
        pending.extend(analyses)
        cl.user_session.set("pending_analyses", pending)

        await cl.Message(content=format_approval_table(analyses)).send()
        return {"status": "review_presented", "count": len(analyses)}

    elif name == "catalog_apply_approved":
        changes = inputs.get("changes", [])
        if not changes:
            return {"message": "No changes to apply"}

        results = apply_changes(changes)
        ok = sum(1 for r in results if r["status"] == "ok")
        err = sum(1 for r in results if r["status"] == "error")

        for change in changes:
            log_decision(
                item_id=change["path"],
                original_name="",
                proposed_name=change.get("name", ""),
                approved=1,
                final_name=change.get("name", ""),
                final_tags=change.get("tags", []),
                final_folder="",
                confidence=change.get("confidence", 0.0),
                source="user_approved",
            )

        return {"applied": ok, "errors": err, "results": results}

    elif name == "catalog_search":
        keyword = inputs.get("keyword")
        tags = inputs.get("tags")
        status = inputs.get("status")
        limit = inputs.get("limit", 20)
        items = get_items(keyword=keyword, tags=tags, status=status, limit=limit)
        return {"count": len(items), "items": [format_item_summary(i) for i in items]}

    elif name == "remember_preference":
        remember(inputs.get("content", ""))
        return {"status": "stored"}

    elif name == "get_session_summary":
        from agent.memory import get_session_summary as _gs
        return {"summary": _gs()}

    return {"error": f"Unknown tool: {name}"}


# ─── Approval handler ──────────────────────────────────────────────────────────

def _looks_like_approval(text: str) -> bool:
    t = text.lower()
    return (
        any(c in t for c in ["y", "n"]) and any(char.isdigit() for char in t)
    ) or t in ("all-y", "done", "approve all", "reject all")


async def _handle_approval(response: str, pending: list):
    if not pending:
        await cl.Message(content="No pending review. Type `review` first.").send()
        return

    approved_changes, rejected_items, messages = parse_approval_response(response, pending)

    for m in messages:
        await cl.Message(content=f"Note: {m}").send()

    summary_lines = []

    if approved_changes:
        results = apply_changes(approved_changes)
        ok = sum(1 for r in results if r["status"] == "ok")
        err = sum(1 for r in results if r["status"] == "error")

        for change in approved_changes:
            a = next((x for x in pending if x["item_id"] == change["path"]), {})
            log_decision(
                item_id=change["path"],
                original_name=a.get("original_name", ""),
                proposed_name=change.get("name", ""),
                approved=1,
                final_name=change.get("name", ""),
                final_tags=change.get("tags", []),
                final_folder="",
                confidence=a.get("confidence", 0.0),
                source=a.get("analysis_source", ""),
            )

        summary_lines.append(f"Cataloged {ok} file{'s' if ok != 1 else ''}" + (f", {err} errors" if err else ""))

    if rejected_items:
        for r in rejected_items:
            log_decision(
                item_id=r["item_id"],
                original_name=r.get("original_name", ""),
                proposed_name="",
                approved=0,
                final_name=r.get("original_name", ""),
                final_tags=[],
                final_folder="",
                confidence=0.0,
                source="user_rejected",
            )
        summary_lines.append(f"Skipped {len(rejected_items)} file{'s' if len(rejected_items) != 1 else ''} (logged)")

    if response.lower() != "done":
        remaining = len(pending) - len(approved_changes) - len(rejected_items)
        if remaining > 0:
            summary_lines.append(f"{remaining} remaining — continue with row numbers or `done`")

    pending.clear()
    cl.user_session.set("pending_analyses", [])

    await cl.Message(content="\n".join(summary_lines) if summary_lines else "Done.").send()
