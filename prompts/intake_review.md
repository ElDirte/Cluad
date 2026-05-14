# Notion File Catalog — Intake Review Prompt Templates

## Start a Batch Review
```
review
```
or
```
Pull the next batch of untagged files and show me the approval table.
```

## Targeted Review by Type
```
Pull the next 10 screenshots and analyze them.
Focus on Archer / GroPhoTo / AI tools / work / family material specifically.
```

## Approval Responses
After the approval table appears, respond with row numbers:

| Response | Meaning |
|---|---|
| `1y` | Approve row 1 as-is |
| `2n` | Reject row 2 (logged, not cataloged) |
| `3edit name=2026-04-23_archer-ref_design-idea tags=use:design-idea,topic:fandom,src:screenshot,q:keep` | Edit row 3 before applying |
| `all-y` | Approve all high/medium confidence rows |
| `done` | Finish this batch without processing remainder |

## Search the Catalog
```
Search for files tagged use:staged from this week
```
```
Find all GroPhoTo files in the catalog
```
```
Show me everything tagged topic:ai
```

## Session Continuity
```
Continue where we left off
```
```
What's still staged in my catalog?
```

## Teach the Agent a Preference
```
Remember that GroPhoTo items should always use proj:grophoto and topic:garden.
```
```
Remember that Archer screenshots always get use:design-idea and topic:fandom.
```

## Check Catalog Status
```
catalog status
```
