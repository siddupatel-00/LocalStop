import AppKit

final class StatusViewController: NSViewController, NSSearchFieldDelegate {
    private let settings = Settings.shared
    private var servers: [LocalServer] = []
    private var refreshTimer: Timer?
    private var scanGeneration = 0
    private var editingPort: Int?

    private let countLabel = NSTextField(labelWithString: "RUNNING SERVERS  ·  0")
    private let refreshButton = NSButton()
    private let quitButton = NSButton()
    private let searchField = NSSearchField()
    private let sortButton = PillButton(iconName: "arrow.up.arrow.down")

    private let listArea = NSView()
    private let scrollView = NSScrollView()
    private let listContainer = FlippedView()
    private let listStack = NSStackView()
    private let emptyState = NSStackView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 520))
        view = root

        buildHeader(in: root)
        buildList(in: root)
    }

    func prepareToShow() {
        view.layoutSubtreeIfNeeded()
        refresh()
        startRefreshing()
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func buildHeader(in root: NSView) {
        let title = NSTextField(labelWithString: "LocalStop")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false

        configureIconButton(refreshButton, symbol: "arrow.clockwise", tooltip: "Refresh servers", action: #selector(refreshNow))
        configureIconButton(quitButton, symbol: "power", tooltip: "Quit LocalStop", action: #selector(quit))

        root.addSubview(title)
        root.addSubview(refreshButton)
        root.addSubview(quitButton)

        searchField.placeholderString = "Search ports, processes, PIDs"
        searchField.font = .systemFont(ofSize: 12)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)

        updateSortButtonTitle()
        sortButton.toolTip = "Change sorting"
        sortButton.target = self
        sortButton.action = #selector(cycleSort)
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sortButton)

        countLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(countLabel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8),

            refreshButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            refreshButton.widthAnchor.constraint(equalToConstant: 24),
            refreshButton.heightAnchor.constraint(equalToConstant: 24),

            quitButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            quitButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            quitButton.widthAnchor.constraint(equalToConstant: 24),
            quitButton.heightAnchor.constraint(equalToConstant: 24),

            refreshButton.trailingAnchor.constraint(equalTo: quitButton.leadingAnchor, constant: -8),

            searchField.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 30),

            sortButton.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sortButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            sortButton.heightAnchor.constraint(equalToConstant: 28),
            sortButton.widthAnchor.constraint(equalToConstant: 112),

            countLabel.centerYAnchor.constraint(equalTo: sortButton.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: sortButton.trailingAnchor, constant: 8)
        ])
    }

    private func buildList(in root: NSView) {
        listArea.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(listArea)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        listContainer.frame = NSRect(x: 0, y: 0, width: 360, height: 200)
        scrollView.documentView = listContainer

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 8
        listStack.translatesAutoresizingMaskIntoConstraints = true
        listContainer.addSubview(listStack)

        listArea.addSubview(scrollView)

        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 6
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        emptyIcon.contentTintColor = .tertiaryLabelColor

        emptyTitle.font = .systemFont(ofSize: 13, weight: .medium)
        emptyTitle.textColor = .secondaryLabelColor

        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.textColor = .tertiaryLabelColor

        updateEmptyState(isSearching: false)

        emptyState.addArrangedSubview(emptyIcon)
        emptyState.addArrangedSubview(emptyTitle)
        emptyState.addArrangedSubview(emptyHint)
        listArea.addSubview(emptyState)
        scrollView.isHidden = true
        emptyState.isHidden = false

        NSLayoutConstraint.activate([
            listArea.topAnchor.constraint(equalTo: sortButton.bottomAnchor, constant: 8),
            listArea.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            listArea.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            listArea.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: listArea.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: listArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listArea.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listArea.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: listArea.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: listArea.centerYAnchor)
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func cycleSort() {
        settings.sortMode = settings.sortMode.next
        updateSortButtonTitle()
        updateList()
    }

    private func updateSortButtonTitle() {
        sortButton.setLabel("Sort: \(settings.sortMode.label)")
    }

    private var searchQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var visibleServers: [LocalServer] {
        let query = searchQuery
        var result = servers

        if !query.isEmpty {
            result = result.filter { server in
                if String(server.port).contains(query) { return true }
                if String(server.pid).contains(query) { return true }
                if server.command.lowercased().contains(query) { return true }
                if server.address.lowercased().contains(query) { return true }
                if let name = settings.customName(for: server.port), name.lowercased().contains(query) {
                    return true
                }
                return false
            }
        }

        switch settings.sortMode {
        case .port:
            result.sort { $0.port < $1.port }
        case .name:
            result.sort {
                let left = displayName(for: $0)
                let right = displayName(for: $1)
                let order = left.localizedCaseInsensitiveCompare(right)
                return order == .orderedSame ? $0.port < $1.port : order == .orderedAscending
            }
        case .pid:
            result.sort { $0.pid < $1.pid }
        }

        return result
    }

    private func displayName(for server: LocalServer) -> String {
        settings.customName(for: server.port) ?? server.command
    }

    private func updateEmptyState(isSearching: Bool) {
        let symbol = isSearching ? "magnifyingglass" : "rectangle.on.rectangle.dashed"
        emptyIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .regular))
        emptyTitle.stringValue = isSearching ? "No matches" : "No local servers running"
        emptyHint.stringValue = isSearching
            ? "Try a different search."
            : "Start a dev server and it shows up here."
    }

    private func startRefreshing() {
        stopRefreshing()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refresh() {
        scanGeneration += 1
        let generation = scanGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ServerScanner.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                guard result != self.servers else { return }
                self.servers = result
                if self.view.window != nil {
                    self.updateList()
                }
            }
        }
    }

    private func updateList() {
        let portToRestore = editingPort

        for arranged in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        let visible = visibleServers
        let searching = !searchQuery.isEmpty

        for server in visible {
            listStack.addArrangedSubview(makeRow(for: server))
        }

        if searching {
            countLabel.stringValue = "SHOWING  \(visible.count)  OF  \(servers.count)"
        } else {
            countLabel.stringValue = "RUNNING SERVERS  ·  \(servers.count)"
        }

        updateEmptyState(isSearching: searching)
        emptyState.isHidden = !visible.isEmpty
        scrollView.isHidden = visible.isEmpty

        layoutList()

        if let port = portToRestore, visible.contains(where: { $0.port == port }) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for case let field as NSTextField in self.listStack.arrangedSubviews.flatMap({ $0.subviewsRecursive() }) where field.tag == port {
                    if let window = field.window {
                        window.makeFirstResponder(field)
                        if let editor = field.currentEditor() {
                            editor.selectedRange = NSRange(location: 0, length: (field.stringValue as NSString).length)
                        }
                    }
                    break
                }
            }
        }
    }

    private func layoutList() {
        let width = max(scrollView.contentSize.width, 360)
        if listStack.arrangedSubviews.isEmpty {
            listContainer.frame = NSRect(x: 0, y: 0, width: width, height: scrollView.contentSize.height)
            return
        }


        let stackWidth = width - 28

        listStack.frame = NSRect(x: 14, y: 8, width: stackWidth, height: 0)
        listStack.layoutSubtreeIfNeeded()

        let height = listStack.fittingSize.height
        listStack.frame = NSRect(x: 14, y: 8, width: stackWidth, height: height)

        let viewportHeight = scrollView.contentSize.height
        listContainer.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(height + 16, viewportHeight)
        )
    }

    private func makeRow(for server: LocalServer) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        row.translatesAutoresizingMaskIntoConstraints = false

        let badge = PortBadge(port: server.port)
        badge.translatesAutoresizingMaskIntoConstraints = false

        let customName = settings.customName(for: server.port)

        let title = NSTextField()
        title.stringValue = customName ?? server.command
        title.isEditable = true
        title.isSelectable = true
        title.isBordered = false
        title.isBezeled = false
        title.drawsBackground = false
        title.focusRingType = .none
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.tag = server.port
        title.delegate = self
        title.toolTip = "Click to rename"
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detailText = customName != nil
            ? "\(server.command) · pid \(server.pid)"
            : "\(server.address) · pid \(server.pid)"
        let detail = NSTextField(labelWithString: detailText)
        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [title, detail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let pencil = IconButton(systemName: "pencil", tooltip: "Rename", pointSize: 15) { [weak title] _ in
            guard let title, let window = title.window else { return }
            window.makeFirstResponder(title)
            DispatchQueue.main.async {
                if let editor = title.currentEditor() {
                    editor.selectedRange = NSRange(location: 0, length: (title.stringValue as NSString).length)
                }
            }
        }
        pencil.translatesAutoresizingMaskIntoConstraints = false

        let stop = CircleButton(symbolName: "stop.fill", pointSize: 11, tint: .systemRed, tooltip: "Stop port \(server.port)") { [weak self] button in
            button.isEnabled = false
            self?.stop(server, button: button)
        }
        stop.translatesAutoresizingMaskIntoConstraints = false

        let open = CircleButton(symbolName: "arrow.up.right.square", pointSize: 11, tint: .secondaryLabelColor, tooltip: "Open in browser") { _ in
            var host = server.address
            if host.isEmpty || host == "*" { host = "localhost" }
            if host.contains(":") && !host.hasPrefix("[") { host = "[\(host)]" }
            if let url = URL(string: "http://\(host):\(server.port)") {
                NSWorkspace.shared.open(url)
            }
        }
        open.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(badge)
        row.addSubview(textStack)
        row.addSubview(pencil)
        row.addSubview(open)
        row.addSubview(stop)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 54),

            badge.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 54),
            badge.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: pencil.leadingAnchor, constant: -6),

            pencil.trailingAnchor.constraint(equalTo: open.leadingAnchor, constant: -6),
            pencil.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pencil.widthAnchor.constraint(equalToConstant: 28),
            pencil.heightAnchor.constraint(equalToConstant: 28),

            open.trailingAnchor.constraint(equalTo: stop.leadingAnchor, constant: -6),
            open.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            open.widthAnchor.constraint(equalToConstant: 26),
            open.heightAnchor.constraint(equalToConstant: 26),

            stop.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            stop.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            stop.widthAnchor.constraint(equalToConstant: 26),
            stop.heightAnchor.constraint(equalToConstant: 26)
        ])

        return row
    }

    private func stop(_ server: LocalServer, button: CircleButton?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = ServerScanner.stop(server)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !success {
                    button?.isEnabled = true
                    self.presentStopError(for: server)
                }
                self.refresh()
            }
        }
    }

    private func presentStopError(for server: LocalServer) {
        let alert = NSAlert()
        alert.messageText = "Couldn't stop \(server.command)"
        alert.informativeText = "The process on port \(server.port) may have already exited."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutList()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field.tag > 0 else { return }
        editingPort = field.tag
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }

        if field === searchField {
            updateList()
            return
        }

        guard field.tag > 0 else { return }
        settings.setCustomName(field.stringValue, for: field.tag)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field.tag > 0 else { return }

        if let custom = settings.customName(for: field.tag) {
            field.stringValue = custom
        } else if let server = servers.first(where: { $0.port == field.tag }) {
            field.stringValue = server.command
        }

        editingPort = nil
        if settings.sortMode == .name {
            DispatchQueue.main.async { [weak self] in
                self?.updateList()
            }
        }
    }
}

final class PortBadge: NSView {
    init(port: Int) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor

        let label = NSTextField(labelWithString: String(port))
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class CircleButton: NSButton {
    private let handler: (CircleButton) -> Void
    private let iconView = NSImageView()

    init(symbolName: String, pointSize: CGFloat, tint: NSColor, tooltip: String, handler: @escaping (CircleButton) -> Void) {
        self.handler = handler
        super.init(frame: .zero)

        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        toolTip = tooltip

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        iconView.contentTintColor = tint
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.5
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return super.hitTest(point) == nil ? nil : self
    }

    @objc private func fire() {
        handler(self)
    }
}

final class IconButton: NSButton {
    private let handler: (NSButton) -> Void

    init(systemName: String, tooltip: String, pointSize: CGFloat = 11, handler: @escaping (NSButton) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.image = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        self.isBordered = false
        self.imagePosition = .imageOnly
        self.contentTintColor = .secondaryLabelColor
        self.toolTip = tooltip
        self.target = self
        self.action = #selector(fire)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func fire() {
        handler(self)
    }
}


final class PillButton: NSButton {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var handler: ((PillButton) -> Void)?

    init(
        iconName: String? = nil,
        textColor: NSColor = .secondaryLabelColor,
        borderColor: NSColor = NSColor.labelColor.withAlphaComponent(0.22),
        fillColor: NSColor = NSColor.labelColor.withAlphaComponent(0.06)
    ) {
        super.init(frame: .zero)

        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = fillColor.cgColor

        iconView.contentTintColor = textColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = textColor
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let iconName {
            setSymbol(iconName)
            stack.addArrangedSubview(iconView)
        }
        stack.addArrangedSubview(label)
        addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ]

        if iconName != nil {
            constraints.append(iconView.widthAnchor.constraint(equalToConstant: 14))
            constraints.append(iconView.heightAnchor.constraint(equalToConstant: 14))
        }

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSymbol(_ name: String) {
        iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
    }

    func setLabel(_ text: String) {
        label.stringValue = text
    }

    func onClick(_ handler: @escaping (PillButton) -> Void) {
        self.handler = handler
        target = self
        action = #selector(fire)
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.5
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return super.hitTest(point) == nil ? nil : self
    }

    @objc private func fire() {
        handler?(self)
    }
}


extension NSView {
    func subviewsRecursive() -> [NSView] {
        var result: [NSView] = [self]
        for sub in subviews {
            result.append(contentsOf: sub.subviewsRecursive())
        }
        return result
    }
}
