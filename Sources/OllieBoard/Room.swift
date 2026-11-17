import AppKit

/// What the room looks like: the default cozy room, one scene per supported series, and the UN hall for politics.
enum RoomScene: String, CaseIterable {
    case cozy, kimetsu, onePiece, attackOnTitan, jujutsuKaisen, hunterXHunter, unitedNations

    var title: String {
        switch self {
        case .cozy: return ui(.sceneCozy)
        case .kimetsu: return ui(.sceneKimetsu)
        case .onePiece: return ui(.sceneOnePiece)
        case .attackOnTitan: return ui(.sceneAttackOnTitan)
        case .jujutsuKaisen: return ui(.sceneJujutsuKaisen)
        case .hunterXHunter: return ui(.sceneHunterXHunter)
        case .unitedNations: return ui(.sceneUnitedNations)
        }
    }
}

/// A play room drawn on the desktop, under the app windows. Characters put in it stay on its floor
/// and only play with each other.
final class Room {
    static let minSize = CGSize(width: 320, height: 240)
    private let openKey = "roomOpen", membersKey = "roomMembers", frameKey = "roomFrame", sceneKey = "roomScene"

    /// Called when the room opens or gains a member, so members outside can pop in.
    var onMembersChange: (() -> Void)?
    /// Called with the shift of the room's origin after it is moved or resized, so members move along.
    var onMove: ((CGVector) -> Void)?

    private(set) var isOpen: Bool
    private(set) var members: Set<String>
    private(set) var editing = false
    /// "Hide all" in the menu: the room window stays away without touching the saved open state.
    private(set) var suppressed = false
    private(set) var frame: CGRect
    private(set) var scene: RoomScene

    private lazy var view: RoomView = {
        let view = RoomView(frame: CGRect(origin: .zero, size: frame.size))
        view.room = self
        view.autoresizingMask = [.width, .height]
        return view
    }()

    private lazy var window: NSPanel = {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = view
        return window
    }()

    init() {
        let defaults = UserDefaults.standard
        isOpen = defaults.bool(forKey: openKey)
        members = Set(defaults.stringArray(forKey: membersKey) ?? [])
        scene = defaults.string(forKey: sceneKey).flatMap(RoomScene.init) ?? .cozy
        let saved = defaults.string(forKey: frameKey).map(NSRectFromString)
        // Fall back to the default spot when the screen it was on is gone.
        if let saved, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            frame = saved
        } else {
            let f = NSScreen.main?.visibleFrame ?? NSScreen.screens[0].visibleFrame
            frame = CGRect(x: f.minX + 40, y: f.minY + 20, width: min(600, f.width - 80), height: 300)
        }
    }

    func start() { apply() }

    // MARK: Geometry

    /// Height of the wooden floor along the bottom of the room.
    var floorHeight: CGFloat { min(max(70, frame.height * 0.36), frame.height - 150) }

    /// Where members' feet may be: on the floor, with the whole body inside the walls.
    var floor: CGRect {
        CGRect(x: frame.minX + 36, y: frame.minY + 10, width: frame.width - 72, height: floorHeight - 24)
    }

    /// Where a member the user is holding may be dragged: anywhere inside the room.
    func clampHeld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, floor.minX), floor.maxX), y: min(max(p.y, floor.minY), frame.maxY - 140))
    }

    func randomSpot() -> CGPoint {
        CGPoint(x: .random(in: floor.minX...floor.maxX), y: .random(in: floor.minY...floor.maxY))
    }

    /// Under the desktop icons; above everything while it is being moved or resized.
    private var level: NSWindow.Level {
        editing ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    }

    /// Members stand just above the room (and the icons), so app windows cover the room and its members alike.
    var petLevel: NSWindow.Level { NSWindow.Level(rawValue: level.rawValue + 1) }

    // MARK: Changes from the menu

    func setSuppressed(_ on: Bool) {
        suppressed = on
        apply()
    }

    func setOpen(_ open: Bool) {
        isOpen = open
        if !open { editing = false }
        UserDefaults.standard.set(open, forKey: openKey)
        apply()
        onMembersChange?()
    }

    func setMember(_ id: String, _ inside: Bool) {
        if inside { members.insert(id) } else { members.remove(id) }
        UserDefaults.standard.set(Array(members), forKey: membersKey)
        if inside && !isOpen { setOpen(true) } else { onMembersChange?() }
    }

    func setScene(_ newScene: RoomScene) {
        scene = newScene
        UserDefaults.standard.set(newScene.rawValue, forKey: sceneKey)
        if !isOpen { setOpen(true) } else { view.needsDisplay = true }
    }

    func setEditing(_ on: Bool) {
        if on && !isOpen { setOpen(true) }
        editing = on
        apply()
    }

    /// Moves or resizes the room (while editing), taking its members along.
    func setFrame(_ newFrame: CGRect) {
        let shift = CGVector(dx: newFrame.minX - frame.minX, dy: newFrame.minY - frame.minY)
        frame = newFrame
        window.setFrame(newFrame, display: true)
        onMove?(shift)
    }

    func saveFrame() { UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey) }

    private func apply() {
        guard isOpen, !suppressed else { return window.orderOut(nil) }
        window.setFrame(frame, display: false)
        window.level = level
        window.ignoresMouseEvents = !editing
        view.needsDisplay = true
        window.orderFrontRegardless()
    }
}

/// Paints the room's scene (see RoomScenes.swift); the cozy default is a striped wall with a window and a clock,
/// wooden floor and a rug.
/// While editing it can be dragged around, resized from the bottom-right corner and closed with its done button.
final class RoomView: NSView {
    weak var room: Room?

    private var gripRect: CGRect { CGRect(x: bounds.maxX - 30, y: 0, width: 30, height: 30) }
    private var doneRect: CGRect { CGRect(x: bounds.maxX - 74, y: bounds.maxY - 36, width: 62, height: 24) }

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    func fill(_ rect: CGRect, _ c: NSColor) {
        c.setFill()
        rect.fill(using: .sourceOver)
    }

    override func draw(_ dirtyRect: NSRect) {
        let floorH = room?.floorHeight ?? bounds.height * 0.36
        let wall = CGRect(x: 0, y: floorH, width: bounds.width, height: bounds.height - floorH)
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 14, yRadius: 14)

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        switch room?.scene ?? .cozy {
        case .cozy: drawCozy(wall: wall, floorH: floorH)
        case .kimetsu: drawWisteriaNight(wall: wall, floorH: floorH)
        case .onePiece: drawSunnyDeck(wall: wall, floorH: floorH)
        case .attackOnTitan: drawWallMaria(wall: wall, floorH: floorH)
        case .jujutsuKaisen: drawJujutsuHigh(wall: wall, floorH: floorH)
        case .hunterXHunter: drawWhaleIsland(wall: wall, floorH: floorH)
        case .unitedNations: drawAssemblyHall(wall: wall, floorH: floorH)
        }
        NSGraphicsContext.restoreGraphicsState()
        color(120, 78, 52, 0.95).setStroke()
        outline.lineWidth = 3
        outline.stroke()

        if room?.editing == true { drawEditing() }
    }

    private func drawCozy(wall: CGRect, floorH: CGFloat) {
        fill(wall, color(253, 240, 232, 0.94))
        for x in stride(from: CGFloat(14), to: bounds.width, by: 38) {
            fill(CGRect(x: x, y: floorH, width: 16, height: wall.height), color(249, 224, 220, 0.94))
        }
        drawWindow(in: wall)
        drawClock(in: wall)

        fill(CGRect(x: 0, y: 0, width: bounds.width, height: floorH), color(206, 150, 100, 0.97))
        let plank: CGFloat = 16
        for (row, y) in stride(from: CGFloat(0), to: floorH, by: plank).enumerated() {
            fill(CGRect(x: 0, y: y, width: bounds.width, height: 1.5), color(168, 112, 70, 0.9))
            for x in stride(from: row % 2 == 0 ? CGFloat(30) : 75, to: bounds.width, by: 90) {
                fill(CGRect(x: x, y: y, width: 1.5, height: plank), color(168, 112, 70, 0.7))
            }
        }
        let rugWidth = min(bounds.width * 0.55, 340)
        let rug = CGRect(x: bounds.midX - rugWidth / 2, y: floorH * 0.14, width: rugWidth, height: floorH * 0.62)
        color(240, 160, 172, 0.95).setFill()
        NSBezierPath(ovalIn: rug).fill()
        color(250, 206, 210, 0.95).setFill()
        NSBezierPath(ovalIn: rug.insetBy(dx: 12, dy: 7)).fill()
        fill(CGRect(x: 0, y: floorH - 2, width: bounds.width, height: 9), color(150, 98, 64, 0.97))
    }

    private func drawWindow(in wall: CGRect) {
        guard wall.height >= 90 else { return }
        let w = min(140, bounds.width * 0.24), h = min(96, wall.height * 0.56)
        let frame = CGRect(x: bounds.width * 0.14, y: wall.midY - h / 2 + 6, width: w, height: h)
        fill(frame, color(255, 255, 255))
        let glass = frame.insetBy(dx: 6, dy: 6)
        NSGradient(starting: color(170, 214, 245), ending: color(222, 240, 252))!.draw(in: glass, angle: 90)
        color(255, 255, 255, 0.95).setFill()
        let cloud = CGPoint(x: glass.minX + glass.width * 0.32, y: glass.minY + glass.height * 0.62)
        for (dx, dy, r) in [(-12.0, 0.0, 8.0), (0.0, 4.0, 11.0), (13.0, 0.0, 8.0)] {
            NSBezierPath(ovalIn: CGRect(x: cloud.x + dx - r, y: cloud.y + dy - r, width: r * 2, height: r * 2)).fill()
        }
        fill(CGRect(x: glass.midX - 2, y: glass.minY, width: 4, height: glass.height), color(255, 255, 255))
        fill(CGRect(x: glass.minX, y: glass.midY - 2, width: glass.width, height: 4), color(255, 255, 255))
        fill(CGRect(x: frame.minX - 6, y: frame.minY - 6, width: frame.width + 12, height: 6), color(150, 98, 64))
    }

    private func drawClock(in wall: CGRect) {
        guard wall.height >= 90, bounds.width >= 360 else { return }
        let r = min(22, wall.height * 0.18)
        let c = CGPoint(x: bounds.width * 0.76, y: wall.midY + 14)
        let face = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        color(255, 255, 255).setFill()
        NSBezierPath(ovalIn: face).fill()
        color(150, 98, 64).setStroke()
        let rim = NSBezierPath(ovalIn: face)
        rim.lineWidth = 3
        rim.stroke()
        let hands = NSBezierPath()
        hands.move(to: CGPoint(x: c.x, y: c.y + r * 0.62))
        hands.line(to: c)
        hands.line(to: CGPoint(x: c.x + r * 0.45, y: c.y))
        hands.lineWidth = 2.2
        hands.lineCapStyle = .round
        color(90, 60, 45).setStroke()
        hands.stroke()
    }

    private func drawEditing() {
        let accent = NSColor.controlAccentColor
        let dashed = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 12, yRadius: 12)
        dashed.setLineDash([8, 5], count: 2, phase: 0)
        dashed.lineWidth = 2.5
        accent.setStroke()
        dashed.stroke()

        let grip = NSBezierPath()
        for i in 0..<3 {
            let d = CGFloat(8 + i * 6)
            grip.move(to: CGPoint(x: bounds.maxX - 8 - d, y: 8))
            grip.line(to: CGPoint(x: bounds.maxX - 8, y: 8 + d))
        }
        grip.lineWidth = 2.5
        grip.lineCapStyle = .round
        grip.stroke()

        accent.setFill()
        NSBezierPath(roundedRect: doneRect, xRadius: 7, yRadius: 7).fill()
        let done = NSAttributedString(string: ui(.done), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        done.draw(at: CGPoint(x: doneRect.midX - done.size().width / 2, y: doneRect.midY - done.size().height / 2))

        let hint = NSAttributedString(string: ui(.roomHint), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let size = hint.size()
        let pill = CGRect(x: 14, y: bounds.maxY - 34, width: size.width + 16, height: size.height + 6)
        if pill.maxX < doneRect.minX - 6 {
            color(60, 40, 30, 0.75).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            hint.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 3))
        }
    }

    // MARK: Mouse (only while editing; otherwise the window ignores the mouse)

    private var resizing = false
    private var startMouse: CGPoint = .zero
    private var startFrame: CGRect = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let room else { return }
        let p = convert(event.locationInWindow, from: nil)
        if doneRect.contains(p) { return room.setEditing(false) }
        resizing = gripRect.contains(p)
        startMouse = NSEvent.mouseLocation
        startFrame = room.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let room, room.editing else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - startMouse.x, dy = m.y - startMouse.y
        var f = startFrame
        if resizing {
            // The top-left corner stays put.
            f.size.width = max(Room.minSize.width, startFrame.width + dx)
            f.size.height = max(Room.minSize.height, startFrame.height - dy)
            f.origin.y = startFrame.maxY - f.height
        } else {
            f.origin.x += dx
            f.origin.y += dy
        }
        room.setFrame(f.integral)
    }

    override func mouseUp(with event: NSEvent) { room?.saveFrame() }
}
