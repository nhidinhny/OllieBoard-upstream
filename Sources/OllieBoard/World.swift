import AppKit

/// Owns the pets, drives the animation clock and coordinates access to desktop icons.
final class World {
    let desktop = DesktopIcons()
    let agents = AgentMonitor()
    let room = Room()
    private(set) var pets: [String: Pet] = [:]
    /// Mascots of running AI agent sessions, by agent process id.
    private(set) var agentPets: [Int32: Pet] = [:]
    weak var arranger: Pet?
    /// Icons the last cleaner put in place, so kicking one of them upsets that pet.
    var arranged: Set<String> = []
    weak var arrangedBy: Pet?
    private var claimed: Set<String> = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastRefresh: TimeInterval = 0

    private let agentsKey = "agentCharacters"
    private let hiddenKey = "allHidden"

    /// Quick switch: hides every character, agent mascot and the play room without forgetting who was on.
    var allHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hiddenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hiddenKey)
            pets.values.forEach { $0.setSuppressed(newValue) }
            room.setSuppressed(newValue)
        }
    }
    private let disabledKindsKey = "disabledAgentKinds"

    /// Whether running AI agents get their own characters.
    var agentsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: agentsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: agentsKey)
            if newValue { agents.start() } else { agents.stop() }
        }
    }

    /// Agent kinds switched off in the menu; their sessions get no character.
    var disabledAgentKinds: Set<AgentKind> {
        get { Set((UserDefaults.standard.stringArray(forKey: disabledKindsKey) ?? []).compactMap(AgentKind.init)) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: disabledKindsKey) }
    }

    func start() {
        desktop.refresh()
        agents.onUpdate = { [weak self] in self?.syncAgents($0) }
        if agentsEnabled { agents.start() }
        room.onMembersChange = { [weak self] in self?.pets.values.forEach { $0.moveIntoRoom() } }
        room.onMove = { [weak self] shift in self?.pets.values.forEach { $0.followRoom(by: shift) } }
        room.start()
        room.setSuppressed(allHidden)
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)   // keep animating while menus are open
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        for pet in pets.values { pet.tick(dt) }
        if now - lastRefresh > 15 {
            lastRefresh = now
            desktop.refresh()
        }
    }

    // MARK: Pets

    func setEnabled(_ character: Character, _ enabled: Bool) {
        if enabled, pets[character.id] == nil {
            let index = allCharacters.firstIndex { $0.id == character.id } ?? 0
            let f = NSScreen.main?.visibleFrame ?? NSScreen.screens[0].visibleFrame
            let x = f.minX + 140 + CGFloat(index) * 170
            let pet = Pet(character: character, world: self,
                          position: CGPoint(x: min(x, f.maxX - 60), y: f.minY + 10))
            pets[character.id] = pet
            pet.setSuppressed(allHidden)
            pet.show()
            pet.moveIntoRoom()
        } else if !enabled, let pet = pets.removeValue(forKey: character.id) {
            pet.hide()
        }
    }

    private func syncAgents(_ sessions: [Int32: AgentSession]) {
        let disabled = disabledAgentKinds
        let sessions = sessions.filter { !disabled.contains($0.value.kind) }
        for (pid, session) in sessions {
            if let pet = agentPets[pid] {
                pet.update(agent: session)
                continue
            }
            // Starts hidden; the mascot shows itself once the agent works or waits for the user.
            let character = session.kind.character(pid: pid)
            let pet = Pet(character: character, world: self, position: .zero, agent: session)
            pets[character.id] = pet
            agentPets[pid] = pet
            pet.setSuppressed(allHidden)
            pet.update(agent: session)
        }
        for (pid, pet) in agentPets where sessions[pid] == nil {
            agentPets[pid] = nil
            pet.leave { [weak self, weak pet] in
                guard let self, let pet else { return }
                self.pets[pet.character.id] = nil
                pet.hide()
            }
        }
    }

    /// Sometimes a friend (on the same side of the room walls) walks over to cheer up an upset (shy) pet.
    func requestComfort(for pet: Pet) {
        guard Double.random(in: 0..<1) < 0.6 else { return }
        let helper = pets.values.filter { $0 !== pet && $0.isAvailable && !$0.character.shy && $0.inRoom == pet.inRoom }.randomElement()
        helper?.comfort(pet)
    }

    // MARK: Icons

    func claim(_ name: String) { claimed.insert(name) }
    func release(_ name: String) { claimed.remove(name) }

    func availableIcons() -> [DesktopIcon] {
        desktop.icons.filter { !claimed.contains($0.name) }
    }

    /// A random icon among the few closest to `point`, so pets don't cross every screen for one kick.
    func pickIcon(near point: CGPoint) -> DesktopIcon? {
        let sorted = availableIcons().sorted {
            hypot($0.center.x - point.x, $0.center.y - point.y) < hypot($1.center.x - point.x, $1.center.y - point.y)
        }
        return sorted.prefix(5).randomElement()
    }

    /// Neat grid in the top-right corner of the primary screen, filled column by column like Finder does.
    func gridSlots(count: Int) -> [CGPoint] {
        guard let f = NSScreen.screens.first?.visibleFrame else { return [] }
        let spacing: CGFloat = 100
        let rows = max(1, Int((f.height - 70) / spacing))
        return (0..<count).map { i in
            CGPoint(x: f.maxX - 70 - CGFloat(i / rows) * spacing,
                    y: f.maxY - 70 - CGFloat(i % rows) * spacing)
        }
    }
}
