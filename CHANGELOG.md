# Changelog

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
