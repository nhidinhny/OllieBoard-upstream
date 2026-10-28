import AppKit

/// Small transparent, click-through panel that follows a pet around every screen.
/// Never straddles two screens: the window server flickers a window that does, so a pet on the seam is cut into
/// one window per screen (this one holds the larger part, `PetEdgeMirror` the rest).
final class PetWindow: NSPanel {
    static let size = CGSize(width: 240, height: 194)
    /// Where the pet's feet sit inside the window (bottom-left origin); room below is for the name tag.
    static let feet = CGPoint(x: 120, y: 22)

    /// The frame the window would have if it were never cut: what the pet's own coordinates refer to.
    private(set) var fullFrame = CGRect(origin: .zero, size: PetWindow.size)
    /// The screen holding the smaller part of a pet on the seam, nil when the pet is on one screen.
    private(set) var overhangScreen: NSScreen?
    private let petView: NSView

    init(view: NSView) {
        petView = view
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: CGRect(origin: .zero, size: Self.size))
        content.addSubview(view)
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Let the pet walk across screen edges without AppKit pushing the window back.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func place(feetAt p: CGPoint) {
        let full = CGRect(origin: CGPoint(x: (p.x - Self.feet.x).rounded(), y: (p.y - Self.feet.y).rounded()), size: Self.size)
        var slices: [(screen: NSScreen, part: CGRect)] = []
        for screen in NSScreen.screens {
            let part = screen.frame.intersection(full)
            if part.width > 0 && part.height > 0 { slices.append((screen, part)) }
        }
        slices.sort { $0.part.width * $0.part.height > $1.part.width * $1.part.height }
        let mine = slices.count > 1 ? slices[0].part : full
        overhangScreen = slices.count > 1 ? slices[1].screen : nil
        fullFrame = full
        if mine != frame { setFrame(mine, display: false) }
        let offset = CGPoint(x: full.minX - mine.minX, y: full.minY - mine.minY)
        if petView.frame.origin != offset { petView.setFrameOrigin(offset) }
    }
}

/// Shows the part of a pet that hangs over onto a second screen. A window is only drawn on the screen it mostly
/// sits on, so a pet crossing the seam would be cut off and then jump; this window sits entirely on the other
/// screen and displays that part from a snapshot of the pet's own view.
final class PetEdgeMirror: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView()
        content.wantsLayer = true
        content.layer?.contentsGravity = .resize
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// `windowFrame` is the pet window's frame; only its overlap with `screen` is shown.
    func show(copying view: PetView, windowFrame: CGRect, on screen: NSScreen, level: NSWindow.Level) {
        let part = windowFrame.intersection(screen.frame)
        setFrame(part, display: false)
        self.level = level
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView?.layer?.contents = view.snapshot(scale: screen.backingScaleFactor)
        contentView?.layer?.contentsRect = CGRect(x: (part.minX - windowFrame.minX) / windowFrame.width,
                                                  y: (part.minY - windowFrame.minY) / windowFrame.height,
                                                  width: part.width / windowFrame.width,
                                                  height: part.height / windowFrame.height)
        CATransaction.commit()
        orderFrontRegardless()
    }
}

/// Layer-hosting view. The sprite and emote are CALayers whose contents are swapped per frame and
/// composited by the window server; only the bubble and name tag are drawn, and only when their text changes.
final class PetView: NSView {
    weak var pet: Pet?

    /// Area of the window covered by the character body, used for hit testing.
    let bodyRect = CGRect(x: PetWindow.feet.x - 30, y: PetWindow.feet.y, width: 60, height: 112)
    private let headTop = PetWindow.feet.y + 118
    private let effectOrigin = CGPoint(x: PetWindow.feet.x + 30, y: PetWindow.feet.y + 82)

    private let spriteLayer = CALayer()
    private let effectLayer = CALayer()
    private let textLayer = CALayer()
    /// A prop standing on the ground next to the pet (Frieren's treasure chest).
    private let propLayer = CALayer()

    private var shownFrame: CGImage?
    private var shownFacing: CGFloat = 1
    private var shownScale: CGFloat = 1
    private var shownShift: CGFloat = 0
    private var shownThought = false
    private var shownEffect: CGImage?
    private var shownRise: CGFloat = -1
    private var shownBubble: String?
    private var shownTag: String?

    init() {
        super.init(frame: CGRect(origin: .zero, size: PetWindow.size))
        layer = CALayer()   // set before wantsLayer: we own the layer tree and AppKit never redraws it
        wantsLayer = true
        let layout = SpriteSheet.layout
        let size = layout.frameSize
        spriteLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        // Pin the frame's feet to the window's feet point, which is also the axis for flipping.
        spriteLayer.anchorPoint = CGPoint(x: layout.anchor.x / size, y: (size - layout.anchor.y) / size)
        spriteLayer.position = PetWindow.feet
        propLayer.bounds = spriteLayer.bounds
        propLayer.anchorPoint = spriteLayer.anchorPoint
        effectLayer.bounds = CGRect(x: 0, y: 0, width: 52, height: 52)
        effectLayer.anchorPoint = .zero
        textLayer.frame = bounds
        for sublayer in [propLayer, spriteLayer, effectLayer, textLayer] {
            sublayer.contentsGravity = .resize
            layer!.addSublayer(sublayer)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        textLayer.contents = overlayImage()
    }

    /// Applies the pet's current look; does nothing when nothing visible changed.
    func render(frame: CGImage?, facing: CGFloat, scale: CGFloat, shift: CGFloat, effect: CGImage?, effectAge: TimeInterval,
                bubble: String?, thought: Bool, tag: String?) {
        let rise = effect == nil ? 0 : (CGFloat(min(effectAge, 0.4) / 0.4) * 8).rounded()
        guard frame !== shownFrame || facing != shownFacing || scale != shownScale || shift != shownShift || effect !== shownEffect || rise != shownRise
                || bubble != shownBubble || thought != shownThought || tag != shownTag else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame !== shownFrame { spriteLayer.contents = frame }
        if facing != shownFacing || scale != shownScale {
            spriteLayer.setAffineTransform(CGAffineTransform(scaleX: facing * scale, y: scale))
        }
        if shift != shownShift { spriteLayer.position = CGPoint(x: PetWindow.feet.x + shift, y: PetWindow.feet.y) }
        if effect !== shownEffect { effectLayer.contents = effect }
        if rise != shownRise { effectLayer.position = CGPoint(x: effectOrigin.x, y: effectOrigin.y + rise) }
        if bubble != shownBubble || thought != shownThought || tag != shownTag {
            shownBubble = bubble
            shownThought = thought
            shownTag = tag
            textLayer.contents = overlayImage()
        }
        CATransaction.commit()
        shownFrame = frame
        shownFacing = facing
        shownScale = scale
        shownShift = shift
        shownEffect = effect
        shownRise = rise
    }

    /// What the pet looks like right now, drawn from the layer tree (animations still in flight are not included).
    func snapshot(scale: CGFloat) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        layer?.render(in: ctx)
        return ctx.makeImage()
    }

    /// Bubble and name tag rendered once into a bitmap at the screen's scale.
    private func overlayImage() -> CGImage? {
        guard shownBubble != nil || shownTag != nil else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        guard let ctx = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        if let tag = shownTag { drawTag(tag, feet: PetWindow.feet) }
        if let bubble = shownBubble { drawBubble(bubble, headTop: headTop, thought: shownThought) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Small name plate under the feet of agent mascots.
    private func drawTag(_ text: String, feet: CGPoint) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingTail
                return style
            }(),
        ])
        let size = string.size()
        let w = min(bounds.width - 8, ceil(size.width) + 12), h = ceil(size.height) + 4
        let rect = CGRect(x: feet.x - w / 2, y: feet.y - h - 4, width: w, height: h)
        NSColor(calibratedRed: 0.17, green: 0.16, blue: 0.22, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
        string.draw(with: rect.insetBy(dx: 6, dy: 2), options: [.usesLineFragmentOrigin])
    }

    /// Speech bubble with a pointer, or a rounder thought bubble trailing little puffs.
    private func drawBubble(_ text: String, headTop: CGFloat, thought: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.29, green: 0.18, blue: 0.23, alpha: 1),
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let maxWidth = bounds.width - 12
        let textSize = string.boundingRect(with: CGSize(width: maxWidth - 16, height: 60),
                                           options: [.usesLineFragmentOrigin]).size
        let w = min(maxWidth, ceil(textSize.width) + 16), h = ceil(textSize.height) + 10
        let rect = CGRect(x: (bounds.width - w) / 2, y: min(headTop + 12, bounds.height - h - 2), width: w, height: h)

        let radius: CGFloat = thought ? min(rect.height / 2, 14) : 9
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let tail = NSBezierPath()
        if thought {
            tail.appendOval(in: CGRect(x: rect.midX - 9, y: rect.minY - 9, width: 7, height: 6))
            tail.appendOval(in: CGRect(x: rect.midX - 13, y: rect.minY - 15, width: 4.5, height: 4))
        } else {
            tail.move(to: CGPoint(x: rect.midX - 5, y: rect.minY + 1))
            tail.line(to: CGPoint(x: rect.midX + 1, y: rect.minY - 7))
            tail.line(to: CGPoint(x: rect.midX + 5, y: rect.minY + 1))
        }
        NSColor.white.withAlphaComponent(0.96).setFill()
        path.fill(); tail.fill()
        NSColor(calibratedRed: 0.29, green: 0.18, blue: 0.23, alpha: 0.85).setStroke()
        path.lineWidth = 1.4
        path.stroke()
        if thought {
            tail.lineWidth = 1.2
            tail.stroke()
        }
        string.draw(with: rect.insetBy(dx: 8, dy: 5), options: [.usesLineFragmentOrigin])
    }

    // MARK: Special-move effects
    // Fire-and-forget Core Animation: once added, the window server runs them with no per-frame work here.

    private var feet: CGPoint { PetWindow.feet }
    private var bodyCenter: CGPoint { CGPoint(x: feet.x, y: feet.y + 52) }
    private var headCenter: CGPoint { CGPoint(x: feet.x + 2, y: feet.y + 98) }

    /// Adds a layer for `seconds` (behind the sprite, or in front of it below the bubble).
    private func addTransient(_ sublayer: CALayer, for seconds: TimeInterval, behind: Bool = false) {
        if behind { layer!.insertSublayer(sublayer, below: spriteLayer) } else { layer!.insertSublayer(sublayer, below: textLayer) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { sublayer.removeFromSuperlayer() }
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// An expanding, fading ring.
    private func ring(at center: CGPoint, radius: CGFloat, squash: CGFloat = 1, color: CGColor, width: CGFloat,
                      to scale: CGFloat, duration: TimeInterval, delay: TimeInterval = 0) {
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * squash, width: radius * 2, height: radius * 2 * squash), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color
        ring.lineWidth = width
        ring.position = center
        ring.opacity = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.4
        grow.toValue = scale
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.95, 0]
        fade.keyTimes = [0, 0.2, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        ring.add(group, forKey: nil)
        addTransient(ring, for: delay + duration + 0.1)
    }

    /// A one-off burst of particles; `configure` sets up the single emitter cell.
    private func burst(at point: CGPoint, image: Effect, rate: Float, for seconds: TimeInterval, lasting lifetime: Float,
                       size: CGSize = CGSize(width: 30, height: 30), behind: Bool = false, configure: (CAEmitterCell) -> Void) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .circle
        emitter.emitterSize = size
        let cell = CAEmitterCell()
        cell.contents = SpriteSheet.effect(image)
        cell.birthRate = rate
        cell.lifetime = lifetime
        configure(cell)
        emitter.emitterCells = [cell]
        addTransient(emitter, for: seconds + TimeInterval(lifetime) + 0.3, behind: behind)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { emitter.birthRate = 0 }
    }

    /// A puff of smoke (transformations, popping out of a chest, landing a blow).
    func puff(at point: CGPoint? = nil) {
        withoutActions {
            burst(at: point ?? bodyCenter, image: .puff, rate: 70, for: 0.12, lasting: 0.6) { cell in
                cell.velocity = 50; cell.velocityRange = 20; cell.emissionRange = .pi * 2
                cell.scale = 0.1; cell.scaleRange = 0.03; cell.scaleSpeed = 0.12
                cell.alphaSpeed = -1.6; cell.spinRange = 1.5
            }
        }
    }

    /// Anya's telepathy: rings rippling out from her head.
    func telepathy() {
        withoutActions {
            for i in 0..<4 {
                ring(at: headCenter, radius: 18, color: CGColor(srgbRed: 1, green: 0.44, blue: 0.66, alpha: 1), width: 2.5,
                     to: 2.8, duration: 1.1, delay: Double(i) * 0.4)
            }
        }
    }

    /// Nezuko's Exploding Blood: pink flames bursting out in every direction.
    func flameBurst() {
        withoutActions {
            ring(at: bodyCenter, radius: 30, color: CGColor(srgbRed: 1, green: 0.42, blue: 0.66, alpha: 1), width: 6,
                 to: 3.2, duration: 0.5)
            burst(at: bodyCenter, image: .flame, rate: 170, for: 0.35, lasting: 0.75, size: CGSize(width: 50, height: 60)) { cell in
                cell.lifetimeRange = 0.25
                cell.velocity = 115; cell.velocityRange = 40; cell.emissionRange = .pi * 2
                cell.yAcceleration = 90
                cell.scale = 0.12; cell.scaleRange = 0.05; cell.scaleSpeed = -0.08
                cell.alphaSpeed = -1.2
            }
        }
    }

    /// Frieren's spell: a field of flowers popping up around her feet, wilting after `seconds`.
    func flowerField(for seconds: TimeInterval) {
        let images = [Effect.flower1, .flower2, .flower3].compactMap(SpriteSheet.effect)
        let now = CACurrentMediaTime()
        withoutActions {
            for i in 0..<18 {
                let flower = CALayer()
                flower.contents = images[i % images.count]
                let size = CGFloat.random(in: 20...30)
                flower.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                flower.anchorPoint = CGPoint(x: 0.5, y: 0.03)   // the bottom of the stem
                let a = CGFloat.random(in: 0..<(2 * .pi)), r = CGFloat.random(in: 0.3...1)
                flower.position = CGPoint(x: feet.x + cos(a) * 104 * r, y: feet.y - 2 + sin(a) * 16 * r)
                let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                pop.values = [0, 1.25, 1]
                pop.keyTimes = [0, 0.7, 1]
                pop.duration = 0.45
                pop.beginTime = now + Double(i) * 0.07
                pop.fillMode = .backwards
                let wilt = CABasicAnimation(keyPath: "opacity")
                wilt.fromValue = 1
                wilt.toValue = 0
                wilt.duration = 0.6
                wilt.beginTime = now + seconds - 0.6
                wilt.fillMode = .forwards
                wilt.isRemovedOnCompletion = false
                flower.add(pop, forKey: "pop")
                flower.add(wilt, forKey: "wilt")
                // Flowers nearer the viewer than her feet grow in front of her.
                addTransient(flower, for: seconds, behind: flower.position.y > feet.y)
            }
            burst(at: CGPoint(x: feet.x, y: feet.y + 4), image: .sparkle, rate: 6, for: seconds - 1.5, lasting: 1.6,
                  size: CGSize(width: 200, height: 10)) { cell in
                cell.velocity = 20; cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.6
                cell.scale = 0.07; cell.scaleRange = 0.03; cell.alphaSpeed = -0.5
            }
        }
    }

    /// Notes floating up from Bocchi's guitar.
    func notes(for seconds: TimeInterval, facing: CGFloat) {
        withoutActions {
            burst(at: CGPoint(x: feet.x + facing * 10, y: feet.y + 40), image: .note, rate: 3, for: seconds, lasting: 2.2,
                  size: CGSize(width: 10, height: 10)) { cell in
                cell.velocity = 35; cell.velocityRange = 10
                cell.emissionLongitude = .pi / 2 - facing * 0.5; cell.emissionRange = 0.6
                cell.scale = 0.16; cell.scaleRange = 0.04; cell.alphaSpeed = -0.4; cell.spinRange = 0.8
                cell.redRange = 0.5; cell.greenRange = 0.3; cell.blueRange = 0.2
            }
        }
    }

    /// Rem's oni form: a pulsing glow behind her and light rising around her (tinted `color` for other moves).
    func aura(for seconds: TimeInterval, color: CGColor? = nil) {
        withoutActions {
            let glow = CAGradientLayer()
            glow.type = .radial
            glow.colors = color.map { [$0.copy(alpha: 0.55)!, $0.copy(alpha: 0)!] }
                ?? [CGColor(srgbRed: 0.75, green: 0.88, blue: 1, alpha: 0.55), CGColor(srgbRed: 0.55, green: 0.73, blue: 0.97, alpha: 0)]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            glow.bounds = CGRect(x: 0, y: 0, width: 150, height: 190)
            glow.position = CGPoint(x: bodyCenter.x, y: bodyCenter.y + 12)
            glow.opacity = 0
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0, 1, 0.6, 1, 0.6, 1, 0]
            pulse.duration = seconds
            glow.add(pulse, forKey: nil)
            addTransient(glow, for: seconds, behind: true)
            burst(at: CGPoint(x: feet.x, y: feet.y + 10), image: .glow, rate: 22, for: seconds - 0.5, lasting: 1.3,
                  size: CGSize(width: 70, height: 20)) { cell in
                cell.velocity = 30; cell.velocityRange = 10; cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.3
                cell.scale = 0.07; cell.scaleRange = 0.03; cell.alphaSpeed = -0.7
                if let color { cell.color = color }
            }
        }
    }

    /// Tập's Skynet robot: a red laser from its eyes to the edge of the window, sparking where it ends.
    func laser(for seconds: TimeInterval, facing: CGFloat) {
        let eye = CGPoint(x: feet.x + facing * 43, y: feet.y + 62)
        let end = CGPoint(x: facing > 0 ? bounds.maxX : bounds.minX, y: eye.y - 6)
        withoutActions {
            for (width, color) in [(7.0, CGColor(srgbRed: 1, green: 0.18, blue: 0.15, alpha: 0.35)),
                                   (2.4, CGColor(srgbRed: 1, green: 0.45, blue: 0.4, alpha: 1))] {
                let beam = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: eye); path.addLine(to: end)
                beam.path = path
                beam.strokeColor = color
                beam.lineWidth = width
                beam.lineCap = .round
                beam.opacity = 0
                let flicker = CAKeyframeAnimation(keyPath: "opacity")
                flicker.values = [0, 1, 0.7, 1, 0.8, 1, 0.75, 1, 0]
                flicker.duration = seconds
                beam.add(flicker, forKey: nil)
                addTransient(beam, for: seconds)
            }
            ring(at: eye, radius: 6, color: CGColor(srgbRed: 1, green: 0.2, blue: 0.15, alpha: 1), width: 1.6,
                 to: 2.6, duration: 0.5)
            burst(at: CGPoint(x: end.x - facing * 6, y: end.y), image: .sparkle, rate: 30, for: seconds, lasting: 0.5,
                  size: CGSize(width: 8, height: 8)) { cell in
                cell.velocity = 60; cell.velocityRange = 25
                cell.emissionLongitude = facing > 0 ? .pi : 0; cell.emissionRange = 1.2
                cell.scale = 0.06; cell.scaleRange = 0.02; cell.alphaSpeed = -1.8
                cell.color = CGColor(srgbRed: 1, green: 0.35, blue: 0.3, alpha: 1)
            }
        }
    }

    /// Kim's missile coming down as fireworks: a flash, three bursts, a comic "BOOM!" and falling glitter.
    func fireworks(facing: CGFloat) {
        let center = CGPoint(x: feet.x + facing * 44, y: feet.y + 128)
        let now = CACurrentMediaTime()
        withoutActions {
            let flash = CAGradientLayer()
            flash.type = .radial
            flash.colors = [CGColor(srgbRed: 1, green: 1, blue: 0.85, alpha: 0.95), CGColor(srgbRed: 1, green: 0.75, blue: 0.3, alpha: 0)]
            flash.startPoint = CGPoint(x: 0.5, y: 0.5)
            flash.endPoint = CGPoint(x: 1, y: 1)
            flash.bounds = CGRect(x: 0, y: 0, width: 150, height: 150)
            flash.position = center
            flash.opacity = 0
            let pop = CAKeyframeAnimation(keyPath: "opacity")
            pop.values = [0, 1, 0]
            pop.keyTimes = [0, 0.15, 1]
            pop.duration = 0.5
            flash.add(pop, forKey: nil)
            addTransient(flash, for: 0.6)

            let colors: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.8, 0.32), (1, 0.38, 0.45), (0.45, 0.8, 1)]
            let offsets: [CGPoint] = [.zero, CGPoint(x: -facing * 52, y: -22), CGPoint(x: facing * 40, y: -30)]
            for (k, (r, g, b)) in colors.enumerated() {
                let c = CGPoint(x: center.x + offsets[k].x, y: center.y + offsets[k].y)
                let delay = Double(k) * 0.35
                ring(at: c, radius: 16, color: CGColor(srgbRed: r, green: g, blue: b, alpha: 1), width: 3, to: 3.4,
                     duration: 0.6, delay: delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.withoutActions {
                        self?.burst(at: c, image: .sparkle, rate: 120, for: 0.15, lasting: 0.9, size: CGSize(width: 10, height: 10)) { cell in
                            cell.velocity = 75; cell.velocityRange = 20; cell.emissionRange = .pi * 2
                            cell.yAcceleration = -40
                            cell.scale = 0.1; cell.scaleRange = 0.04; cell.alphaSpeed = -1
                            cell.color = CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
                        }
                    }
                }
            }

            let boom = CALayer()
            boom.contents = SpriteSheet.effect(.boom)
            boom.bounds = CGRect(x: 0, y: 0, width: 86, height: 86)
            boom.position = CGPoint(x: center.x, y: center.y - 8)
            boom.opacity = 0
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = [0.2, 1.25, 1, 1, 0.8]
            grow.keyTimes = [0, 0.15, 0.25, 0.8, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.8, 1]
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 1.5
            group.beginTime = now + 0.1
            boom.add(group, forKey: nil)
            addTransient(boom, for: 1.7)

            burst(at: CGPoint(x: center.x, y: center.y + 20), image: .sparkle, rate: 25, for: 1.2, lasting: 1.6,
                  size: CGSize(width: 140, height: 20)) { cell in
                cell.velocity = 10; cell.emissionLongitude = -.pi / 2; cell.yAcceleration = -45
                cell.scale = 0.05; cell.scaleRange = 0.02; cell.alphaSpeed = -0.6
                cell.redRange = 0.4; cell.greenRange = 0.4; cell.blueRange = 0.4
            }
        }
        shake()
    }

    /// Trump's wall: rising out of the ground in front of him course by course, then sinking back after `seconds`.
    func wall(for seconds: TimeInterval, facing: CGFloat) {
        let length = bounds.maxX - feet.x - 18, height: CGFloat = 88
        let now = CACurrentMediaTime()
        withoutActions {
            // Clipped at the ground line, so the wall seems to come up out of it.
            let ground = CALayer()
            ground.frame = CGRect(x: facing > 0 ? feet.x + 18 : feet.x - 18 - length, y: feet.y - 3, width: length, height: height)
            ground.masksToBounds = true
            let wall = CALayer()
            wall.contents = SpriteSheet.effect(.wall)
            wall.frame = ground.bounds
            wall.position = CGPoint(x: length / 2, y: -height / 2)
            ground.addSublayer(wall)
            let rise = CAKeyframeAnimation(keyPath: "position.y")
            rise.values = [-height / 2, -height * 0.2, -height * 0.1, height * 0.2, height * 0.3, height / 2]
            rise.keyTimes = [0, 0.3, 0.4, 0.7, 0.8, 1]
            rise.duration = 0.9
            rise.fillMode = .forwards
            rise.isRemovedOnCompletion = false
            let sink = CABasicAnimation(keyPath: "position.y")
            sink.fromValue = height / 2
            sink.toValue = -height / 2
            sink.duration = 0.5
            sink.beginTime = now + seconds - 0.5
            sink.fillMode = .forwards
            sink.isRemovedOnCompletion = false
            wall.add(rise, forKey: "rise")
            wall.add(sink, forKey: "sink")
            addTransient(ground, for: seconds)
            burst(at: CGPoint(x: ground.frame.midX, y: feet.y), image: .puff, rate: 40, for: 0.9, lasting: 0.7,
                  size: CGSize(width: length, height: 4)) { cell in
                cell.velocity = 25; cell.velocityRange = 10; cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.8
                cell.scale = 0.08; cell.scaleRange = 0.03; cell.scaleSpeed = 0.08; cell.alphaSpeed = -1.4
            }
        }
        shake()
    }

    /// Trump's tariffs: gold coins pouring off his board toward whoever he faces.
    func coins(facing: CGFloat) {
        let board = CGPoint(x: feet.x + facing * 46, y: feet.y + 70)
        withoutActions {
            ring(at: board, radius: 14, color: CGColor(srgbRed: 1, green: 0.84, blue: 0.3, alpha: 1), width: 2.5, to: 3, duration: 0.5)
            burst(at: board, image: .coin, rate: 26, for: 1.2, lasting: 1.1, size: CGSize(width: 20, height: 30)) { cell in
                cell.velocity = 120; cell.velocityRange = 40
                cell.emissionLongitude = facing > 0 ? 0.35 : .pi - 0.35; cell.emissionRange = 0.5
                cell.yAcceleration = -160
                cell.scale = 0.11; cell.scaleRange = 0.03; cell.spinRange = 6; cell.alphaSpeed = -0.4
            }
        }
    }

    /// Kim's applause: confetti raining down on the crowd.
    func confetti(for seconds: TimeInterval) {
        withoutActions {
            burst(at: CGPoint(x: feet.x, y: feet.y + 150), image: .sparkle, rate: 30, for: seconds, lasting: 2,
                  size: CGSize(width: 220, height: 10)) { cell in
                cell.velocity = 20; cell.velocityRange = 10; cell.emissionLongitude = -.pi / 2; cell.emissionRange = 0.5
                cell.yAcceleration = -25
                cell.scale = 0.06; cell.scaleRange = 0.03; cell.spinRange = 4; cell.alphaSpeed = -0.4
                cell.redRange = 0.8; cell.greenRange = 0.8; cell.blueRange = 0.8
            }
        }
    }

    /// Xi's parade: a convoy of tanks and armored trucks rolling past behind him.
    func convoy(for seconds: TimeInterval, facing: CGFloat) {
        let vehicles: [Effect] = [.tank, .truck, .tank, .truck]
        let drive = (seconds - 0.4) / 2, gap = drive / 3
        let now = CACurrentMediaTime()
        let from = facing > 0 ? bounds.minX - 50 : bounds.maxX + 50, to = facing > 0 ? bounds.maxX + 50 : bounds.minX - 50
        withoutActions {
            for (k, vehicle) in vehicles.enumerated() {
                let layer = CALayer()
                layer.contents = SpriteSheet.effect(vehicle)
                layer.bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
                layer.anchorPoint = CGPoint(x: 0.5, y: 0.03)
                layer.position = CGPoint(x: from, y: feet.y + 16)
                layer.setAffineTransform(CGAffineTransform(scaleX: facing, y: 1))
                let move = CABasicAnimation(keyPath: "position.x")
                move.fromValue = from
                move.toValue = to
                move.duration = drive
                move.beginTime = now + Double(k) * gap
                move.fillMode = .both
                let bounce = CAKeyframeAnimation(keyPath: "position.y")
                bounce.values = [feet.y + 16, feet.y + 17.5, feet.y + 16]
                bounce.duration = 0.25
                bounce.repeatCount = .infinity
                layer.add(move, forKey: "move")
                layer.add(bounce, forKey: "bounce")
                addTransient(layer, for: Double(k) * gap + drive + 0.1, behind: true)
            }
            burst(at: CGPoint(x: feet.x, y: feet.y + 16), image: .puff, rate: 8, for: seconds - 0.6, lasting: 0.8,
                  size: CGSize(width: 240, height: 4), behind: true) { cell in
                cell.velocity = 12; cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.6
                cell.scale = 0.06; cell.scaleRange = 0.02; cell.scaleSpeed = 0.06; cell.alphaSpeed = -1.2
            }
        }
    }

    /// Putin's bear ride: dust kicked up behind the galloping bear.
    func dust(for seconds: TimeInterval, facing: CGFloat) {
        withoutActions {
            burst(at: CGPoint(x: feet.x - facing * 30, y: feet.y + 6), image: .puff, rate: 18, for: seconds, lasting: 0.8,
                  size: CGSize(width: 20, height: 6), behind: true) { cell in
                cell.velocity = 60; cell.velocityRange = 20
                cell.emissionLongitude = facing > 0 ? .pi - 0.3 : 0.3; cell.emissionRange = 0.4
                cell.scale = 0.08; cell.scaleRange = 0.03; cell.scaleSpeed = 0.1; cell.alphaSpeed = -1.2
            }
        }
    }

    /// Sword arcs sweeping down in front of the pet, or `full` rings all around it (Tanjiro, Zoro, Levi, Mikasa).
    func slash(color: CGColor, facing: CGFloat, count: Int = 1, full: Bool = false) {
        let now = CACurrentMediaTime()
        withoutActions {
            for k in 0..<count {
                let r = 56 + CGFloat(k % 2) * 10
                let path = CGMutablePath()
                if full {
                    path.addEllipse(in: CGRect(x: -r, y: -r * 0.45, width: r * 2, height: r * 0.9))
                } else {
                    path.addArc(center: .zero, radius: r, startAngle: 1.4, endAngle: -0.9, clockwise: true)
                }
                for (width, stroke) in [(7.0, color), (2.2, CGColor(gray: 1, alpha: 0.95))] {
                    let arc = CAShapeLayer()
                    arc.path = path
                    arc.fillColor = nil
                    arc.strokeColor = stroke
                    arc.lineWidth = width
                    arc.lineCap = .round
                    arc.position = bodyCenter
                    arc.setAffineTransform(CGAffineTransform(scaleX: facing, y: 1).rotated(by: CGFloat(k) * 0.35 - 0.2))
                    arc.opacity = 0
                    let draw = CABasicAnimation(keyPath: "strokeEnd")
                    draw.fromValue = 0
                    draw.toValue = 1
                    draw.duration = 0.18
                    draw.fillMode = .forwards
                    let fade = CAKeyframeAnimation(keyPath: "opacity")
                    fade.values = [1, 1, 0]
                    fade.keyTimes = [0, 0.4, 1]
                    let group = CAAnimationGroup()
                    group.animations = [draw, fade]
                    group.duration = 0.5
                    group.beginTime = now + Double(k) * 0.16
                    arc.add(group, forKey: nil)
                    addTransient(arc, for: Double(k) * 0.16 + 0.6)
                }
            }
        }
    }

    /// A bolt of lightning from the top of the window down to the ground `dx` points from the pet (Nami, Eren, Killua).
    func lightning(dx: CGFloat, color: CGColor = CGColor(srgbRed: 1, green: 0.88, blue: 0.3, alpha: 1)) {
        let ground = CGPoint(x: feet.x + dx, y: feet.y + 4)
        let path = CGMutablePath()
        var p = CGPoint(x: ground.x + .random(in: -20...20), y: bounds.maxY)
        path.move(to: p)
        while p.y > ground.y + 30 {
            p = CGPoint(x: ground.x + .random(in: -16...16), y: p.y - .random(in: 16...28))
            path.addLine(to: p)
        }
        path.addLine(to: ground)
        withoutActions {
            for (width, stroke) in [(8.0, color.copy(alpha: 0.4)!), (2.6, CGColor(gray: 1, alpha: 1))] {
                let bolt = CAShapeLayer()
                bolt.path = path
                bolt.fillColor = nil
                bolt.strokeColor = stroke
                bolt.lineWidth = width
                bolt.lineJoin = .round
                bolt.opacity = 0
                let flicker = CAKeyframeAnimation(keyPath: "opacity")
                flicker.values = [0, 1, 0.2, 1, 0.6, 0]
                flicker.duration = 0.5
                bolt.add(flicker, forKey: nil)
                addTransient(bolt, for: 0.55)
            }
            ring(at: ground, radius: 20, squash: 0.3, color: color, width: 3, to: 2.4, duration: 0.45)
            burst(at: ground, image: .sparkle, rate: 80, for: 0.15, lasting: 0.6, size: CGSize(width: 12, height: 6)) { cell in
                cell.velocity = 70; cell.velocityRange = 25; cell.emissionLongitude = .pi / 2; cell.emissionRange = 1.4
                cell.yAcceleration = -120
                cell.scale = 0.06; cell.scaleRange = 0.02; cell.alphaSpeed = -1.6
                cell.color = color
            }
        }
    }

    /// Speed lines trailing behind a pet that just dashed toward `facing`.
    func streak(facing: CGFloat, color: CGColor) {
        withoutActions {
            for k in 0..<5 {
                let y = feet.y + 14 + CGFloat(k) * 20
                let line = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: feet.x - facing * 24, y: y))
                path.addLine(to: CGPoint(x: feet.x - facing * CGFloat.random(in: 80...118), y: y))
                line.path = path
                line.strokeColor = color
                line.lineWidth = 3
                line.lineCap = .round
                line.opacity = 0
                let slide = CABasicAnimation(keyPath: "position.x")
                slide.fromValue = 0
                slide.toValue = -facing * 30
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.9
                fade.toValue = 0
                let group = CAAnimationGroup()
                group.animations = [slide, fade]
                group.duration = 0.45
                line.add(group, forKey: nil)
                addTransient(line, for: 0.5)
            }
        }
    }

    /// Rings bursting out of a point `dx`, `dy` from the feet (a punch landing, a fish splashing).
    func shockwave(color: CGColor, dx: CGFloat = 0, dy: CGFloat = 52, rings count: Int = 2, to scale: CGFloat = 3) {
        withoutActions {
            for i in 0..<count {
                ring(at: CGPoint(x: feet.x + dx, y: feet.y + dy), radius: 18, color: color, width: 4, to: scale,
                     duration: 0.5, delay: Double(i) * 0.15)
            }
        }
    }

    /// A thick glowing beam from `dx`, `dy` to the edge of the window it faces (Gojo's Hollow Purple).
    func beam(color: CGColor, facing: CGFloat, dx: CGFloat, dy: CGFloat, for seconds: TimeInterval) {
        let start = CGPoint(x: feet.x + facing * dx, y: feet.y + dy)
        let end = CGPoint(x: facing > 0 ? bounds.maxX : bounds.minX, y: start.y)
        withoutActions {
            for (width, stroke) in [(26.0, color.copy(alpha: 0.35)!), (12.0, color), (4.0, CGColor(gray: 1, alpha: 0.95))] {
                let ray = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                ray.path = path
                ray.strokeColor = stroke
                ray.lineWidth = width
                ray.lineCap = .round
                ray.opacity = 0
                let flicker = CAKeyframeAnimation(keyPath: "opacity")
                flicker.values = [0, 1, 0.8, 1, 0.85, 1, 0]
                flicker.duration = seconds
                ray.add(flicker, forKey: nil)
                addTransient(ray, for: seconds)
            }
            ring(at: start, radius: 12, color: color, width: 3, to: 2.6, duration: 0.5)
        }
        shake()
    }

    /// Particles rising around the pet, tinted `color` (Luffy's Gear Fifth, Killua's lightning).
    func sparks(color: CGColor, for seconds: TimeInterval) {
        withoutActions {
            burst(at: CGPoint(x: feet.x, y: feet.y + 30), image: .sparkle, rate: 24, for: seconds, lasting: 1,
                  size: CGSize(width: 80, height: 60)) { cell in
                cell.velocity = 35; cell.velocityRange = 15; cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.8
                cell.scale = 0.06; cell.scaleRange = 0.03; cell.spinRange = 3; cell.alphaSpeed = -0.9
                cell.color = color
            }
        }
    }

    /// Gojo's domain: a dark, starry dome swelling out around him for `seconds`.
    func domain(for seconds: TimeInterval) {
        withoutActions {
            let dome = CAGradientLayer()
            dome.type = .radial
            dome.colors = [CGColor(srgbRed: 0.1, green: 0.05, blue: 0.25, alpha: 0.85), CGColor(srgbRed: 0.35, green: 0.2, blue: 0.7, alpha: 0.5),
                           CGColor(srgbRed: 0.5, green: 0.4, blue: 1, alpha: 0)]
            dome.startPoint = CGPoint(x: 0.5, y: 0.5)
            dome.endPoint = CGPoint(x: 1, y: 1)
            dome.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 1.2)
            dome.position = bodyCenter
            dome.opacity = 0
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.1
            grow.toValue = 1
            grow.duration = 0.6
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.85, 1]
            fade.duration = seconds
            dome.add(grow, forKey: "grow")
            dome.add(fade, forKey: "fade")
            addTransient(dome, for: seconds, behind: true)
            burst(at: bodyCenter, image: .sparkle, rate: 20, for: seconds - 0.8, lasting: 1.2,
                  size: CGSize(width: bounds.width * 0.8, height: 140), behind: true) { cell in
                cell.velocity = 6; cell.emissionRange = .pi * 2
                cell.scale = 0.04; cell.scaleRange = 0.02; cell.alphaSpeed = -0.6
                cell.color = CGColor(srgbRed: 0.8, green: 0.85, blue: 1, alpha: 1)
            }
        }
    }

    /// Animals (`image`, drawn facing +x) dashing from the pet off the side of the window it faces,
    /// or scattering both ways when `scatter` is set (Megumi's shikigami).
    func runners(_ image: Effect, count: Int, facing: CGFloat, size: CGFloat = 50, scatter: Bool = false) {
        let now = CACurrentMediaTime()
        withoutActions {
            for k in 0..<count {
                let side = scatter ? (k % 2 == 0 ? facing : -facing) : facing
                let y = feet.y + 2 + CGFloat.random(in: -6...8)
                let runner = CALayer()
                runner.contents = SpriteSheet.effect(image)
                runner.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                runner.anchorPoint = CGPoint(x: 0.5, y: 0.03)
                runner.position = CGPoint(x: feet.x, y: y)
                runner.setAffineTransform(CGAffineTransform(scaleX: side, y: 1))
                let delay = Double(k) * (scatter ? 0.06 : 0.15)
                let run = CABasicAnimation(keyPath: "position.x")
                run.fromValue = feet.x + side * 10
                run.toValue = side > 0 ? bounds.maxX + size : bounds.minX - size
                run.duration = scatter ? .random(in: 0.6...0.9) : 0.8
                run.beginTime = now + delay
                run.fillMode = .both
                let hop = CAKeyframeAnimation(keyPath: "position.y")
                hop.values = [y, y + 8, y]
                hop.duration = 0.22
                hop.repeatCount = .infinity
                runner.add(run, forKey: "run")
                runner.add(hop, forKey: "hop")
                addTransient(runner, for: delay + run.duration + 0.1)
            }
            puff(at: CGPoint(x: feet.x + facing * 10, y: feet.y + 16))
        }
    }

    /// Kurapika's chain shooting out toward `facing` and reeling back in.
    func chain(facing: CGFloat) {
        let hand = CGPoint(x: feet.x + facing * 22, y: feet.y + 58)
        let end = CGPoint(x: facing > 0 ? bounds.maxX - 6 : bounds.minX + 6, y: feet.y + 30)
        withoutActions {
            for (width, stroke, dash) in [(6.0, CGColor(gray: 0.25, alpha: 1), [7, 4] as [NSNumber]),
                                          (3.0, CGColor(gray: 0.85, alpha: 1), [7, 4] as [NSNumber])] {
                let links = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: hand)
                path.addQuadCurve(to: end, control: CGPoint(x: (hand.x + end.x) / 2, y: hand.y + 24))
                links.path = path
                links.fillColor = nil
                links.strokeColor = stroke
                links.lineWidth = width
                links.lineDashPattern = dash
                links.strokeEnd = 0
                let shoot = CAKeyframeAnimation(keyPath: "strokeEnd")
                shoot.values = [0, 1, 1, 0]
                shoot.keyTimes = [0, 0.25, 0.7, 1]
                shoot.duration = 1.4
                links.add(shoot, forKey: nil)
                addTransient(links, for: 1.4)
            }
        }
    }

    /// A short jolt of the sprite, for big impacts.
    func shake() {
        let jolt = CAKeyframeAnimation(keyPath: "position.x")
        jolt.values = [0, -3, 3, -2, 2, 0]
        jolt.duration = 0.35
        jolt.isAdditive = true
        spriteLayer.add(jolt, forKey: "shake")
    }

    /// Rem's morning star hitting the ground `dx` points in front of her.
    func impact(dx: CGFloat) {
        let ground = CGPoint(x: feet.x + dx, y: feet.y + 4)
        withoutActions {
            ring(at: ground, radius: 22, squash: 0.3, color: CGColor(gray: 0.45, alpha: 1), width: 3, to: 2.2, duration: 0.45)
        }
        puff(at: ground)
    }

    /// Shows `image` standing on the ground `dx` points from the pet, or removes it.
    func showProp(_ image: CGImage?, dx: CGFloat) {
        withoutActions {
            propLayer.contents = image
            propLayer.position = CGPoint(x: feet.x + dx, y: feet.y)
        }
        guard image != nil else { return }
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0, 1.15, 1]
        pop.duration = 0.35
        propLayer.add(pop, forKey: "pop")
    }

    // MARK: Mouse

    private var grabOffset: CGPoint = .zero
    private var mouseDownAt: CGPoint = .zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        guard let pet else { return }
        let mouse = NSEvent.mouseLocation
        mouseDownAt = mouse
        grabOffset = CGPoint(x: mouse.x - pet.position.x, y: mouse.y - pet.position.y)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pet else { return }
        let mouse = NSEvent.mouseLocation
        if !didDrag && hypot(mouse.x - mouseDownAt.x, mouse.y - mouseDownAt.y) < 4 { return }
        if !didDrag { didDrag = true; pet.beginDrag() }
        pet.drag(to: CGPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { pet?.endDrag() } else { pet?.clicked() }
    }

    /// Right-click lists the character's special moves.
    override func rightMouseDown(with event: NSEvent) {
        guard let pet, pet.agent == nil, !pet.availableSkills.isEmpty else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: pet.character.displayName(in: Language.current), action: nil, keyEquivalent: "")
        for skill in pet.availableSkills {
            let item = menu.addItem(withTitle: skill.title, action: #selector(useSkill(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skill.rawValue
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func useSkill(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let skill = Skill(rawValue: raw) else { return }
        pet?.useSkill(skill)
    }
}
