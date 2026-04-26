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
from tools.eagle_api import (
    is_running, get_library_info, get_staging_items, get_items,
    apply_changes, format_item_summary, find_folder_by_name
)
from tools.analyzer import analyze_item, format_approval_table, parse_approval_response

_client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

# In-memory state per session (Chainlit handles session isolation)
_pending_analyses: list[dict] = []


@cl.on_chat_start
async def on_start():
    """Initialize session: check Eagle, surface continuity, greet."""
    global _pending_analyses
    _pending_analyses = []

    system = build_system_prompt()
    cl.user_session.set("system", system)
    cl.user_session.set("history", [])
    cl.user_session.set("pending_analyses", [])

    eagle_ok = is_running()
    if eagle_ok:
        lib = get_library_info()
        lib_name = lib.get("name", "Unknown library")
        status_line = f"Eagle connected — **{lib_name}**"
    else:
        status_line = "Eagle is **not running**. Open Eagle first, then refresh."

    from agent.memory import get_session_summary
    session_note = get_session_summary()

    await cl.Message(
        content=(
            f"{status_line}\n\n"
            f"**Last session:**\n{session_note}\n\n"
            "What do you want to work on? Type `review` to start Eagle intake, "
            "or just tell me what you need."
        )
    ).send()


@cl.on_message
async def on_message(message: cl.Message):
    """Main message handler — routes to agent loop."""
    history: list = cl.user_session.get("history", [])
    system: str = cl.user_session.get("system", build_system_prompt())
    pending: list = cl.user_session.get("pending_analyses", [])

    user_text = message.content.strip()

    # ── shortcut: handle approval responses when a review is pending ──────────
    if pending and _looks_like_approval(user_text):
        await _handle_approval(user_text, pending)
        return

    # ── standard agent loop ───────────────────────────────────────────────────
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
                elif event.type == "content_block_stop":
                    pass

        final = stream.get_final_message()

    # collect tool use blocks
    for block in final.content:
        if block.type == "tool_use":
            tool_calls_to_execute.append(block)

    if accumulated_text:
        history.append({"role": "assistant", "content": accumulated_text})

    # ── execute tool calls ────────────────────────────────────────────────────
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
        follow_text = "".join(
            b.text for b in follow_up.content if hasattr(b, "text")
        )
        if follow_text:
            await cl.Message(content=follow_text).send()
            history.append({"role": "assistant", "content": follow_text})

    cl.user_session.set("history", history[-40:])
    cl.user_session.set("pending_analyses", pending)


# ─── Tool execution ────────────────────────────────────────────────────────────

async def _execute_tool(name: str, inputs: dict, pending: list) -> dict:
    """Dispatch tool calls to their implementations."""

    if name == "eagle_status":
        if is_running():
            lib = get_library_info()
            return {"status": "connected", "library": lib.get("name"), "path": lib.get("path")}
        return {"status": "not_running", "message": "Open Eagle first"}

    elif name == "eagle_get_staging":
        if not is_running():
            return {"error": "Eagle not running"}
        limit = inputs.get("limit", INTAKE_BATCH_SIZE)
        offset = inputs.get("offset", 0)
        items, folder_id = get_staging_items(limit=limit, offset=offset)
        if not items:
            return {"message": "No untagged items in The Pile. Staging is clear!"}
        summaries = [format_item_summary(i) for i in items]
        cl.user_session.set("_raw_items", items)
        return {
            "count": len(items),
            "folder_id": folder_id,
            "items": summaries,
            "item_ids": [i["id"] for i in items],
        }

    elif name == "eagle_analyze_batch":
        if not is_running():
            return {"error": "Eagle not running"}

        raw_items = cl.user_session.get("_raw_items", [])
        requested_ids = set(inputs.get("item_ids", []))

        items_to_analyze = [i for i in raw_items if i["id"] in requested_ids] if requested_ids else raw_items[:INTAKE_BATCH_SIZE]

        if not items_to_analyze:
            return {"error": "No items found to analyze"}

        await cl.Message(content=f"Analyzing {len(items_to_analyze)} items... (this may take a moment)").send()

        analyses = []
        for item in items_to_analyze:
            analysis = analyze_item(item)
            analyses.append(analysis)

        pending.clear()
        pending.extend(analyses)
        cl.user_session.set("pending_analyses", pending)

        table = format_approval_table(analyses)
        await cl.Message(content=table).send()

        return {"status": "review_presented", "count": len(analyses)}

    elif name == "eagle_apply_approved":
        changes = inputs.get("changes", [])
        if not changes:
            return {"message": "No changes to apply"}

        results = apply_changes(changes)
        ok = sum(1 for r in results if r["status"] == "ok")
        err = sum(1 for r in results if r["status"] == "error")

        for change in changes:
            log_decision(
                item_id=change["id"],
                original_name="",
                proposed_name=change.get("name", ""),
                approved=1,
                final_name=change.get("name", ""),
                final_tags=change.get("tags", []),
                final_folder="",
                confidence=0.0,
                source="user_approved",
            )

        return {"applied": ok, "errors": err, "results": results}

    elif name == "eagle_search":
        keyword = inputs.get("keyword")
        tags = inputs.get("tags")
        limit = inputs.get("limit", 20)
        items = get_items(keyword=keyword, tags=tags, limit=limit)
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
    """Detect if the user's message is responding to an approval table."""
    t = text.lower()
    return (
        any(c in t for c in ["y", "n"]) and
        any(char.isdigit() for char in t)
    ) or t in ("all-y", "done", "approve all", "reject all")


async def _handle_approval(response: str, pending: list):
    """Process approval response and apply changes."""
    if not pending:
        await cl.Message(content="No pending review to approve. Run `review` first.").send()
        return

    approved_changes, rejected_items, messages = parse_approval_response(response, pending)

    if messages:
        for m in messages:
            await cl.Message(content=f"Note: {m}").send()

    summary_lines = []

    if approved_changes:
        results = apply_changes(approved_changes)
        ok = sum(1 for r in results if r["status"] == "ok")
        err = sum(1 for r in results if r["status"] == "error")

        for change in approved_changes:
            a = next((x for x in pending if x["item_id"] == change["id"]), {})
            log_decision(
                item_id=change["id"],
                original_name=a.get("original_name", ""),
                proposed_name=change.get("name", ""),
                approved=1,
                final_name=change.get("name", ""),
                final_tags=change.get("tags", []),
                final_folder=a.get("suggested_folder", ""),
                confidence=a.get("confidence", 0.0),
                source=a.get("analysis_source", ""),
            )

        summary_lines.append(f"Applied {ok} changes" + (f", {err} errors" if err else ""))

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
        summary_lines.append(f"Skipped {len(rejected_items)} items (logged)")

    if response.lower() != "done":
        remaining = len(pending) - len(approved_changes) - len(rejected_items)
        if remaining > 0:
            summary_lines.append(f"{remaining} items still in this batch — type row numbers or `done` to finish")

    pending.clear()
    cl.user_session.set("pending_analyses", [])

    await cl.Message(content="\n".join(summary_lines) if summary_lines else "Done.").send()
