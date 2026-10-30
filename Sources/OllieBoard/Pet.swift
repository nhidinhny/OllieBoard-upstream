import AppKit

/// One character on screen: a queue of steps (walk, play an animation, run an action)
/// refilled by a weighted choice of behaviors whenever it runs dry.
final class Pet {
    enum Step {
        case walk(CGPoint)
        /// Drops straight down to this height (a pet let go above the room's floor).
        case fall(CGFloat)
        /// Floats straight up to this height (Luffy blown up like a balloon).
        case rise(CGFloat)
        case play(Anim, TimeInterval, effect: Effect? = nil, say: Line? = nil)
        /// Plays an animation once from its start and stays on its last frame (Bocchi's puddle);
        /// if it is already playing, it carries on from where it is instead of restarting.
        case hold(Anim, TimeInterval)
        case face(CGFloat)
        case run(() -> Void)
        case line(Line, to: Character?)
    }

    /// Things other pets do to this one.
    enum Social {
        case invite(Pet), greet(Pet), woken(Pet), hit(Pet), pranked(Pet), chased(Pet), comfort(Pet)
        /// Special moves: Anya reading this pet's mind, Bocchi's guitar solo.
        case mindRead(Pet), listen(Pet)
        /// Special moves: Putin's judo throw, Kim's applause.
        case tossed(Pet), applaud(Pet)
        /// Special move: caught in Gojo's Infinite Void, frozen in place.
        case stunned(Pet)
    }

    /// How high above the feet a carried icon is held.
    private static let carryLift: CGFloat = 132

    let character: Character
    private let sheet: SpriteSheet
    private unowned let world: World
    private let view: PetView
    private lazy var window = PetWindow(view: view)
    private var edgeMirror: PetEdgeMirror?

    private(set) var position: CGPoint
    private(set) var facing: CGFloat = 1

    private var anim: Anim = .idle
    private var animStart: TimeInterval = 0
    private var effect: (effect: Effect, start: TimeInterval, until: TimeInterval)?
    private var bubble: (text: String, until: TimeInterval, thought: Bool)?
    private var holding = false
    /// Nezuko's size change: the drawn scale, the size it is heading to and when that wears off.
    private var scale: CGFloat = 1
    private var targetScale: CGFloat = 1
    private var resizedUntil: TimeInterval = 0

    private var steps: [Step] = []
    private var current: Step?
    private var stepStart: TimeInterval = 0

    private(set) var carrying: String?
    /// Icon picked for a kick that hasn't flown yet, so it can be freed if the kick is called off.
    private var kickTarget: String?
    private var dragging = false
    private var boredom: Double = 0
    private var clicks: [TimeInterval] = []
    /// Busy with a kick, cleanup or visit; other pets won't pull it into a social interaction.
    private var engaged = false

    /// Set for the mascot of a running AI agent session.
    private(set) var agent: AgentSession?
    private var leaving = false
    private var lastAgentCall: TimeInterval = 0
    private var agentReminders = 0
    /// Agent mascots are only on screen while their agent works or waits for the user.
    private var visible = false
    private var handledState: AgentState?
    private var greeted = false

    var isSleeping: Bool { anim == .sleep }
    /// Free to be pulled into games with other characters (agents never are).
    var isAvailable: Bool { agent == nil && !dragging && !engaged && !leaving && carrying == nil && !isSleeping }

    /// Name tag shown under agent mascots, e.g. "Claude · OllieBoard".
    var tag: String? {
        agent.map { $0.project.isEmpty ? $0.kind.title : "\($0.kind.title) · \($0.project)" }
    }

    private var now: TimeInterval { CACurrentMediaTime() }

    init(character: Character, world: World, position: CGPoint, agent: AgentSession? = nil) {
        self.character = character
        self.sheet = agent.map { SpriteSheet.named($0.kind.rawValue, skills: false) } ?? SpriteSheet.named(character.id)
        self.view = PetView()
        self.world = world
        self.position = position
        self.agent = agent
        view.pet = self
        facing = Bool.random() ? 1 : -1
    }

    /// "Hide all" in the menu: the window stays off screen and the pet stands still, keeping its place and state.
    private(set) var suppressed = false

    func setSuppressed(_ on: Bool) {
        guard suppressed != on else { return }
        suppressed = on
        if on {
            window.orderOut(nil)
            edgeMirror?.orderOut(nil)
        } else if agent == nil || visible {
            window.orderFrontRegardless()
        }
    }

    func show() {
        window.place(feetAt: position)
        if !suppressed { window.orderFrontRegardless() }
        steps = [.play(.happy, 1.4, effect: .heart, say: .happy)]
    }

    func hide() {
        if let name = carrying { drop(name, at: carryPoint) }
        if world.arranger === self { world.arranger = nil }
        window.orderOut(nil)
        edgeMirror?.orderOut(nil)
    }

    // MARK: - Rendering state

    func currentFrame() -> CGImage? {
        let elapsed = now - animStart
        return sheet.frame(anim, elapsed: holding ? min(elapsed, sheet.duration(anim) - 0.01) : elapsed)
    }

    func currentEffect() -> (Effect, TimeInterval)? {
        guard let effect, now < effect.until else { return nil }
        return (effect.effect, now - effect.start)
    }

    func currentBubble() -> (text: String, thought: Bool)? {
        guard let bubble, now < bubble.until else { return nil }
        return (bubble.text, bubble.thought)
    }

    private func setAnim(_ a: Anim) {
        if a != anim { anim = a; animStart = now }
    }

    private func say(_ line: Line, to partner: Character? = nil, app: String = "", thought: Bool = false) {
        if let text = character.line(line, to: partner, project: agent?.project ?? "", app: app) {
            bubble = (text, now + 2.8, thought)
        }
    }

    // MARK: - Tick

    /// The mouse pointer is over the character: it stops walking until the pointer moves away, so it can be
    /// right-clicked (or just looked at) without running off.
    private var hovered = false

    func tick(_ dt: TimeInterval) {
        if agent != nil, !visible { return }
        if suppressed { return }
        let m = NSEvent.mouseLocation
        hovered = !dragging && view.bodyRect.contains(CGPoint(x: m.x - window.fullFrame.minX, y: m.y - window.fullFrame.minY))
        if let agent, agent.state == .done || agent.state == .needsInput,
           agentReminders < 2, now - lastAgentCall > 60, isAvailable {
            agentReminders += 1
            callUser()
        }
        if dragging {
            setAnim(.dragged)
        } else {
            advance(dt)
        }
        if [.idle, .walk, .bored].contains(anim) { boredom += dt }
        if targetScale != 1, now > resizedUntil {
            targetScale = 1
            view.puff()
        }
        if scale != targetScale {
            scale += (targetScale - scale) * min(1, CGFloat(dt) * 8)
            if abs(targetScale - scale) < 0.01 { scale = targetScale }
        }
        window.place(feetAt: position)
        let level = inRoom ? world.room.petLevel : .floating
        if window.level != level { window.level = level }
        updateMousePassthrough()
        let fx = currentEffect()
        let bubble = currentBubble()
        view.render(frame: currentFrame(), facing: facing, scale: scale, shift: sheet.shift(anim) * facing, effect: fx.flatMap { SpriteSheet.effect($0.0) },
                    effectAge: fx?.1 ?? 0, bubble: bubble?.text, thought: bubble?.thought ?? false, tag: tag)
        mirrorOverhang()
    }

    /// Draws the part of the pet that lies on a second screen (see PetWindow).
    private func mirrorOverhang() {
        guard !flying, let screen = window.overhangScreen else { edgeMirror?.orderOut(nil); return }
        let mirror = edgeMirror ?? PetEdgeMirror()
        edgeMirror = mirror
        mirror.show(copying: view, windowFrame: window.fullFrame, on: screen, level: window.level)
    }

    private func advance(_ dt: TimeInterval) {
        if current == nil { startNextStep() }
        guard let step = current else { return }
        switch step {
        case .walk(let goal):
            // Carrying an icon keeps walking (its arms-up pose would not match the icon floating above them).
            if hovered && carrying == nil { setAnim(.idle); break }
            let target = confined(goal)
            let dx = target.x - position.x, dy = target.y - position.y
            let dist = hypot(dx, dy)
            let fast = carrying == nil && dist > 450
            let speed = character.walkSpeed * (carrying != nil ? 0.75 : fast ? 2.2 : 1)
            setAnim(carrying != nil ? .carry : fast ? .run : .walk)
            if abs(dx) > 1 { facing = dx > 0 ? 1 : -1 }
            let len = CGFloat(speed * dt)
            if dist <= len {
                position = target
                current = nil
            } else {
                position.x += dx / dist * len
                position.y += dy / dist * len
            }
            if let name = carrying { world.desktop.moveLive(name, to: carryPoint) }
        case .fall(let y):
            if flying { showInflated() } else { setAnim(.dragged) }   // Luffy keeps his balloon belly on the way down
            position.y = max(y, position.y - CGFloat(700 * dt))
            if position.y <= y { current = nil }
        case .rise(let y):
            if flying { showInflated() } else { setAnim(.happy) }
            position.y = min(y, position.y + CGFloat(380 * dt))
            if position.y >= y { current = nil }
        case .play(_, let duration, _, _), .hold(_, let duration):
            if now - stepStart >= duration { current = nil }
        case .face, .run, .line:
            current = nil
        }
    }

    private func startNextStep() {
        if steps.isEmpty {
            if let agent {
                // Mascots type on their laptop while the agent is busy, and wait near you once it's done.
                steps = agent.state == .working ? [.play(.work, 5, effect: .code)] : [.play(.idle, 4)]
            } else {
                steps = plan(for: chooseBehavior())
            }
        }
        guard !steps.isEmpty else { return }
        let step = steps.removeFirst()
        current = step
        stepStart = now
        holding = false
        switch step {
        case .play(let a, let duration, let fx, let line):
            setAnim(a)
            if let fx { effect = (fx, now, now + duration) }
            if let line { say(line) }
        case .face(let f):
            facing = f
        case .run(let action):
            action()
        case .line(let line, let partner):
            say(line, to: partner)
        case .hold(let a, _):
            setAnim(a)
            holding = true
        case .walk, .fall, .rise:
            break
        }
    }

    /// Plays `newSteps` right away, then resumes what the pet was doing (an interrupted walk or fall is redone).
    private func interrupt(_ newSteps: [Step]) {
        if let current {
            switch current {
            case .walk, .fall, .rise: steps.insert(current, at: 0)
            default: break
            }
        }
        steps.insert(contentsOf: newSteps, at: 0)
        current = nil
    }

    // MARK: - Behaviors

    private func chooseBehavior() -> Behavior {
        let hasIcons = world.availableIcons().count > 0
        var weights = character.weights
        weights[.bored, default: 0] *= 1 + boredom / 40
        weights[.sleep, default: 0] *= 1 + boredom / 60
        weights[.kick, default: 0] *= inRoom ? 0 : hasIcons ? 1 : 0.1
        weights[.arrange, default: 0] *= (!inRoom && hasIcons && world.arranger == nil) ? 1 : 0
        weights[.social, default: 0] *= world.pets.values.contains { $0 !== self && $0.agent == nil && $0.inRoom == inRoom } ? 1 : 0
        let total = weights.values.reduce(0, +)
        var roll = Double.random(in: 0..<max(total, 0.001))
        for behavior in Behavior.allCases {
            roll -= weights[behavior, default: 0]
            if roll < 0 { return behavior }
        }
        return .wander
    }

    private func plan(for behavior: Behavior) -> [Step] {
        if character.shy, let flee = fleeFromCursor() { return flee }
        switch behavior {
        case .wander:
            return [.walk(randomDestination()), .play(.idle, .random(in: 1...3))]
        case .kick:
            return kickPlan()
        case .arrange:
            return arrangePlan()
        case .bored:
            // Join a friend who is already bored instead of sulking alone.
            if let buddy = world.pets.values.first(where: { $0 !== self && $0.anim == .bored && $0.inRoom == inRoom }) {
                return [.walk(beside(buddy)),
                        .face(buddy.position.x > position.x ? 1 : -1),
                        .line(.together, to: buddy.character),
                        .play(.bored, .random(in: 5...9), effect: .dots)]
            }
            return [.play(.bored, .random(in: 4...8), effect: .dots, say: .bored)]
        case .sleep:
            return [.play(.yawn, sheet.duration(.yawn) + 0.3, say: .tedious),
                    .play(.sleep, .random(in: 8...16), effect: .zzz),
                    .run { [weak self] in self?.boredom = 0 }]
        case .grumpy:
            return [.play(character.grumpyAnim, 2.5, effect: .anger, say: .grumpy), askForComfort()]
        case .happy:
            return [.play(.happy, 1.8, effect: .note, say: .happy),
                    .run { [weak self] in self?.boredom = max(0, (self?.boredom ?? 0) - 20) }]
        case .social:
            return socialPlan()
        case .skill:
            guard let skill = availableSkills.randomElement() else { return plan(for: .wander) }
            return skillPlan(skill)
        }
    }

    // MARK: - Skills drawn with their prop

    /// Luffy is floating up or down as a balloon: only the screen-edge mirror cares (it would copy the sprite every frame).
    private var flying = false

    /// Luffy's last, fully puffed-up `inflate` frame (also after something interrupted him in the air).
    private func showInflated() {
        guard sheet.has(.inflate) else { return setAnim(.happy) }
        if anim != .inflate {
            anim = .inflate
            animStart = now - sheet.duration(.inflate)
        }
    }

    /// The skills this character's sheets actually draw (one without its rows in the skills sheet is not offered).
    var availableSkills: [Skill] { character.skills.filter { sheet.hasSkill($0) } }

    /// A skill whose prop is drawn in the character's own skills sheet (`<id>-skills.png`, see skills.json).
    private func drawnSkillPlan(_ skill: Skill) -> [Step] {
        let f = facing
        switch skill {
        case .yoyo:
            return engage([.face(f), .line(.yoyo, to: nil), .play(.yoyo, 5.5),
                           .play(.happy, 1.2, effect: .sparkle, say: .yoyoDone)])
        case .balloon:
            return balloonPlan()
        case .eat:
            return engage([.face(f), .play(.eat, 6, say: .eat), .play(.happy, 1.2, effect: .heart)])
        case .lift:
            return engage([.face(f), .line(.lift, to: nil), .play(.lift, 6),
                           .play(.happy, 1.2, effect: .sparkle, say: .liftDone)])
        case .sake:
            return engage([.face(f), .play(.sake, 1.4, say: .sake), .play(.sake, 5.4),
                           .play(.happy, 1.4, effect: .note)])
        case .grill:
            // The campfire and the skewers are drawn in her own skills row.
            return engage([.face(f), .line(.grill, to: nil), .play(.grill, 6),
                           .play(.happy, 1.6, effect: .heart, say: .grillDone)])
        default:
            return plan(for: .wander)
        }
    }

    /// Luffy puffs his belly out like a balloon, floats up to twice his own height above the ground and comes back down.
    private func balloonPlan() -> [Step] {
        let frame = screenFrame(containing: position)
        let ground = position.y
        let ceiling = min(ground + 2 * SpriteSheet.layout.frameSize, frame.maxY - 20)
        // His belly swells in his own `inflate` row (it plays once and stays on its last, floating frame).
        return engage([.play(.inflate, 1.4, effect: .sparkle, say: .inflate),
                       .run { [weak self] in self?.flying = true },
                       .rise(ceiling),
                       .play(.inflate, 1.6),
                       .fall(ground),
                       .run { [weak self] in self?.view.puff(); self?.flying = false },
                       .play(.happy, 1.6, effect: .heart, say: .inflateDone)])
    }

    /// Wraps a multi-step task so other pets leave this one alone until it finishes.
    private func engage(_ plan: [Step]) -> [Step] {
        [.run { [weak self] in self?.engaged = true }] + plan + [.run { [weak self] in self?.engaged = false }]
    }

    private func fleeFromCursor() -> [Step]? {
        let m = NSEvent.mouseLocation
        let dx = position.x - m.x, dy = position.y - m.y
        let d = hypot(dx, dy)
        guard d < 170, d > 0 else { return nil }
        let target = clampToScreens(CGPoint(x: position.x + dx / d * 260, y: position.y + dy / d * 260))
        return [.play(.surprised, 0.4, effect: .exclaim),
                .walk(target),
                .play(character.grumpyAnim, 1.5, effect: .sweat, say: .grumpy),
                askForComfort()]
    }

    // MARK: Kicking icons

    private func kickPlan() -> [Step] {
        guard let icon = world.pickIcon(near: position) else {
            return [.play(character.grumpyAnim, 2, effect: .dots, say: .noIcons)]
        }
        world.claim(icon.name)
        kickTarget = icon.name
        let side: CGFloat = icon.center.x >= position.x ? 1 : -1
        let stand = clampToScreens(CGPoint(x: icon.center.x - side * 46, y: icon.center.y - 44))
        return engage([.walk(stand),
                       .face(side),
                       .play(.kick, 0.33, say: .kick),
                       .run { [weak self] in self?.launch(icon.name, side: side) },
                       .play(.kick, 0.3),
                       .play(.happy, 1.2, effect: .sparkle)])
    }

    private func launch(_ name: String, side: CGFloat) {
        kickTarget = nil
        guard let icon = world.desktop.icons.first(where: { $0.name == name }) else {
            world.release(name)
            return
        }
        let path = flightPath(of: icon.center, direction: CGVector(dx: side, dy: 0), distance: .random(in: 160...320))
        // Friends standing in the flight path get hit.
        for other in world.pets.values where other !== self && !other.inRoom {
            let body = CGPoint(x: other.position.x, y: other.position.y + 55)
            if let i = path.firstIndex(where: { hypot($0.x - body.x, $0.y - body.y) < 55 }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.03) { [weak self, weak other] in
                    if let self, let other { other.receive(.hit(self)) }
                }
            }
        }
        // Kicking an icon someone just tidied up starts a chase.
        if let owner = world.arrangedBy, owner !== self, !owner.inRoom, world.arranged.remove(name) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak owner] in
                if let self, let owner { owner.receive(.pranked(self)) }
            }
        }
        world.desktop.move(name, along: path) { [weak self] final in
            guard let self else { return }
            self.world.release(name)
            if final == nil || hypot(final!.x - icon.center.x, final!.y - icon.center.y) < 10 {
                self.interrupt([.play(self.character.grumpyAnim, 2, effect: .sweat, say: .fail)])
            }
        }
    }

    /// A kicked icon's arc: `distance` along `direction` with a hop, kept on the icon's screen.
    private func flightPath(of start: CGPoint, direction: CGVector, distance: CGFloat) -> [CGPoint] {
        let bounds = screenFrame(containing: start).insetBy(dx: 40, dy: 40)
        let n = 12
        return (1...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            let ease = 1 - (1 - t) * (1 - t)
            let p = CGPoint(x: start.x + direction.dx * distance * ease, y: start.y + direction.dy * distance * ease + sin(t * .pi) * 50)
            return CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
        }
    }

    // MARK: Arranging icons

    private var carryPoint: CGPoint { CGPoint(x: position.x, y: position.y + Self.carryLift) }

    private func feetUnder(_ p: CGPoint) -> CGPoint {
        let bottom = screenFrame(containing: p).minY
        return CGPoint(x: p.x, y: max(bottom, p.y - Self.carryLift))
    }

    private func arrangePlan() -> [Step] {
        guard world.arranger == nil else { return plan(for: .wander) }
        let icons = world.availableIcons().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !icons.isEmpty else { return [.play(character.grumpyAnim, 2, effect: .dots, say: .noIcons)] }
        let slots = world.gridSlots(count: icons.count)

        var work: [Step] = []
        for (icon, slot) in zip(icons, slots).filter({ hypot($0.center.x - $1.x, $0.center.y - $1.y) > 12 }).prefix(10) {
            work += [.walk(feetUnder(icon.center)),
                     .run { [weak self] in self?.pickUp(icon.name) },
                     .walk(feetUnder(slot)),
                     .run { [weak self] in self?.drop(icon.name, at: slot) },
                     .play(.idle, 0.25)]
        }
        guard !work.isEmpty else { return [.play(.happy, 1.5, effect: .sparkle, say: .done)] }
        world.arranger = self
        return engage([.play(.idle, 0.8, effect: .exclaim, say: .arrange)] + work +
            [.run { [weak self] in
                guard let self else { return }
                if self.world.arranger === self { self.world.arranger = nil }
                self.world.arranged = Set(icons.map(\.name))
                self.world.arrangedBy = self
             },
             .play(.happy, 2, effect: .sparkle, say: .done)])
    }

    private func pickUp(_ name: String) {
        world.claim(name)
        carrying = name
    }

    private func drop(_ name: String, at point: CGPoint) {
        carrying = nil
        world.desktop.cancelLive(name)
        world.desktop.move(name, along: [point]) { [weak self] _ in self?.world.release(name) }
    }

    // MARK: - Agent

    func update(agent session: AgentSession) {
        agent = session
        guard !leaving, session.state != handledState else { return }
        handledState = session.state
        guard session.state != .idle else { return disappear() }
        let justAppeared = !visible
        if justAppeared { appear() }
        switch session.state {
        case .working:
            // Start working as soon as the current errand allows.
            if !engaged, !dragging {
                steps.removeAll()
                current = nil
            }
            say(greeted ? .agentWorking : .agentHello)
            greeted = true
        case .done, .needsInput:
            if justAppeared {
                // Skip the stroll to a spot and head straight for the user.
                steps.removeAll()
                engaged = false
            }
            agentReminders = 0
            callUser()
        case .idle:
            break
        }
    }

    /// Walks in from the nearest edge of the main screen to a spot along the bottom.
    private func appear() {
        let f = NSScreen.main?.visibleFrame ?? NSScreen.screens[0].visibleFrame
        let spot = CGPoint(x: .random(in: (f.minX + 80)...(f.maxX - 80)), y: f.minY + .random(in: 10...80))
        position = CGPoint(x: spot.x < f.midX ? f.minX - 80 : f.maxX + 80, y: spot.y)
        visible = true
        // Engaged right away so the state handling that follows doesn't cut the entrance short.
        engaged = true
        steps = [.walk(spot), .run { [weak self] in self?.engaged = false }]
        current = nil
        window.place(feetAt: position)
        if !suppressed { window.orderFrontRegardless() }
    }

    private func disappear() {
        visible = false
        steps.removeAll()
        current = nil
        engaged = false
        bubble = nil
        effect = nil
        window.orderOut(nil)
        edgeMirror?.orderOut(nil)
    }

    /// Runs over to the mouse cursor to say the agent finished or needs the user.
    private func callUser() {
        guard let agent else { return }
        lastAgentCall = now
        let line: Line = agent.state == .needsInput ? .agentNeedsYou : .agentDone
        let m = NSEvent.mouseLocation
        let side: CGFloat = position.x < m.x ? -1 : 1
        interrupt(engage([.play(.surprised, 0.4, effect: .exclaim),
                          .walk(clampToScreens(CGPoint(x: m.x + side * 70, y: m.y - 110))),
                          .face(-side),
                          .line(line, to: nil),
                          .play(.happy, 2.2, effect: line == .agentDone ? .check : .exclaim)]))
    }

    /// The agent session ended: wave goodbye and walk off the nearest screen edge.
    func leave(_ completion: @escaping () -> Void) {
        guard !leaving else { return }
        leaving = true
        guard visible || agent == nil else { return completion() }
        if let name = carrying { drop(name, at: carryPoint) }
        if world.arranger === self { world.arranger = nil }
        let f = screenFrame(containing: position)
        let exitX = position.x - f.minX < f.maxX - position.x ? f.minX - 80 : f.maxX + 80
        steps = [.line(.agentBye, to: nil),
                 .play(.happy, 1.2, effect: .heart),
                 .walk(CGPoint(x: exitX, y: position.y)),
                 .run(completion)]
        current = nil
    }

    // MARK: - Friends

    private func direction(to other: Pet) -> CGFloat { other.position.x >= position.x ? 1 : -1 }

    /// A spot right next to `other`, on the side this pet is coming from.
    private func beside(_ other: Pet) -> CGPoint {
        clampToScreens(CGPoint(x: other.position.x + (position.x < other.position.x ? -60 : 60), y: other.position.y))
    }

    private func socialPlan() -> [Step] {
        let others = world.pets.values.filter { $0 !== self && $0.inRoom == inRoom }
        // Pranksters (and sometimes the others) wake up sleeping friends.
        if let sleeper = others.filter(\.isSleeping).randomElement(), character.prankster || Double.random(in: 0..<1) < 0.3 {
            return engage([.walk(beside(sleeper)),
                           .face(direction(to: sleeper)),
                           .line(.wakeOther, to: sleeper.character),
                           .play(.happy, 0.6, effect: .exclaim),
                           .run { [weak self, weak sleeper] in if let self, let sleeper { sleeper.receive(.woken(self)) } },
                           .play(.happy, 1.4, effect: .note)])
        }
        // Only friends close enough to reach before they get tired of waiting.
        let nearest = others.filter { $0.isAvailable && hypot($0.position.x - position.x, $0.position.y - position.y) < 900 }.min {
            hypot($0.position.x - position.x, $0.position.y - position.y) < hypot($1.position.x - position.x, $1.position.y - position.y)
        }
        guard let friend = nearest else { return plan(for: .wander) }
        friend.receive(.invite(self))
        return engage([.walk(beside(friend)),
                       .face(direction(to: friend)),
                       .line(.greet, to: friend.character),
                       .play(.happy, 1.4, effect: .heart),
                       .run { [weak self, weak friend] in if let self, let friend { friend.receive(.greet(self)) } },
                       .play(.idle, 1.2)])
    }

    /// Shy characters hope someone notices they are upset.
    private func askForComfort() -> Step {
        .run { [weak self] in
            if let self, self.character.shy { self.world.requestComfort(for: self) }
        }
    }

    func comfort(_ friend: Pet) {
        friend.receive(.invite(self))
        interrupt(engage([.walk(beside(friend)),
                          .face(direction(to: friend)),
                          .line(.comfort, to: friend.character),
                          .play(.idle, 1.0, effect: .heart),
                          .run { [weak self, weak friend] in if let self, let friend { friend.receive(.comfort(self)) } },
                          .play(.happy, 1.2)]))
    }

    func receive(_ event: Social) {
        guard agent == nil, !dragging, !leaving else { return }
        switch event {
        case .invite(let other):
            guard isAvailable else { return }
            // Wait for the visitor to arrive.
            interrupt(engage([.face(direction(to: other)), .play(.idle, 6)]))
        case .greet(let other):
            let flustered: [Step] = character.shy ? [.play(.surprised, 0.5, effect: .exclaim)] : []
            interrupt(flustered + [.face(direction(to: other)),
                                   .line(.greetBack, to: other.character),
                                   .play(.happy, 1.6, effect: .heart)])
            boredom = 0
        case .woken(let other):
            interrupt([.play(.surprised, 0.7, effect: .exclaim),
                       .face(direction(to: other)),
                       .play(character.grumpyAnim, 1.8, effect: .anger, say: .wake),
                       askForComfort()])
        case .hit(let kicker):
            interrupt([.play(.surprised, 0.5, effect: .exclaim),
                       .face(direction(to: kicker)),
                       .line(.hit, to: kicker.character),
                       .play(character.grumpyAnim, 1.8, effect: .anger),
                       .run { [weak self, weak kicker] in
                           guard let self, let kicker else { return }
                           kicker.interrupt([.face(kicker.direction(to: self)),
                                             .line(.sorry, to: self.character),
                                             .play(kicker.character.prankster ? .happy : .sad, 1.5, effect: .sweat)])
                       },
                       askForComfort()])
        case .pranked(let kicker):
            interrupt(engage([.play(.surprised, 0.5, effect: .exclaim),
                              .face(direction(to: kicker)),
                              .line(.pranked, to: kicker.character),
                              .play(character.grumpyAnim, 1.4, effect: .anger),
                              .run { [weak self, weak kicker] in
                                  guard let self, let kicker else { return }
                                  kicker.receive(.chased(self))
                              },
                              .play(.idle, 0.6),
                              // Chase toward wherever the culprit has run off to by now.
                              .run { [weak self, weak kicker] in
                                  guard let self, let kicker else { return }
                                  self.steps.insert(.walk(self.beside(kicker)), at: 0)
                              },
                              .play(character.grumpyAnim, 1.5, effect: .anger, say: .grumpy)]))
        case .chased(let chaser):
            let away = -direction(to: chaser)
            interrupt([.face(away),
                       .line(.chased, to: chaser.character),
                       .walk(clampToScreens(CGPoint(x: position.x + away * 300, y: position.y))),
                       .play(.happy, 1, effect: .note)])
        case .comfort(let friend):
            boredom = 0
            interrupt([.face(direction(to: friend)),
                       .line(.thanks, to: friend.character),
                       .play(.happy, 1.8, effect: .heart)])
        case .mindRead(let reader):
            // The secret thought pops up for everyone to see.
            interrupt([.face(direction(to: reader)),
                       .run { [weak self] in self?.say(.thought, thought: true) },
                       .play(.idle, 2.4),
                       .play(.surprised, 0.6, effect: .exclaim),
                       .play(character.grumpyAnim, 1.2, effect: .sweat)])
        case .listen(let musician):
            guard isAvailable else { return }
            let side: CGFloat = position.x < musician.position.x ? -1 : 1
            let seat = clampToScreens(CGPoint(x: musician.position.x + side * 100, y: musician.position.y + .random(in: -14...14)))
            interrupt(engage([.walk(seat),
                              .face(-side),
                              .play(.happy, 3.5, effect: .note),
                              .line(.cheer, to: musician.character),
                              .play(.happy, 1.4, effect: .heart)]))
        case .tossed(let thrower):
            // Putin's judo: tumble in place, then get up cross.
            interrupt([.play(.surprised, 0.5, effect: .exclaim),
                       .face(direction(to: thrower)),
                       .line(.hit, to: thrower.character),
                       .run { [weak self] in self?.view.impact(dx: 0); self?.view.shake() },
                       .play(.dragged, 0.6),
                       .play(character.grumpyAnim, 1.6, effect: .anger),
                       askForComfort()])
        case .applaud(let leader):
            interrupt([.face(direction(to: leader)),
                       .line(.cheer, to: leader.character),
                       .play(.happy, 1.8, effect: .note)])
        case .stunned(let caster):
            interrupt([.face(direction(to: caster)),
                       .play(.surprised, 3.6, effect: .dots),
                       .play(.sad, 1, effect: .sweat)])
        }
    }

    // MARK: - Skills

    /// A special move picked from the right-click menu.
    func useSkill(_ skill: Skill) {
        guard agent == nil, !dragging, !leaving, availableSkills.contains(skill) else { return }
        interrupt(skillPlan(skill))
    }

    private func skillPlan(_ skill: Skill) -> [Step] {
        switch skill {
        case .yoyo, .balloon, .eat, .lift, .sake, .grill:
            return drawnSkillPlan(skill)
        case .mindRead:
            // Whatever app you are in is what's on your mind.
            let app = NSWorkspace.shared.frontmostApplication.flatMap { $0 == NSRunningApplication.current ? nil : $0.localizedName }
            return engage([.run { [weak self] in self?.view.telepathy() },
                           .play(.skill1, 2),
                           .run { [weak self] in self?.say(app == nil ? .mindReadIdle : .mindRead, app: app ?? "") },
                           .play(.skill2, 2.4)])
        case .readFriend:
            guard let friend = nearbyFriends(within: 900).randomElement() else { return skillPlan(.mindRead) }
            friend.receive(.invite(self))
            return engage([.walk(beside(friend)),
                           .face(direction(to: friend)),
                           .run { [weak self] in self?.view.telepathy() },
                           .play(.skill1, 1.5),
                           .run { [weak self, weak friend] in if let self, let friend { friend.receive(.mindRead(self)) } },
                           .play(.skill1, 1.6),
                           .line(.readFriend, to: friend.character),
                           .play(.skill2, 2.2)])
        case .bloodBurst:
            return engage([.play(.skill2, 1, say: .bloodBurst),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.flameBurst()
                               self.blast(from: CGPoint(x: self.position.x, y: self.position.y + 50), radius: 210) { _ in true }
                           },
                           .play(.skill1, 1.5),
                           .play(.happy, 1, effect: .sparkle)])
        case .resize:
            let small = Bool.random()
            return [.run { [weak self] in
                        guard let self else { return }
                        self.view.puff()
                        self.targetScale = small ? 0.55 : 1.25
                        self.resizedUntil = self.now + .random(in: 12...20)
                    },
                    .play(.surprised, 0.5),
                    .line(small ? .shrink : .grow, to: nil),
                    .play(.happy, 1.4, effect: .note)]
        case .flowerField:
            return engage([.play(.skill1, 1, say: .flowers),
                           .run { [weak self] in self?.view.flowerField(for: 7.5) },
                           .play(.skill1, 2),
                           .play(.idle, 4.5)])
        case .mimic:
            // The chest turns up beside her, on whichever side has room; she ends up inside it.
            func chestSpot(_ side: CGFloat) -> CGPoint { confined(clampToScreens(CGPoint(x: position.x + side * 48, y: position.y))) }
            let side = abs(chestSpot(facing).x - position.x) < 40 ? -facing : facing
            let spot = chestSpot(side)
            return engage([.face(side),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.showProp(SpriteSheet.effect(.chest), dx: spot.x - self.position.x)
                           },
                           .play(.surprised, 0.6, effect: .sparkle, say: .mimicSpot),
                           .play(.idle, 2.2),
                           .run { [weak self] in
                               self?.view.showProp(nil, dx: 0)
                               self?.position = spot
                           },
                           .play(.skill2, 3.5, say: .mimicEaten),
                           .run { [weak self] in self?.view.puff() },
                           .play(.sad, 1.8, effect: .sweat, say: .mimicOut)])
        case .guitarSolo:
            for friend in nearbyFriends(within: 600) { friend.receive(.listen(self)) }
            return engage([.play(.surprised, 0.5, effect: .sweat, say: .guitar),
                           .run { [weak self] in self?.view.notes(for: 6, facing: self?.facing ?? 1) },
                           .play(.skill1, 6.5),
                           .line(.guitarDone, to: nil),
                           .play(.happy, 1.8, effect: .heart)])
        case .melt:
            return engage([.play(.surprised, 0.5, effect: .sweat, say: .melt),
                           .hold(.skill2, 3.5),
                           .run { [weak self] in self?.view.puff() },
                           .play(.surprised, 0.4),
                           .play(.sad, 1.6, say: .reform)])
        case .morningStar:
            // The ball hits the ground on frame 5 of the 8-frame swing.
            return engage([.line(.morningStar, to: nil),
                           .hold(.skill1, 0.625),
                           .run { [weak self] in
                               guard let self else { return }
                               let side = self.facing
                               self.view.impact(dx: 44 * side)
                               let origin = CGPoint(x: self.position.x, y: self.position.y + 30)
                               self.blast(from: origin, radius: 230) { ($0.x - origin.x) * side > 0 && abs($0.y - origin.y) < 140 }
                           },
                           .play(.skill1, 0.375),
                           .play(.happy, 1, effect: .sparkle)])
        case .poisonTest:
            // Shakes the vial and watches the purple bubbles; only a visual, nothing on the Desktop changes.
            return [.play(.skill1, 0.4, say: .poisonTest),
                    .run { [weak self] in self?.view.aura(for: 2.4, color: Pet.purple) },
                    .play(.skill1, 2.2),
                    .play(.idle, 0.8, effect: .dots)]
        case .herbalBrew:
            // Grinds herbs in the mortar, then a soft recovery glow. Also only a visual.
            return [.play(.skill2, 0.4, say: .herbalBrew),
                    .run { [weak self] in self?.view.sparks(color: CGColor(srgbRed: 0.5, green: 0.9, blue: 0.55, alpha: 1), for: 2.4) },
                    .play(.skill2, 2.2),
                    .play(.happy, 1.2, effect: .sparkle)]
        case .oniForm:
            return engage([.play(.surprised, 0.4, effect: .exclaim),
                           .run { [weak self] in self?.view.aura(for: 4) },
                           .play(.skill2, 4, say: .oni),
                           .line(.oniCalm, to: nil),
                           .play(.happy, 1.4)])
        case .wall:
            // The wall rises in front of him and shoves the icons beyond it away.
            return engage([.run { [weak self] in
                               guard let self else { return }
                               self.view.wall(for: 3.6, facing: self.facing)
                               let origin = CGPoint(x: self.position.x + self.facing * 70, y: self.position.y + 40)
                               self.blast(from: origin, radius: 260) { ($0.x - origin.x) * self.facing > -20 }
                           },
                           .play(.skill1, 1, say: .wall),
                           .hold(.skill1, 1.2),
                           .play(.happy, 1.4, effect: .sparkle, say: .wallBuilt)])
        case .tariff:
            // Holds up the tariff board; coins pour off it at a friend, or at the icons ahead.
            let friend = nearbyFriends(within: 700).randomElement()
            friend?.receive(.invite(self))
            let approach: [Step] = friend.map { [.walk(beside($0)), .face(direction(to: $0))] } ?? []
            return engage(approach + [.line(.tariff, to: friend?.character),
                                      .play(.skill2, 1),
                                      .run { [weak self, weak friend] in
                                          guard let self else { return }
                                          self.view.coins(facing: self.facing)
                                          if let friend {
                                              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                                                  if let self { friend.receive(.hit(self)) }
                                              }
                                          } else {
                                              let origin = CGPoint(x: self.position.x + self.facing * 50, y: self.position.y + 60)
                                              self.blast(from: origin, radius: 260) { ($0.x - origin.x) * self.facing > 0 }
                                          }
                                      },
                                      .hold(.skill2, 1.3),
                                      .play(.happy, 1.4, effect: .note)])
        case .judo:
            guard let friend = nearbyFriends(within: 500).randomElement() else {
                return engage([.play(.skill1, 2, say: .judo), .play(.happy, 1, effect: .sparkle)])
            }
            friend.receive(.invite(self))
            return engage([.walk(beside(friend)),
                           .face(direction(to: friend)),
                           .play(.skill1, 1.8, say: .judo),
                           .run { [weak self, weak friend] in
                               guard let self, let friend else { return }
                               friend.receive(.tossed(self))
                           },
                           .play(.happy, 1.2)])
        case .bearRide:
            return engage([.run { [weak self] in
                               guard let self else { return }
                               self.view.dust(for: 3, facing: self.facing)
                               self.view.shake()
                           },
                           .play(.skill2, 1, say: .bear),
                           .run { [weak self] in
                               guard let self else { return }
                               let origin = CGPoint(x: self.position.x, y: self.position.y + 30)
                               self.blast(from: origin, radius: 190) { _ in true }
                           },
                           .play(.skill2, 2),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .parade:
            // A convoy rolls past while he waves, and the nearby icons fall in line.
            return engage([.run { [weak self] in
                               guard let self else { return }
                               self.view.convoy(for: 4.2, facing: self.facing)
                           },
                           .play(.skill1, 1, say: .parade),
                           .run { [weak self] in
                               guard let self else { return }
                               // Up to five nearby icons line up in a neat row in front of him.
                               let icons = self.world.availableIcons()
                                   .filter { hypot($0.center.x - self.position.x, $0.center.y - self.position.y) < 320 }
                                   .prefix(5)
                               guard !icons.isEmpty else { return }
                               let frame = self.screenFrame(containing: self.position)
                               let y = min(max(self.position.y + 60, frame.minY + 60), frame.maxY - 60)
                               var paths: [String: [CGPoint]] = [:]
                               for (i, icon) in icons.enumerated() {
                                   let x = self.position.x + self.facing * CGFloat(i + 1) * 64
                                   paths[icon.name] = [CGPoint(x: min(max(x, frame.minX + 40), frame.maxX - 40), y: y)]
                               }
                               self.world.desktop.moveAll(paths)
                           },
                           .play(.skill1, 2.6, say: .paradeOrder),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .aiRobot:
            // The robot is printed and its eyes light up, then it sweeps the icons ahead with a laser.
            return engage([.play(.skill2, 1, say: .aiRobot),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.laser(for: 1.6, facing: self.facing)
                               let eye = CGPoint(x: self.position.x + self.facing * 43, y: self.position.y + 62)
                               self.blast(from: eye, radius: 420) { ($0.x - eye.x) * self.facing > 0 && abs($0.y - eye.y) < 90 }
                           },
                           .hold(.skill2, 1.6),
                           .line(.aiRobotDone, to: nil),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .applause:
            for friend in nearbyFriends(within: 700) { friend.receive(.applaud(self)) }
            return engage([.run { [weak self] in self?.view.confetti(for: 2.4) },
                           .play(.skill1, 2.4, say: .applause),
                           .play(.happy, 1.4, effect: .note)])
        case .missile:
            // Launch (one cycle of skill2), then the missile comes down as fireworks.
            return engage([.play(.skill2, 1, say: .missile),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.fireworks(facing: self.facing)
                               let origin = CGPoint(x: self.position.x + self.facing * 44, y: self.position.y + 128)
                               self.blast(from: origin, radius: 260) { _ in true }
                           },
                           .line(.boom, to: nil),
                           .hold(.skill2, 1.8),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .waterBreathing:
            return engage([.play(.skill1, 0.5, say: .waterBreathing),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.slash(color: Pet.water, facing: self.facing, count: 2)
                               self.blastAhead(radius: 240)
                           },
                           .play(.skill1, 1.5),
                           .play(.happy, 1, effect: .sparkle)])
        case .hinokami:
            return engage([.play(.skill2, 0.5, say: .hinokami),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.slash(color: Pet.fire, facing: self.facing, count: 3, full: true)
                               self.view.sparks(color: Pet.fire, for: 2)
                               self.blastAround(radius: 220)
                           },
                           .play(.skill2, 2),
                           .play(.happy, 1, effect: .sparkle)])
        case .thunderclap:
            // Dozes off, then strikes in his sleep and wakes up wondering what happened.
            return engage([.play(.sleep, 1.4, effect: .zzz),
                           .line(.thunderclap, to: nil),
                           .run { [weak self] in self?.view.sparks(color: Pet.thunder, for: 0.8) },
                           .play(.skill1, 0.8),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.lightning(dx: 0, color: Pet.thunder)
                               self.dash(260, color: Pet.thunder)
                           },
                           .play(.skill1, 1.2),
                           .play(.surprised, 0.8, effect: .exclaim)])
        case .clingCry:
            // Clings to a friend in tears until they come and comfort him.
            let friend = nearbyFriends(within: 700).randomElement()
            friend?.receive(.invite(self))
            let approach: [Step] = friend.map { [.walk(beside($0)), .face(direction(to: $0))] } ?? []
            return engage(approach + [.line(.clingCry, to: nil),
                                      .play(.skill2, 3, effect: .sweat),
                                      .run { [weak self, weak friend] in if let self, let friend { friend.comfort(self) } }])
        case .gomuPistol:
            // The fist lands on frame 4 of the 8-frame stretch.
            return engage([.play(.skill1, 0.5, say: .gomuPistol),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.impact(dx: self.facing * 112)
                               self.blastAhead(radius: 150, reach: 100)
                           },
                           .play(.skill1, 0.5),
                           .play(.happy, 1.2, effect: .note)])
        case .gear5:
            for friend in nearbyFriends(within: 600) { friend.receive(.applaud(self)) }
            return engage([.run { [weak self] in
                               self?.view.aura(for: 3.5, color: CGColor(gray: 1, alpha: 1))
                               self?.view.sparks(color: CGColor(gray: 1, alpha: 1), for: 3)
                           },
                           .play(.skill2, 3.5, say: .gear5),
                           .play(.happy, 1.2, effect: .note)])
        case .threeSword:
            return engage([.play(.skill1, 0.5, say: .threeSword),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.slash(color: Pet.steel, facing: self.facing, count: 3)
                               self.blastAhead(radius: 250)
                           },
                           .play(.skill1, 1.5),
                           .play(.idle, 0.6)])
        case .getLost:
            // Sets off confidently somewhere else entirely.
            return engage([.line(.getLost, to: nil),
                           .play(.skill2, 2),
                           .walk(randomDestination()),
                           .play(.skill2, 1.5, effect: .dots),
                           .line(.lostAgain, to: nil),
                           .play(.grumpy, 1.2, effect: .sweat)])
        case .climaTact:
            return engage([.play(.skill1, 1, say: .climaTact),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.lightning(dx: self.facing * 80)
                               self.blast(from: CGPoint(x: self.position.x + self.facing * 80, y: self.position.y + 30), radius: 170) { _ in true }
                           },
                           .play(.skill1, 1),
                           .play(.happy, 1, effect: .sparkle)])
        case .berries:
            return engage([.play(.skill2, 0.5, say: .berries),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.coins(facing: self.facing)
                           },
                           .play(.skill2, 2.5),
                           .play(.happy, 1.2, effect: .heart)])
        case .titanShift:
            // A bolt from the sky, and he comes out of the smoke a lot bigger.
            return engage([.play(.surprised, 0.4, effect: .exclaim),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.lightning(dx: 0)
                               self.view.puff()
                               self.view.shake()
                               self.targetScale = 1.35
                               self.resizedUntil = self.now + 5
                               self.blastAround(radius: 250)
                           },
                           .play(.skill1, 4.4, say: .titanShift),
                           .play(.idle, 0.8)])
        case .tatakae:
            for friend in nearbyFriends(within: 600) { friend.receive(.applaud(self)) }
            return engage([.run { [weak self] in self?.view.aura(for: 2.5, color: Pet.scarlet) },
                           .play(.skill2, 2.5, say: .tatakae),
                           .play(.happy, 1, effect: .exclaim)])
        case .odmGear:
            return engage([.play(.skill1, 0.4, say: .odmGear),
                           .run { [weak self] in
                               guard let self else { return }
                               self.dash(260, color: Pet.steel)
                               self.view.slash(color: Pet.steel, facing: self.facing)
                           },
                           .play(.skill1, 1.2),
                           .play(.idle, 0.6)])
        case .scarf:
            return [.play(.skill2, 3, effect: .heart, say: .scarf)]
        case .spinSlash:
            return engage([.play(.skill1, 0.3, say: .spinSlash),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.slash(color: Pet.steel, facing: self.facing, count: 3, full: true)
                               self.blastAround(radius: 210)
                           },
                           .play(.skill1, 1.7),
                           .play(.idle, 0.8)])
        case .cleaning:
            // Ties on his bandana and sweeps, then tidies the desktop for real.
            let tidy = !inRoom && world.arranger == nil ? arrangePlan() : []
            return [.play(.skill2, 2.5, say: .cleaning)] + tidy
        case .divergentFist:
            // The punch, then the delayed second impact of cursed energy.
            return engage([.play(.skill1, 0.5, say: .divergentFist),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.shockwave(color: Pet.cursed, dx: self.facing * 34, dy: 62, rings: 2)
                               self.blastAhead(radius: 230)
                           },
                           .play(.skill1, 1),
                           .play(.happy, 1, effect: .sparkle)])
        case .sukuna:
            return engage([.play(.surprised, 0.4, effect: .exclaim),
                           .run { [weak self] in self?.view.aura(for: 3.5, color: Pet.scarlet) },
                           .play(.skill2, 3.5, say: .sukuna),
                           .run { [weak self] in self?.view.puff() },
                           .play(.surprised, 0.8, effect: .sweat)])
        case .infiniteVoid:
            for friend in nearbyFriends(within: 600) { friend.receive(.stunned(self)) }
            return engage([.play(.skill1, 0.6, say: .infiniteVoid),
                           .run { [weak self] in self?.view.domain(for: 4) },
                           .play(.skill1, 3.6),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .hollowPurple:
            // Blue and red come together into purple, then it fires.
            return engage([.play(.skill2, 1, say: .hollowPurple),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.beam(color: Pet.purple, facing: self.facing, dx: 34, dy: 62, for: 1.4)
                               let eye = CGPoint(x: self.position.x + self.facing * 34, y: self.position.y + 62)
                               self.blast(from: eye, radius: 440) { ($0.x - eye.x) * self.facing > 0 && abs($0.y - eye.y) < 110 }
                           },
                           .hold(.skill2, 1.4),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .divineDogs:
            return engage([.play(.skill1, 0.8, say: .divineDogs),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.runners(.dog, count: 2, facing: self.facing)
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.blastAhead(radius: 280) }
                           },
                           .play(.skill1, 1.2),
                           .play(.idle, 0.6)])
        case .rabbitEscape:
            return engage([.play(.skill2, 0.6, say: .rabbitEscape),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.runners(.rabbit, count: 12, facing: self.facing, size: 30, scatter: true)
                           },
                           .play(.skill2, 1.8),
                           .play(.idle, 0.6)])
        case .jajanken:
            // Charges through rock, paper... and the last frame is the punch.
            return engage([.line(.jajanken, to: nil),
                           .hold(.skill1, 1),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.shockwave(color: Pet.thunder, dx: self.facing * 36, dy: 56, rings: 3)
                               self.view.shake()
                               self.blastAhead(radius: 250)
                           },
                           .hold(.skill1, 0.6),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .fishing:
            return engage([.line(.fishing, to: nil),
                           .play(.skill2, 3.5),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.shockwave(color: Pet.water, dx: self.facing * 70, dy: 6, rings: 2, to: 2)
                           },
                           .play(.happy, 1.8, effect: .sparkle, say: .fishCaught)])
        case .godspeed:
            // Zips back and forth in a few flashes of lightning.
            let zap: Step = .run { [weak self] in
                guard let self else { return }
                self.facing = Bool.random() ? 1 : -1
                self.dash(150, color: Pet.thunder)
                self.view.lightning(dx: 0, color: Pet.cursed)
            }
            return engage([.play(.skill1, 0.6, say: .godspeed),
                           .run { [weak self] in self?.view.sparks(color: Pet.cursed, for: 2) },
                           zap, .play(.skill1, 0.4), zap, .play(.skill1, 0.4), zap,
                           .play(.skill1, 0.6),
                           .play(.happy, 1, effect: .sparkle)])
        case .chocolate:
            return [.play(.skill2, 2.5, effect: .heart, say: .chocolate)]
        case .chainJail:
            // The chain shoots out and drags the icons ahead back in a neat row at his feet.
            return engage([.play(.skill1, 0.5, say: .chainJail),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.chain(facing: self.facing)
                               guard !self.inRoom else { return }
                               let icons = self.world.availableIcons()
                                   .filter { ($0.center.x - self.position.x) * self.facing > 0
                                       && hypot($0.center.x - self.position.x, $0.center.y - self.position.y) < 380 }
                                   .prefix(4)
                               let frame = self.screenFrame(containing: self.position)
                               var paths: [String: [CGPoint]] = [:]
                               for (i, icon) in icons.enumerated() {
                                   let x = self.position.x + self.facing * CGFloat(i + 1) * 60
                                   paths[icon.name] = [CGPoint(x: min(max(x, frame.minX + 40), frame.maxX - 40),
                                                               y: min(max(self.position.y + 30, frame.minY + 40), frame.maxY - 60))]
                               }
                               if !paths.isEmpty { self.world.desktop.moveAll(paths) }
                           },
                           .play(.skill1, 1.5),
                           .play(.idle, 0.6)])
        case .scarletEyes:
            return engage([.play(.surprised, 0.4, effect: .exclaim),
                           .run { [weak self] in self?.view.aura(for: 3, color: Pet.scarlet) },
                           .play(.skill2, 3, say: .scarletEyes),
                           .play(.idle, 0.8)])
        case .knightOath:
            // Raises the sword (frames 0–3), then cuts on the way down and holds the finish.
            return engage([.line(.knightOath, to: nil),
                           .run { [weak self] in self?.view.sparks(color: Pet.thunder, for: 0.5) },
                           .hold(.skill1, 0.5),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.slash(color: Pet.steel, facing: self.facing)
                               self.blastAhead(radius: 220)
                           },
                           .hold(.skill1, 1),
                           .play(.happy, 1.2, effect: .heart)])
        case .shieldBash:
            // The shield hits on frame 3 of the 8-frame shove.
            return engage([.play(.skill2, 0.4, say: .shieldBash),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.impact(dx: self.facing * 52)
                               self.view.shake()
                               self.blastAhead(radius: 200, reach: 30)
                           },
                           .play(.skill2, 1.6),
                           .play(.happy, 1.2, effect: .sparkle)])
        case .guguChant:
            // Frame 4 (zero-based) opens the flippers for the big "gaga!".
            return engage([.line(.guguChant, to: nil),
                           .hold(.skill1, 0.5),
                           .run { [weak self] in
                               guard let self else { return }
                               self.view.sparks(color: Pet.thunder, for: 0.7)
                               for friend in self.nearbyFriends(within: 420) { friend.receive(.applaud(self)) }
                           },
                           .hold(.skill1, 0.5),
                           .play(.happy, 1.2, effect: .heart)])
        case .bellySlide:
            // Frame 3 starts the belly slide; hold continues the same animation clock.
            return engage([.line(.bellySlide, to: nil),
                           .hold(.skill2, 0.375),
                           .run { [weak self] in self?.dash(140, color: Pet.water) },
                           .hold(.skill2, 0.625),
                           .play(.happy, 1, effect: .sparkle)])
        }
    }

    /// Colors for the anime series' moves.
    private static let water = CGColor(srgbRed: 0.3, green: 0.62, blue: 1, alpha: 0.9)
    private static let fire = CGColor(srgbRed: 1, green: 0.5, blue: 0.15, alpha: 0.9)
    private static let steel = CGColor(srgbRed: 0.85, green: 0.9, blue: 0.95, alpha: 0.9)
    private static let thunder = CGColor(srgbRed: 1, green: 0.85, blue: 0.25, alpha: 1)
    private static let cursed = CGColor(srgbRed: 0.35, green: 0.55, blue: 1, alpha: 1)
    private static let purple = CGColor(srgbRed: 0.65, green: 0.3, blue: 1, alpha: 1)
    private static let scarlet = CGColor(srgbRed: 1, green: 0.15, blue: 0.2, alpha: 1)

    /// Blasts the icons (and friends) in front of the pet, from about waist height.
    private func blastAhead(radius: CGFloat, reach: CGFloat = 0) {
        let origin = CGPoint(x: position.x + facing * reach, y: position.y + 50)
        blast(from: origin, radius: radius) { [facing] in ($0.x - origin.x) * facing > -20 }
    }

    /// Blasts everything around the pet.
    private func blastAround(radius: CGFloat) {
        blast(from: CGPoint(x: position.x, y: position.y + 50), radius: radius) { _ in true }
    }

    /// Jumps `distance` points ahead in an instant (staying on screen, or on the room's floor), clearing the way.
    private func dash(_ distance: CGFloat, color: CGColor) {
        let from = position
        position = confined(clampToScreens(CGPoint(x: position.x + facing * distance, y: position.y)))
        view.streak(facing: facing, color: color)
        blast(from: CGPoint(x: (from.x + position.x) / 2, y: position.y + 50), radius: abs(position.x - from.x) / 2 + 60) { _ in true }
    }

    /// Friends on the same side of the room walls who are free to join in.
    private func nearbyFriends(within distance: CGFloat) -> [Pet] {
        world.pets.values.filter {
            $0 !== self && $0.isAvailable && $0.inRoom == inRoom
                && hypot($0.position.x - position.x, $0.position.y - position.y) < distance
        }
    }

    /// Sends the desktop icons within `radius` of `origin` that `hits` accepts flying outward (never from inside
    /// the room), and catches friends standing there.
    private func blast(from origin: CGPoint, radius: CGFloat, hits: (CGPoint) -> Bool) {
        func reached(_ p: CGPoint) -> Bool { hypot(p.x - origin.x, p.y - origin.y) < radius && hits(p) }
        for other in world.pets.values where other !== self && other.agent == nil && other.inRoom == inRoom
            && reached(CGPoint(x: other.position.x, y: other.position.y + 55)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak other] in
                if let self, let other { other.receive(.hit(self)) }
            }
        }
        guard !inRoom else { return }
        var paths: [String: [CGPoint]] = [:]
        for icon in world.availableIcons() where reached(icon.center) {
            let dx = icon.center.x - origin.x, dy = icon.center.y - origin.y
            let length = max(hypot(dx, dy), 1)
            paths[icon.name] = flightPath(of: icon.center, direction: CGVector(dx: dx / length, dy: dy / length),
                                          distance: .random(in: 150...260))
            world.claim(icon.name)
        }
        guard !paths.isEmpty else { return }
        let world = self.world
        world.desktop.moveAll(paths) { _ in paths.keys.forEach(world.release) }
    }

    // MARK: - Room

    /// Shut in the play room: stays on its floor and only plays with roommates.
    var inRoom: Bool { agent == nil && world.room.isOpen && world.room.members.contains(character.id) }

    /// Where the pet may go: anywhere, or only onto the room's floor while shut in.
    private func confined(_ p: CGPoint) -> CGPoint {
        guard inRoom else { return p }
        let f = world.room.floor
        return CGPoint(x: min(max(p.x, f.minX), f.maxX), y: min(max(p.y, f.minY), f.maxY))
    }

    /// Pops onto the room's floor when put in the room, dropping whatever it was busy with.
    func moveIntoRoom() {
        guard inRoom, !world.room.floor.contains(position) else { return }
        if let name = carrying { drop(name, at: carryPoint) }
        if let name = kickTarget { world.release(name); kickTarget = nil }
        if world.arranger === self { world.arranger = nil }
        view.showProp(nil, dx: 0)
        position = world.room.randomSpot()
        steps = [.play(.surprised, 0.5, effect: .sparkle), .play(.happy, 1.4, effect: .heart, say: .happy)]
        current = nil
        holding = false
        engaged = false
    }

    /// Moves along with the room when it is moved or resized.
    func followRoom(by shift: CGVector) {
        guard inRoom else { return }
        position = confined(CGPoint(x: position.x + shift.dx, y: position.y + shift.dy))
    }

    // MARK: - Mouse

    func clicked() {
        guard !leaving else { return }
        // Clicking a mascot that is waiting for you jumps to its terminal; it then hides until the agent acts again.
        if let agent, agent.state == .done || agent.state == .needsInput {
            AgentMonitor.focusHostApp(of: agent.pid)
            interrupt([.play(.happy, 0.6, effect: .heart), .run { [weak self] in self?.disappear() }])
            return
        }
        let t = now
        clicks = clicks.filter { t - $0 < 3 } + [t]
        if anim == .sleep {
            interrupt([.play(.surprised, 0.7, effect: .exclaim),
                       .play(character.grumpyAnim, 1.8, effect: .anger, say: .wake)])
        } else if clicks.count >= 4 {
            clicks.removeAll()
            // Too much attention: Bocchi melts, everyone else gets cross.
            interrupt(character.skills.contains(.melt) ? skillPlan(.melt) : [.play(character.grumpyAnim, 2.2, effect: .anger, say: .poke)])
        } else {
            boredom = 0
            interrupt([.play(.happy, 1.3, effect: .heart, say: .click)])
        }
    }

    func beginDrag() {
        dragging = true
        holding = false
        effect = (.sweat, now, .infinity)
    }

    func drag(to p: CGPoint) { position = inRoom ? world.room.clampHeld(p) : p }

    func endDrag() {
        dragging = false
        effect = nil
        let floorTop = world.room.floor.maxY
        let landing: [Step] = inRoom && position.y > floorTop ? [.fall(floorTop)] : []
        interrupt(landing + [.play(.surprised, 0.5),
                   Bool.random() ? .play(.happy, 1.2, effect: .note, say: .happy)
                                 : .play(character.grumpyAnim, 1.5, effect: .anger, say: .grumpy)])
    }

    private func updateMousePassthrough() {
        let m = NSEvent.mouseLocation
        let local = CGPoint(x: m.x - window.fullFrame.minX, y: m.y - window.fullFrame.minY)
        let over = dragging || view.bodyRect.contains(local)
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
    }

    // MARK: - Screen geometry

    private func screenFrame(containing p: CGPoint) -> CGRect {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.frame.contains(p) }) { return s.visibleFrame }
        let nearest = screens.min { distance(p, $0.frame) < distance(p, $1.frame) }
        return nearest?.visibleFrame ?? .zero
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// Keeps the whole character inside a screen's visible area.
    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        let f = screenFrame(containing: p)
        return CGPoint(x: min(max(p.x, f.minX + 40), f.maxX - 40),
                       y: min(max(p.y, f.minY), f.maxY - 130))
    }

    private func randomDestination() -> CGPoint {
        if inRoom { return world.room.randomSpot() }
        let screens = NSScreen.screens
        let here = screens.first { $0.frame.contains(position) } ?? screens[0]
        let screen = Double.random(in: 0..<1) < 0.7 ? here : (screens.randomElement() ?? here)
        let f = screen.visibleFrame
        return CGPoint(x: .random(in: (f.minX + 60)...(f.maxX - 60)),
                       y: .random(in: f.minY...(f.minY + max(0, (f.height - 140) * 0.6))))
    }
}
