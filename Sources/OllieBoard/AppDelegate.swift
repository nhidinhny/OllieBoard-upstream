import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let world = World()
    private var statusItem: NSStatusItem!
    private let updater = Updater()
    private var updateTimer: Timer?
    private let enabledKey = "enabledCharacters"

    private var enabledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? ["nezuko"]) }
        set { UserDefaults.standard.set(Array(newValue), forKey: enabledKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "OllieBoard")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        world.start()
        for character in allCharacters where enabledIDs.contains(character.id) {
            world.setEnabled(character, true)
        }
        updateStatusIcon()

        if Updater.canUpdate {
            updater.onInstallFailed = { message in
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = ui(.updateFailed)
                alert.informativeText = message
                alert.runModal()
            }
            updater.check()
            updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.updater.check() }
        }
    }

    // Rebuilt every time it opens so warnings reflect Finder's current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addItem(menu, world.allHidden ? ui(.showAll) : ui(.hideAll), #selector(toggleAllHidden))
        menu.addItem(.separator())
        menu.addItem(withTitle: ui(.characters), action: nil, keyEquivalent: "").isEnabled = false
        for group in characterGroups(#selector(toggleCharacter(_:)), isOn: { self.world.pets[$0.id] != nil }) {
            menu.addItem(group)
        }
        menu.addItem(withTitle: ui(.playRoom), action: nil, keyEquivalent: "").submenu = roomMenu()

        let languageItem = menu.addItem(withTitle: "Ngôn ngữ / Language / 言語", action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for language in Language.allCases {
            let item = languages.addItem(withTitle: language.title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == Language.current ? .on : .off
        }
        languageItem.submenu = languages

        menu.addItem(.separator())
        let agentsItem = menu.addItem(withTitle: ui(.agentCharacters), action: #selector(toggleAgents), keyEquivalent: "")
        agentsItem.target = self
        agentsItem.state = world.agentsEnabled ? .on : .off
        if world.agentsEnabled {
            let kinds = NSMenu()
            for kind in AgentKind.allCases {
                let item = kinds.addItem(withTitle: kind.title, action: #selector(toggleAgentKind(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = kind.rawValue
                item.state = world.disabledAgentKinds.contains(kind) ? .off : .on
            }
            menu.addItem(withTitle: "    " + ui(.chooseAgents), action: nil, keyEquivalent: "").submenu = kinds
            for pet in world.agentPets.values.sorted(by: { ($0.tag ?? "") < ($1.tag ?? "") }) {
                guard let agent = pet.agent else { continue }
                let state: String
                switch agent.state {
                case .idle: state = ui(.agentIdle)
                case .working: state = ui(.agentWorking)
                case .done: state = ui(.agentDone)
                case .needsInput: state = ui(.agentNeedsYou)
                }
                menu.addItem(withTitle: "    \(pet.tag ?? agent.kind.title) — \(state)", action: nil, keyEquivalent: "").isEnabled = false
            }
            if ClaudeHooks.isInstalled {
                menu.addItem(withTitle: "    " + ui(.hookInstalled), action: nil, keyEquivalent: "").isEnabled = false
            } else {
                addItem(menu, "    " + ui(.installHook), #selector(installClaudeHooks))
            }
        }

        if let error = world.desktop.lastError {
            menu.addItem(.separator())
            let warn = menu.addItem(withTitle: ui(.finderBlocked), action: nil, keyEquivalent: "")
            warn.toolTip = error
            warn.isEnabled = false
            addItem(menu, ui(.openAutomation), #selector(openAutomationSettings))
        } else if world.desktop.iconsArePinned {
            menu.addItem(.separator())
            menu.addItem(withTitle: ui(.sortByLocked), action: nil, keyEquivalent: "").isEnabled = false
            addItem(menu, ui(.turnOffSortBy), #selector(disableAutoArrange))
        }

        menu.addItem(.separator())
        if Updater.canUpdate { addUpdateItem(menu) }
        addItem(menu, ui(.quit), #selector(quit), key: "q")
    }

    /// One item that shows where the update check is and, when a newer version is out, installs it.
    private func addUpdateItem(_ menu: NSMenu) {
        let current = Updater.currentVersion
        switch updater.state {
        case .available(let version, _):
            addItem(menu, ui(.updateAvailable, version), #selector(installUpdate))
        case .installing:
            menu.addItem(withTitle: ui(.installingUpdate), action: nil, keyEquivalent: "").isEnabled = false
        case .checking:
            menu.addItem(withTitle: ui(.checkingUpdates), action: nil, keyEquivalent: "").isEnabled = false
        case .upToDate:
            addItem(menu, ui(.upToDate, current), #selector(checkForUpdates))
        case .idle:
            addItem(menu, ui(.checkUpdates, current), #selector(checkForUpdates))
        case .failed(let message):
            let item = menu.addItem(withTitle: ui(.checkUpdates, current), action: #selector(checkForUpdates), keyEquivalent: "")
            item.target = self
            item.toolTip = message
        }
    }

    private func roomMenu() -> NSMenu {
        let room = world.room
        let menu = NSMenu()
        let open = menu.addItem(withTitle: ui(.showRoom), action: #selector(toggleRoom), keyEquivalent: "")
        open.target = self
        open.state = room.isOpen ? .on : .off
        let scenes = NSMenu()
        for scene in RoomScene.allCases {
            let item = scenes.addItem(withTitle: scene.title, action: #selector(setRoomScene(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scene.rawValue
            item.state = scene == room.scene ? .on : .off
        }
        menu.addItem(withTitle: ui(.scenery), action: nil, keyEquivalent: "").submenu = scenes
        menu.addItem(.separator())
        menu.addItem(withTitle: ui(.inRoom), action: nil, keyEquivalent: "").isEnabled = false
        for group in characterGroups(#selector(toggleRoomMember(_:)), isOn: { room.members.contains($0.id) }) {
            menu.addItem(group)
        }
        menu.addItem(.separator())
        let edit = menu.addItem(withTitle: ui(.editRoom), action: #selector(toggleRoomEditing), keyEquivalent: "")
        edit.target = self
        edit.state = room.editing ? .on : .off
        return menu
    }

    /// One submenu per series listing its characters as checkboxes, so several can be toggled without the menu
    /// closing; each checkbox's tag is the character's index in allCharacters.
    /// A series shows a dash when some of its characters are on.
    private func characterGroups(_ action: Selector, isOn: (Character) -> Bool) -> [NSMenuItem] {
        Series.allCases.compactMap { series -> NSMenuItem? in
            let members = allCharacters.enumerated().filter { $0.element.series == series }
            guard !members.isEmpty else { return nil }
            let submenu = NSMenu()
            for (i, character) in members {
                let box = NSButton(checkboxWithTitle: character.name, target: self, action: action)
                box.tag = i
                box.state = isOn(character) ? .on : .off
                box.sizeToFit()
                let row = NSView(frame: CGRect(x: 0, y: 0, width: box.frame.width + 28, height: box.frame.height + 6))
                box.setFrameOrigin(CGPoint(x: 14, y: 3))
                row.addSubview(box)
                submenu.addItem(withTitle: character.name, action: nil, keyEquivalent: "").view = row
            }
            let group = NSMenuItem(title: series.title, action: nil, keyEquivalent: "")
            group.submenu = submenu
            group.state = members.contains { isOn($0.element) } ? .mixed : .off
            return group
        }
    }

    /// Updates a series' dash after one of its checkboxes was clicked (the menu stays open).
    private func refreshGroup(of box: NSButton) {
        guard let group = box.enclosingMenuItem?.parent else { return }
        let anyOn = group.submenu?.items.contains { ($0.view?.subviews.first as? NSButton)?.state == .on } ?? false
        group.state = anyOn ? .mixed : .off
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
    }

    @objc private func toggleAllHidden() {
        world.allHidden.toggle()
        updateStatusIcon()
    }

    /// The paw is dimmed while everything is hidden.
    private func updateStatusIcon() {
        statusItem.button?.appearsDisabled = world.allHidden
    }

    @objc private func toggleCharacter(_ sender: NSButton) {
        let character = allCharacters[sender.tag]
        let enable = world.pets[character.id] == nil
        world.setEnabled(character, enable)
        if enable { enabledIDs.insert(character.id) } else { enabledIDs.remove(character.id) }
        refreshGroup(of: sender)
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let language = Language(rawValue: raw) {
            Language.current = language
        }
    }

    @objc private func toggleAgents() { world.agentsEnabled.toggle() }

    @objc private func toggleAgentKind(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = AgentKind(rawValue: raw) else { return }
        if world.disabledAgentKinds.contains(kind) { world.disabledAgentKinds.remove(kind) } else { world.disabledAgentKinds.insert(kind) }
    }

    @objc private func toggleRoom() { world.room.setOpen(!world.room.isOpen) }

    /// Putting a character in the room also brings it out if it was turned off.
    @objc private func toggleRoomMember(_ sender: NSButton) {
        let character = allCharacters[sender.tag]
        let inside = !world.room.members.contains(character.id)
        world.room.setMember(character.id, inside)
        if inside && world.pets[character.id] == nil {
            world.setEnabled(character, true)
            enabledIDs.insert(character.id)
        }
        refreshGroup(of: sender)
    }

    @objc private func setRoomScene(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let scene = RoomScene(rawValue: raw) {
            world.room.setScene(scene)
        }
    }

    @objc private func toggleRoomEditing() { world.room.setEditing(!world.room.editing) }

    @objc private func installClaudeHooks() {
        NSApp.activate(ignoringOtherApps: true)
        let confirm = NSAlert()
        confirm.messageText = ui(.hookQuestion)
        confirm.informativeText = ui(.hookExplain, ClaudeHooks.settings.path)
        confirm.addButton(withTitle: ui(.install))
        confirm.addButton(withTitle: ui(.cancel))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let result = NSAlert()
        do {
            try ClaudeHooks.install()
            result.messageText = ui(.hookDone)
            result.informativeText = ui(.hookDoneInfo)
        } catch {
            result.alertStyle = .warning
            result.messageText = ui(.hookFailed)
            result.informativeText = error.localizedDescription
        }
        result.runModal()
    }

    @objc private func checkForUpdates() { updater.check() }
    @objc private func installUpdate() { updater.install() }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    @objc private func disableAutoArrange() { world.desktop.disableAutoArrange {} }

    @objc private func quit() { NSApp.terminate(nil) }
}
