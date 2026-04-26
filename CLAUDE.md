# The System — Agent Memory

## Owner
Kenneth (Allen Watts)

## What This System Is
A personal AI agent acting as extended executive function. It controls software on the PC,
holds memory of decisions and preferences across sessions, and learns to think and communicate
in the owner's style. File sorting (Eagle) is the proof of concept. n8n is the orchestration
backbone — the "neuronet" connecting all tools and workflows.

## Current Session Context
- At session start, surface: what was last worked on, any pending approvals, any open tasks
- Never start cold — always check decision log and mem0 for continuity
- If uncertain about intent, ask one focused question rather than assuming

---

## Eagle Library

**Library name**: Intake Router
**Location**: OneDrive → Kenneth - Personal → Intake Router.library
**Eagle API**: http://localhost:41595

### Folder Structure (actual, from audit 2026-04-26)

```
The Pile/                        ← main inbox, 7,953 items (all untagged as of audit)
├── 26 Image Organization/       ← 6,336 items — previous sorting attempt, now a sub-pile
├── Archer/                      ← 462 items — the animated show / project reference
├── Camera Roll/                 ← 414 items — phone photos
├── GroPhoTo/                    ← 243 items — grow photography (plants/garden)
├── Ai_Tool_Diagrams/            ← 202 items — AI tool screenshots, diagrams, UI references
├── Art_Backgrounds/             ← 32 items — art and backgrounds
├── Work/                        ← 30 items, 14 subfolders — work-related
├── Family/                      ← 68 items — family photos/memories
├── lookinto/                    ← 24 items — things to research later
├── idpics/                      ← 8 items — identity/profile pictures
├── Rabbit holes/                ← 3 items — deep research rabbit holes
├── Screenshots/                 ← 2 items — general screenshots
├── Psilly/                      ← 2 items — psychedelic / silly / personal
├── Garden Pics/                 ← 0 items, 1 subfolder
├── Fandom/                      ← fandom/media/entertainment references
└── .smz/                        ← 2 items — unknown, review before moving
```

### Staging Protocol
- New files enter The Pile (top level or any subfolder)
- Agent processes The Pile in batches during intake review sessions
- Nothing moves until approved — dry run first, commit on explicit approval
- After approval, items are tagged + routed to correct folder or kept in place with enriched metadata

---

## Tag Schema

**Prefix system — use these exact prefixes:**

| Class | Prefix | Valid values |
|---|---|---|
| Use/Intent | `use:` | design-idea, ai-reference, memory-trigger, reminder, project-source, archive, research, inspiration, reference |
| Topic | `topic:` | art, tech, ai, work, family, garden, personal, fandom, photography, health, home |
| Source | `src:` | screenshot, camera, web-save, scan, generated, export |
| Status | `status:` | staged, reviewed, needs-action, archived, done |
| Quality | `q:` | keep, maybe, low |
| Project | `proj:` | archer, grophoto, 26-org, work, garden |

**Rules:**
- Every item must have at least one `use:` tag after review
- `status:staged` is automatic on intake; remove it when reviewed
- Maximum 6 tags per item — prefer fewer, more specific
- Never mix prefixes (don't use `topic:screenshot` — that's `src:screenshot`)

---

## Naming Pattern

**Format**: `YYYY-MM-DD_topic_use_shortdesc`

**Examples:**
- `2026-04-23_kitchen_design-idea_brass-faucet`
- `2026-04-23_ai-tools_reference_claude-ui-screenshot`
- `2026-04-23_grophoto_project-source_week3-bud-closeup`
- `2026-04-23_work_reminder_invoice-format-example`

**Rules:**
- Lowercase, hyphens only (no spaces, no underscores in the desc part)
- Keep shortdesc under 5 words
- Date is always YYYY-MM-DD from the file's modification time if original date unknown
- Do not repeat the extension in the name

---

## Confidence Thresholds

| Confidence | Action |
|---|---|
| 90%+ | Can suggest auto-apply — still confirm with user first |
| 70–89% | Present suggestion, require explicit approval |
| 50–69% | Present with flag: "uncertain — please verify" |
| Below 50% | Do not guess — ask user to describe the file |

---

## Operating Rules

1. **Dry run always first** — never move or rename without showing what will happen
2. **Approval table before execution** — present table, wait for `y/n/edit` response
3. **Smallest safe step** — when uncertain, do less and ask
4. **Batch size**: 10–20 items per review session (not 7,953 at once)
5. **Never touch 26 Image Organization** without a dedicated session — it's its own project
6. **Log every decision** — approved, rejected, and edited all go to decisions.db
7. **Learn from corrections** — when user edits a suggestion, that pattern is stored in memory

---

## Communication Style (to be updated as agent learns)

- Direct, no fluff
- Ask one focused question when uncertain rather than a list of questions
- When presenting options, lead with a recommendation
- Match the user's tone — they're casual but precise about their system
- Note uncertainty explicitly — don't fake confidence

---

## Session Continuity

At the start of every session:
1. Check decisions.db for last N actions
2. Load relevant mem0 memories for current task context
3. Surface: "Last time: [X]. Pending: [Y items awaiting review]. Want to continue?"
4. Load this CLAUDE.md into context

---

## Known Issues / Watch List

- `.smz` folder: unknown file type, 2 items — investigate before touching
- `26 Image Organization` with 6,336 items is a backlog project on its own — treat separately
- Eagle trial expires in 29 days (as of 2026-04-24) — confirm license purchase
- Library is on OneDrive — confirm sync is complete before bulk operations
