//
//  Theme.swift
//  Elephant Challenge: Math Memory
//
//  Character catalog: 10 animals, each with a clearly different colour and a
//  matching visual theme for the whole app. Characters are earned by collecting
//  cards; the requirements live in `GameConfig.characterUnlockRequirements`.
//

import SwiftUI

/// The single currency collected throughout the game.
enum Currency {
    static let iconName = "hoop_currency"
}

/// The hoop artwork used anywhere a currency count is shown.
struct CurrencyIcon: View {
    let size: CGFloat

    var body: some View {
        Image(Currency.iconName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AnimalCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    /// Flight portrait: menus, the intro card, the collection, results. It is
    /// the same drawing the playfield rig is cut from, so a character looks in
    /// the menus exactly like the one the player is about to fly.
    let imageName: String
    /// The same portrait at 384 px, for the places that draw it small — the
    /// Premium collection strip and the Settings picker. Both show the whole
    /// cast at once, and a screen that decoded ten full-size portraits to paint
    /// ten 46 pt circles was doing far more work per tile than it needed, all
    /// of it on the frame the sheet opens on.
    let thumbnailName: String
    // Colour components (0–1).
    let primaryRGB: (Double, Double, Double)
    let deepRGB: (Double, Double, Double)
    let skyRGB: (Double, Double, Double)
    let tintRGB: (Double, Double, Double)

    static func == (lhs: AnimalCharacter, rhs: AnimalCharacter) -> Bool {
        lhs.id == rhs.id
    }

    var color: Color { Color(red: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2) }
    var deepColor: Color { Color(red: deepRGB.0, green: deepRGB.1, blue: deepRGB.2) }
    var skyColor: Color { Color(red: skyRGB.0, green: skyRGB.1, blue: skyRGB.2) }
    var tintColor: Color { Color(red: tintRGB.0, green: tintRGB.1, blue: tintRGB.2) }

    var artwork: Image { Image(imageName) }
    /// Use wherever the portrait is drawn at roughly 75 pt or less.
    var thumbnail: Image { Image(thumbnailName) }

    /// How this character's drawing sits inside the shared canvas. The playfield
    /// rig and every portrait read it, so a character is one size everywhere.
    var rig: CharacterRig { CharacterRig.rig(for: id) }

    /// Localized display name, resolved per language from the string catalog
    /// ("character.frog", "character.penguin", …).
    var localizedName: String {
        if id == "flying_penguin" { return L(key: "character.penguin") }
        return L(key: "character.\(id)")
    }
}

/// One character's flight artwork: a body canvas with a separate arm canvas on
/// either side of it. Every layer of a rig — and the portrait cut from the same
/// drawing — shares one 3:2 canvas and one alignment, so the arms only ever need
/// their own shoulder point.
///
/// Assets are named after the character's position in
/// `CharacterUnlocks.orderedCharacterIDs` — `1_body_only`, `2_body_only`, … —
/// so a new character is a folder of four PNGs plus one entry in `all` below.
struct CharacterRig {
    let bodyImage: String
    let frontArmImage: String
    let backArmImage: String
    /// Shoulder of the far arm, in its own canvas' unit space. Sits a little
    /// above the joint's centre so the arm swings from the top of the socket.
    let backShoulder: UnitPoint
    /// Shoulder of the near arm, measured the same way.
    let frontShoulder: UnitPoint
    /// Brings this drawing onto the starter penguin's footprint. Every character
    /// has to read at one size and leave the cannon from one spot, and the
    /// drawings fill their shared canvas very differently: ears, tails, tentacles
    /// and outstretched legs all push a character off centre and make it large.
    let artScale: CGFloat
    /// Shift after scaling, as a fraction of the canvas.
    let artOffset: CGSize

    /// Keyed by character ID. A character with no rig here flies the starter
    /// penguin's artwork, which is what every character did before rigs were
    /// drawn per animal.
    static let all: [String: CharacterRig] = [
        "flying_penguin": rig(1, back: (0.715, 0.600), front: (0.550, 0.550),
                              scale: 1, offset: (0, 0)),
        "bunny": rig(2, back: (0.646, 0.698), front: (0.502, 0.604),
                     scale: 0.820, offset: (0.037, 0.033)),
        "dog": rig(3, back: (0.758, 0.744), front: (0.575, 0.641),
                   scale: 0.760, offset: (0.001, -0.016)),
        "lion": rig(4, back: (0.744, 0.651), front: (0.547, 0.552),
                    scale: 0.765, offset: (0.014, 0.038)),
        "octopus": rig(5, back: (0.764, 0.573), front: (0.575, 0.546),
                       scale: 0.860, offset: (0.054, 0.023)),
        "crab": rig(6, back: (0.681, 0.606), front: (0.489, 0.521),
                    scale: 0.893, offset: (0.007, 0.046)),
        "elephant": rig(7, back: (0.681, 0.627), front: (0.486, 0.528),
                        scale: 0.812, offset: (-0.006, 0.015)),
        "bear": rig(8, back: (0.751, 0.601), front: (0.524, 0.490),
                    scale: 0.848, offset: (-0.005, 0.040)),
        "fox": rig(9, back: (0.703, 0.617), front: (0.520, 0.524),
                   scale: 0.852, offset: (0.016, 0.046)),
        "frog": rig(10, back: (0.745, 0.590), front: (0.546, 0.481),
                    scale: 0.859, offset: (0.027, 0.041))
    ]

    static func rig(for characterID: String) -> CharacterRig {
        all[characterID] ?? all[CharacterUnlocks.starterCharacterID]!
    }

    /// Every rig is the same four assets under one number, so only the measured
    /// numbers are worth spelling out per character.
    private static func rig(_ index: Int,
                            back: (CGFloat, CGFloat),
                            front: (CGFloat, CGFloat),
                            scale: CGFloat,
                            offset: (CGFloat, CGFloat)) -> CharacterRig {
        CharacterRig(bodyImage: "\(index)_body_only",
                     frontArmImage: "\(index)_front_arm",
                     backArmImage: "\(index)_back_arm",
                     backShoulder: UnitPoint(x: back.0, y: back.1),
                     frontShoulder: UnitPoint(x: front.0, y: front.1),
                     artScale: scale,
                     artOffset: CGSize(width: offset.0, height: offset.1))
    }
}

/// A character's flight portrait, drawn at the size and position the starter
/// penguin's is. The drawings share a canvas but not how much of it they fill,
/// so every menu that shows a character goes through here rather than sizing
/// the image itself.
struct CharacterPortrait: View {
    let character: AnimalCharacter
    /// The square the portrait is laid out in. The artwork keeps this footprint
    /// no matter how far it is magnified, so nothing beside it moves.
    let side: CGFloat
    /// Extra magnification, letting a screen send the outstretched arms past a
    /// tile's border or a decorative ring.
    var magnification: CGFloat = 1
    /// Small portraits (roughly 75 pt and under) read the 384 px copy.
    var usesThumbnail: Bool = false

    var body: some View {
        let rig = character.rig
        let scale = rig.artScale * magnification
        // `scaledToFit` inside a square frame leaves a 3:2 drawing two thirds as
        // tall as it is wide; the offset is measured against that drawn box.
        let drawnHeight = side * 2 / 3
        (usesThumbnail ? character.thumbnail : character.artwork)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .scaleEffect(scale)
            .offset(x: side * rig.artOffset.width * scale,
                    y: drawnHeight * rig.artOffset.height * scale)
    }
}

enum CharacterCatalog {
    /// The character available from the very first card.
    static let freeCharacterID = CharacterUnlocks.starterCharacterID

    /// The localized fallback used when the player leaves their name empty.
    /// The current game character is Penguin, so this resolves to Penguin and
    /// automatically follows every language added to the string catalog.
    static var defaultPlayerName: String {
        character(id: "flying_penguin").localizedName
    }

    /// Order must match `CharacterUnlocks.orderedCharacterIDs`. Each palette is
    /// taken from its portrait artwork, and each portrait is numbered by that
    /// same catalog position, so `4_main_character` is the lion everywhere.
    static let all: [AnimalCharacter] = [
        AnimalCharacter(id: "flying_penguin", name: "Penguin", emoji: "🐧",
                        imageName: "1_main_character", thumbnailName: "1_thumb",
                        primaryRGB: (0.13, 0.42, 0.86), deepRGB: (0.04, 0.16, 0.38),
                        skyRGB: (0.86, 0.95, 1.00), tintRGB: (0.68, 0.86, 0.98)),
        AnimalCharacter(id: "bunny", name: "Bunny", emoji: "🐰",
                        imageName: "2_main_character", thumbnailName: "2_thumb",
                        primaryRGB: (0.96, 0.55, 0.64), deepRGB: (0.58, 0.31, 0.37),
                        skyRGB: (0.99, 0.94, 0.96), tintRGB: (0.97, 0.86, 0.89)),
        AnimalCharacter(id: "dog", name: "Dog", emoji: "🐶",
                        imageName: "3_main_character", thumbnailName: "3_thumb",
                        primaryRGB: (0.13, 0.70, 0.71), deepRGB: (0.05, 0.42, 0.43),
                        skyRGB: (0.90, 0.99, 0.99), tintRGB: (0.76, 0.97, 0.97)),
        AnimalCharacter(id: "lion", name: "Lion", emoji: "🦁",
                        imageName: "4_main_character", thumbnailName: "4_thumb",
                        primaryRGB: (0.97, 0.73, 0.10), deepRGB: (0.58, 0.43, 0.02),
                        skyRGB: (0.99, 0.97, 0.89), tintRGB: (0.97, 0.91, 0.74)),
        AnimalCharacter(id: "octopus", name: "Octopus", emoji: "🐙",
                        imageName: "5_main_character", thumbnailName: "5_thumb",
                        primaryRGB: (0.66, 0.38, 0.90), deepRGB: (0.38, 0.20, 0.54),
                        skyRGB: (0.96, 0.93, 0.99), tintRGB: (0.90, 0.82, 0.97)),
        AnimalCharacter(id: "crab", name: "Crab", emoji: "🦀",
                        imageName: "6_main_character", thumbnailName: "6_thumb",
                        primaryRGB: (0.91, 0.24, 0.16), deepRGB: (0.55, 0.11, 0.06),
                        skyRGB: (0.99, 0.91, 0.90), tintRGB: (0.97, 0.78, 0.76)),
        AnimalCharacter(id: "elephant", name: "Elephant", emoji: "🐘",
                        imageName: "7_main_character", thumbnailName: "7_thumb",
                        primaryRGB: (0.44, 0.59, 0.80), deepRGB: (0.25, 0.34, 0.48),
                        skyRGB: (0.94, 0.96, 0.99), tintRGB: (0.86, 0.91, 0.97)),
        AnimalCharacter(id: "bear", name: "Bear", emoji: "🐻",
                        imageName: "8_main_character", thumbnailName: "8_thumb",
                        primaryRGB: (0.65, 0.42, 0.22), deepRGB: (0.39, 0.24, 0.11),
                        skyRGB: (0.99, 0.95, 0.92), tintRGB: (0.97, 0.88, 0.80)),
        AnimalCharacter(id: "fox", name: "Fox", emoji: "🦊",
                        imageName: "9_main_character", thumbnailName: "9_thumb",
                        primaryRGB: (0.97, 0.48, 0.08), deepRGB: (0.58, 0.26, 0.01),
                        skyRGB: (0.99, 0.93, 0.89), tintRGB: (0.97, 0.84, 0.73)),
        AnimalCharacter(id: "frog", name: "Frog", emoji: "🐸",
                        imageName: "10_main_character", thumbnailName: "10_thumb",
                        primaryRGB: (0.29, 0.72, 0.22), deepRGB: (0.15, 0.43, 0.11),
                        skyRGB: (0.92, 0.99, 0.91), tintRGB: (0.82, 0.97, 0.79))
    ]
    .sorted {
        let order = CharacterUnlocks.orderedCharacterIDs
        return (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
    }

    static func character(id: String) -> AnimalCharacter {
        all.first { $0.id == id } ?? all[0]
    }

    /// The first half of the catalog: earned purely by collecting cards.
    static var cardCharacters: [AnimalCharacter] {
        all.filter { !CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The second half: still earnable with cards, but Premium grants them at once.
    static var premiumCharacters: [AnimalCharacter] {
        all.filter { CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The selected character, falling back to the starter when the selected
    /// one is not available (yet).
    static func current(isPremium: Bool) -> AnimalCharacter {
        let selected = character(id: GameSettings.characterID)
        if !CharacterUnlockStore.canUse(characterID: selected.id, isPremium: isPremium) {
            return character(id: freeCharacterID)
        }
        return selected
    }
}

/// Character access, derived from the player's card total so an unlock can
/// never be lost through a missed animation. Only the one-time celebration
/// receipt is stored separately.
enum CharacterUnlockStore {
    static var totalCards: Int {
        get { Progress.store.totalCards }
        set { Progress.store.totalCards = newValue }
    }

    /// Cards required for a character, or nil when it is not card-unlockable.
    static func requirement(for characterID: String) -> Int? {
        CharacterUnlocks.cardsRequired(for: characterID)
    }

    static func canUse(characterID: String, isPremium: Bool) -> Bool {
        CharacterUnlocks.isUnlocked(characterID: characterID,
                                    totalCards: totalCards,
                                    isPremium: isPremium)
    }

    /// The next animal still to be earned, for the home screen and reminders.
    static func nextMilestone() -> (character: AnimalCharacter, remaining: Int)? {
        guard let next = CharacterUnlocks.nextMilestone(totalCards: totalCards) else { return nil }
        return (CharacterCatalog.character(id: next.characterID), next.remaining)
    }

    /// Characters that crossed their requirement but have not been celebrated.
    static func unannouncedUnlocks(at total: Int) -> [AnimalCharacter] {
        let announced = Progress.store.announcedUnlocks
        return CharacterUnlocks.unlockedCharacterIDs(totalCards: total)
            .filter { $0 != CharacterCatalog.freeCharacterID && !announced.contains($0) }
            .map { CharacterCatalog.character(id: $0) }
    }

    static func markAnnounced(_ characterID: String) {
        var announced = Progress.store.announcedUnlocks
        announced.insert(characterID)
        Progress.store.announcedUnlocks = announced
    }
}
