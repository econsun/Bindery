import AppKit
import SwiftUI

struct BindingContextMenuSurface: NSViewRepresentable {
    let binding: BackupBinding
    let categories: [String]
    let open: () -> Void
    let run: () -> Void
    let editNote: () -> Void
    let favorite: () -> Void
    let move: (String) -> Void
    let reveal: () -> Void
    let delete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeNSView(context: Context) -> RightClickSurface {
        let view = RightClickSurface()
        view.makeMenu = { context.coordinator.makeMenu() }
        return view
    }

    func updateNSView(_ nsView: RightClickSurface, context: Context) {
        context.coordinator.owner = self
        nsView.makeMenu = { context.coordinator.makeMenu() }
    }

    final class Coordinator: NSObject {
        var owner: BindingContextMenuSurface
        private var actions: [Int: () -> Void] = [:]
        private weak var activeMenu: NSMenu?

        init(owner: BindingContextMenuSurface) { self.owner = owner }

        func makeMenu() -> NSMenu {
            actions.removeAll()
            let menu = NSMenu()
            menu.autoenablesItems = false
            if let descriptor = NSFont.systemFont(ofSize: 13).fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: 13) {
                menu.font = font
            }
            activeMenu = menu

            menu.addItem(item("Open Details", symbol: "info.circle", tag: 1, action: owner.open))
            menu.addItem(item("Backup Now", symbol: "arrow.triangle.2.circlepath", tag: 2, action: owner.run))
            menu.addItem(item("Edit Project…", symbol: "slider.horizontal.3", tag: 4, action: owner.editNote))
            menu.addItem(.separator())
            menu.addItem(item(
                owner.binding.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                symbol: owner.binding.isFavorite ? "star.fill" : "star",
                tag: 3,
                action: owner.favorite
            ))

            let categoryItem = NSMenuItem(title: "Move to Category", action: nil, keyEquivalent: "")
            categoryItem.image = symbolImage("folder")
            let categoryMenu = NSMenu()
            categoryMenu.font = menu.font
            for (index, category) in owner.categories.enumerated() {
                categoryMenu.addItem(item(category, symbol: nil, tag: 100 + index, action: { [weak self] in self?.owner.move(category) }))
            }
            categoryItem.submenu = categoryMenu
            menu.addItem(categoryItem)
            menu.addItem(.separator())
            menu.addItem(item("Show Source in Finder", symbol: "magnifyingglass", tag: 5, action: owner.reveal))
            menu.addItem(.separator())
            menu.addItem(item("Delete Project…", symbol: "trash", tag: 6, action: owner.delete))
            return menu
        }

        private func item(_ title: String, symbol: String?, tag: Int, action: @escaping () -> Void) -> NSMenuItem {
            actions[tag] = action
            let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.isEnabled = true
            if let symbol { item.image = symbolImage(symbol) }
            return item
        }

        private func symbolImage(_ name: String) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.size = NSSize(width: 13, height: 13)
            return image
        }

        @objc private func invoke(_ sender: NSMenuItem) { actions[sender.tag]?() }
    }
}

final class RightClickSurface: NSView {
    var makeMenu: (() -> NSMenu)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class HorizontalScrollSurface: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .scrollWheel ? self : nil
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontal = event.scrollingDeltaX
        if abs(horizontal) > abs(event.scrollingDeltaY) {
            onScroll?(horizontal)
        }
        super.scrollWheel(with: event)
    }
}

struct HorizontalScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> HorizontalScrollSurface {
        let view = HorizontalScrollSurface()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: HorizontalScrollSurface, context: Context) {
        nsView.onScroll = onScroll
    }
}
