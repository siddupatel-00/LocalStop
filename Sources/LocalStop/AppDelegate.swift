import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastCloseDate = Date.distantPast
    private let contentController = StatusViewController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle.dashed", accessibilityDescription: "LocalStop")
            button.imagePosition = .imageOnly
            button.toolTip = "LocalStop"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 360, height: 520)
        pop.contentViewController = contentController
        pop.behavior = .transient
        pop.delegate = self
        popover = pop
    }

    func applicationWillTerminate(_ notification: Notification) {
        contentController.stopRefreshing()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard Date().timeIntervalSince(lastCloseDate) > 0.2 else { return }

        contentController.prepareToShow()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async {
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        contentController.stopRefreshing()
    }
}
