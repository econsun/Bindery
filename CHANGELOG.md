# Changelog

## 1.2.1 — 2026-11-26

- Timeline is now a right-hand activity panel with a labeled **Timeline** toolbar entry and a close button, instead of a sidebar destination.
- Removed timeline event/day counts; the panel is quieter and uses the top-right space.
- Timeline dots are larger and centered on the rail, with their vertical center locked to the title row.
- Timeline filters now include persistent quick scopes plus type and level filters; selections survive relaunches.
- Search uses an AppKit-backed field with a stable placeholder and reliable Escape/click-away focus exit.
- Log growth is bounded: 8 MB rotation to `activity.previous.jsonl`, app launches at most once per 24 hours/version, no-op scans suppressed, and start events no longer written.

## 1.2.0 — 2026-11-26

- Finder integration: right-click any file or folder and choose **Use Bindery → Add to Unmanaged** or **Back Up to Binding…**. The new intake sheet lets you pick a store or search bindings without leaving the flow. Folders are supported.
- Finder extension is embedded in the app; enable it from **Settings → General → Finder**.
- Wide-screen layouts now use the available width: adaptive card grid, flexible column layouts for All Backups, Unmanaged, and the binding list, plus a right-side event inspector in Timeline.
- Timeline dots now align with event titles.
- Global sorting defaults are split: **Smart folder sort** (last backup by default) and **Category sort** (name by default), configurable in Settings.
- Double-clicking the top of the window zooms/maximizes it.
- Context menus now include Copy Snapshot ID/Path, Copy Binding ID, Show Store in Finder, and clearer binding actions.

## 1.1.1 — 2026-11-25

- Increased secondary and tertiary text contrast in both light and dark mode.
- Larger metadata text in All Backups, Unmanaged, Timeline, binding lists, sidebar counts, detail panels, and editor labels.
- Snapshot IDs, sizes, timestamps, project badges, and “No binding” labels are now readable instead of almost invisible.

## 1.1.0 — 2026-11-25

- Added a durable JSONL activity log and a visual **Timeline** in the sidebar.
- Timeline records backups, binding/category/store edits, snapshot ownership/moves/renames/deletes/verifies, imports, and scans, with major/normal/minor/error levels, expandable details, filters, Copy JSONL, and Reveal Log.
- Moved security-scoped bookmark creation off the main thread during store refresh.

## 1.0.0 — 2026-11-25

Initial public release.

- Store, binding, and snapshot model with portable JSON catalogs.
- Fixed-source and generator bindings, categories, favorites, notes, cover icons and previews.
- Permanent snapshot IDs, SHA-256 content digests, and scan-time relocation.
- All Backups and Unmanaged views with multi-selection, searchable Move to Binding, batch rename preview, verification, and macOS Trash deletion.
- Offline stores, cross-store snapshot adoption, and configurable filename formats.
- Folder-only ZIP compression; single files are copied as-is.
