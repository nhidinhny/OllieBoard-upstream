import Foundation

enum Line: CaseIterable {
    case happy, bored, tedious, grumpy, kick, arrange, click, poke, wake, noIcons, fail, done
    // Lines aimed at another character; "%@" is replaced by their short name.
    case greet, greetBack, wakeOther, hit, sorry, pranked, chased, comfort, thanks, together
    // Agent mascots only; "{project}" is replaced by the session's project folder.
    case agentHello, agentWorking, agentDone, agentNeedsYou, agentBye
    // Special moves (see Skill); "{app}" is replaced by the app the user is in.
    case mindRead, mindReadIdle, readFriend, thought, bloodBurst, shrink, grow, flowers, mimicSpot, mimicEaten, mimicOut,
         guitar, guitarDone, cheer, melt, reform, morningStar, oni, oniCalm,
         wall, wallBuilt, tariff, judo, bear, parade, paradeOrder, aiRobot, aiRobotDone, applause, missile, boom,
         waterBreathing, hinokami, thunderclap, clingCry, gomuPistol, gear5, threeSword, getLost, lostAgain,
         climaTact, berries, titanShift, tatakae, odmGear, scarf, spinSlash, cleaning, divergentFist, sukuna,
         infiniteVoid, hollowPurple, divineDogs, rabbitEscape, jajanken, fishing, fishCaught, godspeed, chocolate,
         chainJail, scarletEyes, knightOath, shieldBash, guguChant, bellySlide, poisonTest, herbalBrew
    // Skills drawn with their prop (see Skill): Killua's yo-yo, Luffy puffing up and eating, Zoro's weights and sake,
    // Maomao's grill.
    case yoyo, yoyoDone, inflate, inflateDone, eat, lift, liftDone, sake, grill, grillDone

    static let agentOnly: Set<Line> = [.agentHello, .agentWorking, .agentDone, .agentNeedsYou, .agentBye]
    /// Special-move lines only some characters have: their own moves, or how they react to someone else's.
    static let skillSpeakers: [Line: Set<String>] = [
        .mindRead: ["anya"], .mindReadIdle: ["anya"], .readFriend: ["anya"],
        .thought: ["nezuko", "frieren", "bocchi", "rem"],
        .bloodBurst: ["nezuko"], .shrink: ["nezuko"], .grow: ["nezuko"],
        .flowers: ["frieren"], .mimicSpot: ["frieren"], .mimicEaten: ["frieren"], .mimicOut: ["frieren"],
        .guitar: ["bocchi"], .guitarDone: ["bocchi"], .melt: ["bocchi"], .reform: ["bocchi"],
        .cheer: ["anya", "nezuko", "frieren", "rem", "trump", "putin", "xi", "kim"],
        .morningStar: ["rem"], .oni: ["rem"], .oniCalm: ["rem"],
        .wall: ["trump"], .wallBuilt: ["trump"], .tariff: ["trump"],
        .judo: ["putin"], .bear: ["putin"],
        .parade: ["xi"], .paradeOrder: ["xi"], .aiRobot: ["xi"], .aiRobotDone: ["xi"],
        .applause: ["kim"], .missile: ["kim"], .boom: ["kim"],
        .waterBreathing: ["tanjiro"], .hinokami: ["tanjiro"], .thunderclap: ["zenitsu"], .clingCry: ["zenitsu"],
        .gomuPistol: ["luffy"], .gear5: ["luffy"], .threeSword: ["zoro"], .getLost: ["zoro"], .lostAgain: ["zoro"],
        .climaTact: ["nami"], .berries: ["nami"], .titanShift: ["eren"], .tatakae: ["eren"],
        .odmGear: ["mikasa"], .scarf: ["mikasa"], .spinSlash: ["levi"], .cleaning: ["levi"],
        .divergentFist: ["yuji"], .sukuna: ["yuji"], .infiniteVoid: ["gojo"], .hollowPurple: ["gojo"],
        .divineDogs: ["megumi"], .rabbitEscape: ["megumi"], .jajanken: ["gon"], .fishing: ["gon"], .fishCaught: ["gon"],
        .godspeed: ["killua"], .chocolate: ["killua"], .chainJail: ["kurapika"], .scarletEyes: ["kurapika"],
        .knightOath: ["catknight"], .shieldBash: ["catknight"],
        .guguChant: ["gugugaga"], .bellySlide: ["gugugaga"],
        .poisonTest: ["maomao"], .herbalBrew: ["maomao"],
        .yoyo: ["killua"], .yoyoDone: ["killua"], .inflate: ["luffy"], .inflateDone: ["luffy"], .eat: ["luffy"],
        .lift: ["zoro"], .liftDone: ["zoro"], .sake: ["zoro"], .grill: ["maomao"], .grillDone: ["maomao"],
    ]
}

enum Language: String, CaseIterable {
    case vi, en, ja

    var title: String {
        switch self {
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    private static let key = "language"

    static var current: Language {
        get { UserDefaults.standard.string(forKey: key).flatMap(Language.init) ?? .vi }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Everything one character says in one language.
struct Lines {
    let shortName: String
    let lines: [Line: [String]]
    /// Special greetings for a specific friend, keyed by their id.
    var pairGreet: [String: [String]] = [:]
}

let dialogue: [Language: [String: Lines]] = [
    .vi: vietnameseLines,
    .en: englishLines,
    .ja: japaneseLines,
]

/// Names of the skills drawn in the skills sheet (the others are in the per-language skill name tables).
let drawnSkillNames: [Language: [Skill: String]] = [
    .vi: [.yoyo: "Chơi yoyo điện", .balloon: "Phình bụng bay lên", .eat: "Ăn thịt", .lift: "Tập tạ", .sake: "Uống sake", .grill: "Nướng nấm"],
    .en: [.yoyo: "Electric yo-yo", .balloon: "Balloon belly", .eat: "Eat meat", .lift: "Lift weights", .sake: "Sake break", .grill: "Grill mushrooms"],
    .ja: [.yoyo: "電気ヨーヨー", .balloon: "お腹風船", .eat: "肉を食べる", .lift: "筋トレ", .sake: "一杯やる", .grill: "キノコ焼き"],
]

let skillNames: [Language: [Skill: String]] = [
    .vi: vietnameseSkillNames,
    .en: englishSkillNames,
    .ja: japaneseSkillNames,
]

extension Character {
    func displayName(in language: Language) -> String {
        fixedName ?? dialogue[language]?[id]?.shortName ?? name
    }

    /// A random line of `kind` in the current language; "%@" becomes the partner's name in that language.
    func line(_ kind: Line, to partner: Character? = nil, project: String = "", app: String = "") -> String? {
        let language = Language.current
        guard let own = dialogue[language]?[dialogueID ?? id] else { return nil }
        var options = own.lines[kind] ?? []
        if kind == .greet, let partner, let special = own.pairGreet[partner.id] { options = special }
        guard let text = options.randomElement() else { return nil }
        return text.replacingOccurrences(of: "%@", with: partner?.displayName(in: language) ?? "")
            .replacingOccurrences(of: "{project}", with: project.isEmpty ? "project" : project)
            .replacingOccurrences(of: "{app}", with: app)
    }
}
