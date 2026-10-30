import AppKit

enum Anim: String, CaseIterable {
    case idle, walk, run, kick, carry, happy, bored, yawn, sleep, grumpy, dragged, surprised, work, sad
    /// Each character's two special moves (see Skill); empty for agent mascots.
    case skill1, skill2

    /// Skills drawn together with their prop (see Pet.drawnSkillPlan): each is a row in the character's own
    /// `<id>-skills.png`, which only has the rows of that character's skills (skills.json lists them).
    case yoyo, inflate, eat, lift, sake, grill

    var isSkill: Bool { self == .skill1 || self == .skill2 }
}

enum Effect: String, CaseIterable {
    case heart, note, anger, zzz, dots, sweat, exclaim, sparkle, code, check
    // Props and particles for the special moves.
    case chest, flower1, flower2, flower3, flame, glow, puff, wall, coin, boom, tank, truck, dog, rabbit
}

/// One row of a character's skills sheet (skills.json): how many frames it has, how fast it plays and how far the
/// sprite is nudged sideways (in points, towards the way the character faces) so the character stands on the pet's spot.
struct SkillRow: Decodable {
    let name: String
    let frames: Int
    let fps: Double
    let loop: Bool
    let shift: CGFloat
}

/// Layout shared by every character sheet (written by SpriteGen).
struct SheetLayout: Decodable {
    struct AnimInfo: Decodable { let row: Int; let frames: Int; let fps: Double; let loop: Bool }
    struct Anchor: Decodable { let x: CGFloat; let y: CGFloat }

    let frameSize: CGFloat
    let pixelScale: CGFloat
    let anchor: Anchor        // feet position inside a frame, y measured from the top
    let animations: [String: AnimInfo]
    let effects: [String]     // emote icons, in order, in effects.png
}

final class SpriteSheet {
    static let directory: URL = {
        // Inside the .app the sprites live in Contents/Resources; with `swift run` they come from the SPM bundle.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Sprites"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return Bundle.module.resourceURL!.appendingPathComponent("Sprites")
    }()

    static let layout: SheetLayout = {
        let data = try! Data(contentsOf: directory.appendingPathComponent("layout.json"))
        return try! JSONDecoder().decode(SheetLayout.self, from: data)
    }()

    /// Skills-sheet rows per character id; empty when there is no skills.json.
    private static let skillRows: [String: [SkillRow]] = {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("skills.json")) else { return [:] }
        struct File: Decodable { let rows: [SkillRow] }
        return ((try? JSONDecoder().decode([String: File].self, from: data)) ?? [:]).mapValues(\.rows)
    }()

    private static var cache: [String: SpriteSheet] = [:]

    /// Shared so each sheet is decoded only once. Agent mascots have no special moves, so they skip those rows.
    static func named(_ id: String, skills: Bool = true) -> SpriteSheet {
        if let sheet = cache[id] { return sheet }
        let sheet = SpriteSheet(characterID: id, skills: skills)
        cache[id] = sheet
        return sheet
    }

    /// Emote icons shared by every character.
    private static let effects: [Effect: CGImage] = {
        let names = layout.effects
        let images = cells(of: "effects", names.indices.map { ($0, 0) })
        return Dictionary(uniqueKeysWithValues: zip(names, images).compactMap { name, image in
            Effect(rawValue: name).map { ($0, image) }
        })
    }()

    static func effect(_ effect: Effect) -> CGImage? { effects[effect] }

    private var frames: [Anim: [CGImage]] = [:]
    private var info: [Anim: SheetLayout.AnimInfo] = [:]
    private var shifts: [Anim: CGFloat] = [:]

    private init(characterID: String, skills: Bool) {
        let layout = Self.layout
        for anim in Anim.allCases where skills || !anim.isSkill {
            guard let row = layout.animations[anim.rawValue] else { continue }
            info[anim] = row
            frames[anim] = Self.cells(of: characterID, (0..<row.frames).map { ($0, row.row) })
        }
        // The character's drawn skills, one row each in <id>-skills.png.
        for (index, row) in (Self.skillRows[characterID] ?? []).enumerated() {
            guard let anim = Anim(rawValue: row.name) else { continue }
            info[anim] = SheetLayout.AnimInfo(row: index, frames: row.frames, fps: row.fps, loop: row.loop)
            shifts[anim] = row.shift
            frames[anim] = Self.cells(of: "\(characterID)-skills", (0..<row.frames).map { ($0, index) })
        }
    }

    /// Whether this character's sheets draw `anim` (the drawn skills exist only for the characters that have them).
    func has(_ anim: Anim) -> Bool { frames[anim] != nil }

    /// Whether the sheet has the animation(s) a skill needs (the skills of the main sheet always do).
    func hasSkill(_ skill: Skill) -> Bool {
        switch skill {
        case .yoyo: return has(.yoyo)
        case .balloon: return has(.inflate)
        case .eat: return has(.eat)
        case .lift: return has(.lift)
        case .sake: return has(.sake)
        case .grill: return has(.grill)
        default: return true
        }
    }

    /// Sideways nudge of the sprite while `anim` plays, in points towards the facing direction.
    func shift(_ anim: Anim) -> CGFloat { shifts[anim] ?? 0 }

    /// Cuts the given (column, row) cells out of `<name>.png`.
    private static func cells(of name: String, _ positions: [(Int, Int)]) -> [CGImage] {
        let url = directory.appendingPathComponent("\(name).png")
        guard let png = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fatalError("Missing sprite sheet \(url.path)")
        }
        let px = Int(layout.frameSize * layout.pixelScale)
        // Store frames in the display's color space so drawing them doesn't color-convert every frame.
        let space = NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        func bitmap(_ width: Int, _ height: Int) -> CGContext {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        }
        // Decode the PNG once (crops of a lazily-decoded PNG re-inflate the whole sheet on every draw),
        // then copy each used cell into its own small bitmap so the full sheet can be released.
        let decoded = bitmap(png.width, png.height)
        decoded.draw(png, in: CGRect(x: 0, y: 0, width: png.width, height: png.height))
        let sheet = decoded.makeImage()!
        func cell(_ col: Int, _ row: Int) -> CGImage {
            let copy = bitmap(px, px)
            copy.draw(sheet.cropping(to: CGRect(x: col * px, y: row * px, width: px, height: px))!,
                      in: CGRect(x: 0, y: 0, width: px, height: px))
            return copy.makeImage()!
        }
        return positions.map { cell($0.0, $0.1) }
    }

    /// Frame of `anim` after it has been playing for `elapsed` seconds.
    func frame(_ anim: Anim, elapsed: TimeInterval) -> CGImage? {
        guard let list = frames[anim], let info = info[anim] else { return nil }
        let i = Int(elapsed * info.fps)
        return list[info.loop ? i % list.count : min(i, list.count - 1)]
    }

    func duration(_ anim: Anim) -> TimeInterval {
        guard let info = info[anim] else { return 0 }
        return Double(info.frames) / info.fps
    }

}
