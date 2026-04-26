# Eagle Intake Review — Prompt Templates

## Batch Start Prompt
Use when starting an intake session:

```
Review my Eagle staging area. Pull the next batch of untagged items from The Pile,
analyze each one, and show me the approval table. I'll go through them and approve,
reject, or edit each suggestion.
```

## Targeted Review Prompt
Use when focusing on a specific type:

```
Pull the next [N] images/screenshots/docs from The Pile and analyze them.
Focus on [Archer / GroPhoTo / AI tools / work / family] material specifically.
```

## Edit a Suggestion
After receiving an approval table, to edit row 3:

```
3edit name=2026-04-23_archer-ref_use-design-idea tags=use:design-idea,topic:fandom,src:screenshot,q:keep
```

## Approve All High-Confidence
```
all-y
```
This approves every row with 70%+ confidence and skips the rest for manual review.

## Finish Batch Without Applying Remainder
```
done
```

## Search and Review Specific Files
```
Search Eagle for files tagged use:staged from this week and show me an approval table.
```

## Session Start — Continue Previous Work
When the agent asks what to work on:
```
Continue where we left off
```
or
```
What's still pending in my staging area?
```

## Teach the Agent a Preference
```
Remember that GroPhoTo items should always use the proj:grophoto tag and topic:garden.
```

## Ask About a Specific File
```
What is item [Eagle item ID]? What do you think it should be tagged as?
```
