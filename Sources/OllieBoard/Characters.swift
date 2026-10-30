import Foundation

enum Behavior: CaseIterable {
    case wander, kick, arrange, bored, sleep, grumpy, happy, social, skill
}

/// Special moves from each character's story, used now and then or picked from the right-click menu.
enum Skill: String {
    case mindRead, readFriend       // Anya
    case bloodBurst, resize         // Nezuko
    case flowerField, mimic         // Frieren
    case guitarSolo, melt           // Bocchi
    case morningStar, oniForm       // Rem
    case poisonTest, herbalBrew     // Maomao
    case wall, tariff               // Trump
    case judo, bearRide             // Putin
    case parade, aiRobot            // Xi
    case applause, missile          // Kim
    case waterBreathing, hinokami   // Tanjiro
    case thunderclap, clingCry      // Zenitsu
    case gomuPistol, gear5          // Luffy
    case threeSword, getLost        // Zoro
    case climaTact, berries         // Nami
    case titanShift, tatakae        // Eren
    case odmGear, scarf             // Mikasa
    case spinSlash, cleaning        // Levi
    case divergentFist, sukuna      // Yuji
    case infiniteVoid, hollowPurple // Gojo
    case divineDogs, rabbitEscape   // Megumi
    case jajanken, fishing          // Gon
    case godspeed, chocolate        // Killua
    case chainJail, scarletEyes     // Kurapika
    case knightOath, shieldBash     // Cat Knight
    case guguChant, bellySlide      // Gugugaga
    // Skills drawn together with their prop in the character's own skills sheet (see SpriteSheet).
    case yoyo                       // Killua
    case balloon, eat               // Luffy
    case lift, sake                 // Zoro
    case grill                      // Maomao

    var title: String { (skillNames[Language.current]?[self] ?? drawnSkillNames[Language.current]?[self]) ?? rawValue }
}

/// Groups the characters in the menu. The five supported series and politics also have a play-room scene.
enum Series: String, CaseIterable {
    case kimetsu = "Kimetsu no Yaiba"
    case onePiece = "One Piece"
    case attackOnTitan = "Attack on Titan"
    case jujutsuKaisen = "Jujutsu Kaisen"
    case hunterXHunter = "Hunter x Hunter"
    case spyFamily = "Spy x Family"
    case frieren = "Sousou no Frieren"
    case bocchi = "Bocchi the Rock!"
    case reZero = "Re:Zero"
    case apothecary = "Kusuriya no Hitorigoto"
    case catKnight = "Cat Knight"
    case endfield = "Arknights: Endfield"
    case politics = "Chính trị"

    /// Series names stay as they are; only "politics" is translated.
    var title: String { self == .politics ? ui(.politics) : rawValue }
}

/// Personality only; what each character says lives in the Dialogue+<Language> files.
struct Character {
    let id: String
    let name: String
    /// Nil for agent mascots.
    let series: Series?
    let walkSpeed: Double
    let weights: [Behavior: Double]
    /// Animation used when the character is upset (Bocchi sulks instead of stomping).
    let grumpyAnim: Anim
    /// Runs away from the mouse cursor.
    let shy: Bool
    /// Likes waking up sleeping friends.
    let prankster: Bool
    /// Agent mascots: a shared dialogue table and a fixed display name.
    var dialogueID: String? = nil
    var fixedName: String? = nil
    var skills: [Skill] = []
}

extension AgentKind {
    /// The mascot for one running session of this agent (its sprite sheet is named after the agent).
    func character(pid: Int32) -> Character {
        Character(id: "agent-\(pid)", name: title, series: nil, walkSpeed: 95,
                  weights: [.wander: 3, .kick: 1, .arrange: 0.5, .bored: 1, .sleep: 0.5, .grumpy: 0.3, .happy: 1.5, .social: 1.5],
                  grumpyAnim: .grumpy, shy: false, prankster: false,
                  dialogueID: "agent", fixedName: title)
    }
}

let allCharacters: [Character] = [
    Character(
        id: "anya", name: "Anya Forger", series: .spyFamily, walkSpeed: 95,
        weights: [.wander: 3, .kick: 3, .arrange: 1, .bored: 1.5, .sleep: 1, .grumpy: 1, .happy: 2, .social: 2.5, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: true, skills: [.mindRead, .readFriend]),
    Character(
        id: "nezuko", name: "Nezuko Kamado", series: .kimetsu, walkSpeed: 100,
        weights: [.wander: 3, .kick: 2, .arrange: 1, .bored: 1, .sleep: 2.5, .grumpy: 0.5, .happy: 2, .social: 2, .skill: 1],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.bloodBurst, .resize]),
    Character(
        id: "frieren", name: "Frieren", series: .frieren, walkSpeed: 70,
        weights: [.wander: 2, .kick: 1, .arrange: 0.7, .bored: 3, .sleep: 3, .grumpy: 0.5, .happy: 0.5, .social: 0.8, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.flowerField, .mimic]),
    Character(
        id: "bocchi", name: "Hitori Gotoh", series: .bocchi, walkSpeed: 85,
        weights: [.wander: 2, .kick: 0.7, .arrange: 1, .bored: 2, .sleep: 1, .grumpy: 1, .happy: 0.7, .social: 0.3, .skill: 1],
        grumpyAnim: .sad, shy: true, prankster: false, skills: [.guitarSolo, .melt]),
    Character(
        id: "rem", name: "Rem", series: .reZero, walkSpeed: 105,
        weights: [.wander: 2, .kick: 1, .arrange: 4, .bored: 1, .sleep: 0.5, .grumpy: 1, .happy: 1.5, .social: 1.5, .skill: 1],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.morningStar, .oniForm]),
    Character(
        id: "maomao", name: "Maomao", series: .apothecary, walkSpeed: 88,
        weights: [.wander: 2.6, .kick: 0.3, .arrange: 3.5, .bored: 1, .sleep: 0.8, .grumpy: 1.1, .happy: 0.7, .social: 0.8, .skill: 4.6],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.poisonTest, .herbalBrew, .grill]),

    // Three characters per supported series for now.
    // TODO: Kimetsu no Yaiba — Hashibira Inosuke, Kibutsuji Muzan.
    // TODO: One Piece — Sanji, Brook.
    // TODO: Attack on Titan — Armin Arlert, Hange Zoë.
    // TODO: Jujutsu Kaisen — Nobara Kugisaki, Ryomen Sukuna.
    // TODO: Hunter x Hunter — Leorio, Hisoka.
    Character(
        id: "tanjiro", name: "Tanjiro Kamado", series: .kimetsu, walkSpeed: 100,
        weights: [.wander: 3, .kick: 1.5, .arrange: 3, .bored: 1, .sleep: 1, .grumpy: 0.5, .happy: 2, .social: 3, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.waterBreathing, .hinokami]),
    Character(
        id: "zenitsu", name: "Agatsuma Zenitsu", series: .kimetsu, walkSpeed: 110,
        weights: [.wander: 2, .kick: 1, .arrange: 0.7, .bored: 1.5, .sleep: 3, .grumpy: 0.5, .happy: 1.5, .social: 2, .skill: 1.2],
        grumpyAnim: .sad, shy: true, prankster: false, skills: [.thunderclap, .clingCry]),
    Character(
        id: "luffy", name: "Monkey D. Luffy", series: .onePiece, walkSpeed: 115,
        weights: [.wander: 3, .kick: 3.5, .arrange: 0.3, .bored: 1, .sleep: 1.5, .grumpy: 0.5, .happy: 3, .social: 3, .skill: 4.2],
        grumpyAnim: .grumpy, shy: false, prankster: true, skills: [.gomuPistol, .gear5, .balloon, .eat]),
    Character(
        id: "zoro", name: "Roronoa Zoro", series: .onePiece, walkSpeed: 90,
        weights: [.wander: 2.5, .kick: 2, .arrange: 0.5, .bored: 1, .sleep: 4, .grumpy: 1, .happy: 0.5, .social: 0.8, .skill: 4.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.threeSword, .getLost, .lift, .sake]),
    Character(
        id: "nami", name: "Nami", series: .onePiece, walkSpeed: 100,
        weights: [.wander: 2.5, .kick: 1.5, .arrange: 2.5, .bored: 1, .sleep: 1, .grumpy: 1.5, .happy: 2, .social: 2, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.climaTact, .berries]),
    Character(
        id: "eren", name: "Eren Yeager", series: .attackOnTitan, walkSpeed: 110,
        weights: [.wander: 3, .kick: 3, .arrange: 0.7, .bored: 1, .sleep: 0.7, .grumpy: 2, .happy: 1, .social: 1.5, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.titanShift, .tatakae]),
    Character(
        id: "mikasa", name: "Mikasa Ackerman", series: .attackOnTitan, walkSpeed: 105,
        weights: [.wander: 3, .kick: 2, .arrange: 2, .bored: 1, .sleep: 0.8, .grumpy: 0.5, .happy: 1, .social: 2, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.odmGear, .scarf]),
    Character(
        id: "levi", name: "Levi Ackerman", series: .attackOnTitan, walkSpeed: 105,
        weights: [.wander: 1.5, .kick: 1, .arrange: 5, .bored: 1, .sleep: 0.5, .grumpy: 1.5, .happy: 0.3, .social: 0.7, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.spinSlash, .cleaning]),
    Character(
        id: "yuji", name: "Yuji Itadori", series: .jujutsuKaisen, walkSpeed: 110,
        weights: [.wander: 3, .kick: 3, .arrange: 1, .bored: 1, .sleep: 1, .grumpy: 0.5, .happy: 2.5, .social: 3, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.divergentFist, .sukuna]),
    Character(
        id: "gojo", name: "Satoru Gojo", series: .jujutsuKaisen, walkSpeed: 95,
        weights: [.wander: 2.5, .kick: 2, .arrange: 0.5, .bored: 2, .sleep: 1, .grumpy: 0.3, .happy: 2.5, .social: 2.5, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: true, skills: [.infiniteVoid, .hollowPurple]),
    Character(
        id: "megumi", name: "Megumi Fushiguro", series: .jujutsuKaisen, walkSpeed: 95,
        weights: [.wander: 2.5, .kick: 1, .arrange: 2, .bored: 2, .sleep: 1, .grumpy: 1, .happy: 0.5, .social: 0.8, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.divineDogs, .rabbitEscape]),
    Character(
        id: "gon", name: "Gon Freecss", series: .hunterXHunter, walkSpeed: 115,
        weights: [.wander: 3.5, .kick: 2.5, .arrange: 1, .bored: 0.7, .sleep: 1, .grumpy: 0.5, .happy: 3, .social: 3, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.jajanken, .fishing]),
    Character(
        id: "killua", name: "Killua Zoldyck", series: .hunterXHunter, walkSpeed: 120,
        weights: [.wander: 3, .kick: 2.5, .arrange: 0.7, .bored: 1.5, .sleep: 1, .grumpy: 1, .happy: 1.5, .social: 2, .skill: 4.2],
        grumpyAnim: .grumpy, shy: false, prankster: true, skills: [.godspeed, .chocolate, .yoyo]),
    Character(
        id: "kurapika", name: "Kurapika", series: .hunterXHunter, walkSpeed: 95,
        weights: [.wander: 2, .kick: 1, .arrange: 3, .bored: 1.5, .sleep: 1, .grumpy: 1, .happy: 0.7, .social: 1, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.chainJail, .scarletEyes]),

    // A kitten in armor, made from the reference in new-charactor/.
    Character(
        id: "catknight", name: "Cat Knight", series: .catKnight, walkSpeed: 85,
        weights: [.wander: 3, .kick: 2, .arrange: 1.5, .bored: 1, .sleep: 2, .grumpy: 0.5, .happy: 2.5, .social: 2.5, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.knightOath, .shieldBash]),

    // Penguinistrator: the Endministrator's playful chibi penguin meme form.
    Character(
        id: "gugugaga", name: "Gugugaga", series: .endfield, walkSpeed: 75,
        weights: [.wander: 3, .kick: 0.8, .arrange: 1.8, .bored: 1.5, .sleep: 2.5, .grumpy: 0.4, .happy: 3, .social: 3, .skill: 1.3],
        grumpyAnim: .grumpy, shy: false, prankster: true, skills: [.guguChant, .bellySlide]),

    // Playful political caricatures, same sketch skeleton as the anime cast.
    Character(
        id: "trump", name: "Donald Trump", series: .politics, walkSpeed: 105,
        weights: [.wander: 2.5, .kick: 3, .arrange: 1, .bored: 1, .sleep: 0.8, .grumpy: 1.2, .happy: 2.5, .social: 3, .skill: 1.5],
        grumpyAnim: .grumpy, shy: false, prankster: true, skills: [.wall, .tariff]),
    Character(
        id: "putin", name: "Vladimir Putin", series: .politics, walkSpeed: 100,
        weights: [.wander: 2, .kick: 1.5, .arrange: 3, .bored: 2, .sleep: 1, .grumpy: 1, .happy: 1, .social: 1, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.judo, .bearRide]),
    Character(
        id: "xi", name: "Tập Cận Bình", series: .politics, walkSpeed: 90,
        weights: [.wander: 2, .kick: 1, .arrange: 4, .bored: 1.5, .sleep: 0.8, .grumpy: 0.8, .happy: 1, .social: 1.2, .skill: 1.2],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.parade, .aiRobot]),
    Character(
        id: "kim", name: "Kim Jong Un", series: .politics, walkSpeed: 85,
        weights: [.wander: 2, .kick: 1.5, .arrange: 1.5, .bored: 1, .sleep: 0.7, .grumpy: 1, .happy: 3, .social: 3, .skill: 1.5],
        grumpyAnim: .grumpy, shy: false, prankster: false, skills: [.applause, .missile]),
]
