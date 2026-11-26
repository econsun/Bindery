# Activity log

Bindery writes every mutating operation to a durable, append-only JSON Lines file:

```text
~/Library/Application Support/Bindery/activity.jsonl
```

Open **Timeline** from the toolbar to inspect it in the right-hand activity
panel. The panel supports quick scopes (`All`, `Changes`, `Backups`, `Scans`,
`Errors`), persistent type/level filters, expandable details, **Copy JSONL**, and
**Reveal Log**. Selections are remembered across launches.

## Format

Each line is one self-contained JSON object. Dates are ISO 8601 UTC. Keys are
stable and sorted.

```json
{
  "actor": "user",
  "details": {
    "binding": "Research",
    "snapshotID": "261125NM",
    "store": "Local",
    "durationMs": "1840"
  },
  "id": "4A4A0B06-7E13-4A20-9B58-BF5E6F2D3E21",
  "kind": "backup.completed",
  "level": "major",
  "schema": 1,
  "summary": "261125NM · zip · 12.4 MB",
  "timestamp": "2026-11-25T14:12:07Z",
  "title": "Backed up Research"
}
```

### Top-level fields

| Field | Meaning |
| --- | --- |
| `schema` | log schema version (`1`) |
| `id` | event UUID |
| `timestamp` | ISO 8601 UTC time |
| `kind` | stable operation identifier (see below) |
| `level` | `major`, `normal`, `minor`, or `error` |
| `actor` | `user`, `system`, or `scan` |
| `title` | short human-readable headline |
| `summary` | one-line context |
| `details` | flat string map with IDs, paths, counts, before/after values, errors |

### Kinds

```text
app.launch
scan.completed
backup.started
backup.completed
backup.failed
binding.created
binding.updated
binding.deleted
binding.archived
binding.favorite
binding.category_changed
category.created
category.renamed
category.moved
category.removed
store.added
store.removed
snapshot.assigned
snapshot.moved_store
snapshot.renamed
snapshot.deleted
snapshot.verified
unmanaged.imported
unmanaged.ignored
```

### Levels

- `major` — backup completed, binding created/updated/deleted, snapshot ownership/move/rename/delete.
- `normal` — scans with changes, category/store changes, verification, assignment counts.
- `minor` — launch, favorites/archive/creator tweaks, no-op scans, ignored files.
- `error` — failed backup, failed verification, import/store errors.

## Reading it from an AI or shell

The current file is capped at 8 MB. When it grows past that, it rotates to
`activity.previous.jsonl` and a fresh `activity.jsonl` starts; both are read by
the panel on launch. No-op scans are not logged, app launches are recorded at
most once per 24 hours per version, and backup start events are omitted so the
log stays focused on operations worth reconstructing.

The file is intentionally plain JSONL so an assistant can reconstruct state
changes without the UI:

```zsh
# latest 200 events, newest first
tail -n 200 ~/Library/Application\ Support/Bindery/activity.jsonl

# only backups and errors
jq -c 'select(.kind | startswith("backup") or .level == "error")' \
  ~/Library/Application\ Support/Bindery/activity.jsonl

# what happened to one binding
jq -c 'select(.details.binding == "Research")' \
  ~/Library/Application\ Support/Bindery/activity.jsonl
```

`Copy JSONL` copies the currently visible/filtered events in chronological
order, which is usually the easiest handoff to another tool.
