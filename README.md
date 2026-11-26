# Bindery

Bindery is a macOS backup manager built around **bindings**. A binding turns a source into snapshots; snapshots live in a store; the store catalog decides whether a backup can still be found.

The app is written in Swift and uses SwiftUI/AppKit directly. There is no Xcode project — `build.sh` compiles the sources with `swiftc`.

## Requirements

- macOS 15.0 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Silicon. The app is compiled for the architecture of the build host.

## Build

```zsh
./test.sh
./build.sh
```

`build.sh` creates `Bindery.app` in the repository root, including the Finder extension. The app is ad-hoc signed, so on first launch use **right-click → Open** if Gatekeeper asks for confirmation. macOS may also ask for access to your Documents folder (or another volume) so Bindery can read and write the store you point it at; allow it. To use **Use Bindery** in Finder, move the app to Applications and enable the extension in **Settings → General → Finder** (or System Settings → Login Items & Extensions → Finder Extensions).

## Objects

- **Store** — a normal folder containing hidden `.bindery/store.json` and `.bindery/catalog.json` files. A store can be renamed, moved to another disk, or go offline; its identity comes from `storeID`, not its path.
- **Binding** — a recipe. It either watches a fixed source or acts as a **generator** that accepts any file or folder dropped on its card.
- **Snapshot** — the product of one backup. Every snapshot has an 8-character permanent ID and its capture metadata is immutable; only its location can move.
- **Category** — belongs to bindings. Bindings own snapshots; snapshots cannot own a category independently.

A snapshot that has no binding is listed under **Unmanaged** until you use **Move** to attach it to a binding.

## Naming

The default snapshot name is:

```text
{bindname}[_{projectDate}]_{backupDate}{XX}
```

- `{bindname}` — binding name, falling back to the source name.
- `{projectDate}` — parsed from the beginning of the source name (`260312`, `26 03 12`, `26-03-12`, …). If no project date can be parsed, the whole optional group disappears, leaving no doubled `_`.
- `{backupDate}` — date the snapshot was created.
- `{XX}` — two random uppercase letters.
- `{backupDate}{XX}` — the permanent 8-character ID.

Date and time formats can be changed in **Settings → General**. Names are generated from a format string, and every rename is previewed before it is applied.

Legacy archives imported from older tools may encode a content/publication date in their filename. The scanner recognizes that shape, records the embedded date as `projectDate`, and uses the archive file's own timestamp for the backup date. The permanent ID is preserved.

## Storage layout

```text
Store/
  .bindery/
    store.json
    catalog.json
  Research/Notes/
    Project_260312_260723AB.zip
```

Category paths match the sidebar hierarchy. Renaming or moving a category moves online snapshots and updates the catalog; offline stores catch up on their next scan.

## Features

- Stores can be local, external, or cloud folders. Offline stores show the last cached catalog and are marked **Offline**, never “missing”.
- The All Backups view merges copies by permanent ID, shows every store copy, and supports search, multi-select, marquee selection, Cmd+A, **Move** to a binding, moving to another store, batch rename with live preview, verification, and deletion to the macOS Trash.
- Bindings can be fixed sources or generators, with categories, favorites, notes, cover icons, cover previews, creator tags, filename formats, and default compression for folder snapshots.
- Single files are always copied as-is. ZIP compression applies only to folder snapshots.
- The Unmanaged view shows unknown files in stores and backups that do not yet belong to a binding. Unknown files can be imported or ignored; unbound backups can be moved to a binding.
- `Archive after first backup` archives a binding after its first successful snapshot.
- The scanner relocates snapshots by permanent ID and by size/hash, preserves binding/date metadata when a snapshot moves between stores, and verifies stored digests on demand.
- The whole library is file-first: the catalog is JSON next to the snapshots, and the app never deletes source files.
- **Timeline** is a right-hand activity panel (toggle **Timeline** in the toolbar) that records backups, binding/category/store edits, moves, renames, deletes, verifications, imports, and meaningful scans in a durable JSONL log. Persistent scope/type/level filters, **Copy JSONL**, and **Reveal Log** make the history useful to both people and AI tools. See [Docs/ACTIVITY_LOG.md](Docs/ACTIVITY_LOG.md).
- **Use Bindery** in Finder: right-click files or folders to send them to Unmanaged or back them up into a binding. Enable the embedded Finder extension in **Settings → General → Finder**.

## Project layout

```text
Sources/
  App_Bindery.swift          App entry point
  Model_*.swift              Binding/store/snapshot models
  Engine_Backup.swift        Backup capture and packaging
  Engine_Scan.swift          Store scanning and relocation
  State_Library.swift        App state and filesystem operations
  View_*.swift               SwiftUI screens and reusable views
  Store_*.swift              JSON persistence
  Settings, theme, preview   Supporting infrastructure
Tests/
  Test_Binding.swift         Domain + engine tests
```

## Tests

`./test.sh` compiles the domain/engine sources together with the test executable and runs the assertions. Tests cover filename rendering, folder-only compression, catalog scans, relocation, legacy date repair, sorting, and status text.

## License

MIT — see [LICENSE](LICENSE).
