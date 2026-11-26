import AppKit
import FinderSync

final class BinderyFinderSync: FIFinderSync {
    override init() {
        super.init()
        // The menu is context-sensitive, so register broadly. Finder only asks
        // for it when the user right-clicks a file or folder.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }

        let menu = NSMenu(title: "Use Bindery")
        let root = NSMenuItem(title: "Use Bindery", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Bindery")
        let submenu = NSMenu(title: "Use Bindery")

        let unmanaged = NSMenuItem(
            title: "Add to Unmanaged",
            action: #selector(addToUnmanaged(_:)),
            keyEquivalent: ""
        )
        unmanaged.target = self
        unmanaged.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)
        submenu.addItem(unmanaged)

        let binding = NSMenuItem(
            title: "Back Up to Binding…",
            action: #selector(backUpToBinding(_:)),
            keyEquivalent: ""
        )
        binding.target = self
        binding.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        submenu.addItem(binding)

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc private func addToUnmanaged(_ sender: Any?) {
        handOff(mode: "unmanaged")
    }

    @objc private func backUpToBinding(_ sender: Any?) {
        handOff(mode: "binding")
    }

    private func handOff(mode: String) {
        let controller = FIFinderSyncController.default()
        let urls = controller.selectedItemURLs() ?? []
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])

        guard let url = URL(string: "bindery://intake?mode=\(mode)") else { return }
        NSWorkspace.shared.open(url)
    }
}
