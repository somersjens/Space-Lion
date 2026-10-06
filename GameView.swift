//
//  GameView.swift
//  Math Memory
//
//  The playing surface. A round runs on the reef: the sum stands on a piece of
//  coral on the sea floor, the coral lets answer bubbles up through the water,
//  and the player steers a fish into the bubble carrying the right answer.
//
//  All rules live in `MemoryGame` and the whole of the reef lives in
//  `ReefGame.swift`; this file only puts the HUD, the reef and the helper
//  together and hands every touched answer straight to the engine, which is the
//  single place that decides whether it counts.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Everything a session needs to start: which level to draw questions from and
/// how many answer cards each round lays out.
struct GameSessionRequest: Identifiable {
    let level: MathLevel
    /// Only meaningful for Supermix levels; every other topic has one operation.
    var mixedVariant: MixedVariant = .all
    /// Which of the three order buttons was chosen. Supermix ignores it.
    var mode: PracticeMode = .mixed
    /// Set by the welcome flow: the level's start card opens with the tutorial
    /// already switched on, so one tap on Start tutorial begins the guided run.
    var startsGuided = false
    var id: String { "\(level.id).\(mixedVariant.rawValue).\(mode.rawValue)" }

    /// The scoreboard this session plays on.
    var board: LevelBoard {
        LevelBoard(level: level, mixedVariant: mixedVariant, mode: mode)
    }
}

struct GameView: View {
    let request: GameSessionRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var language = LanguageManager.shared
    @StateObject private var model: GameViewModel

    /// The window's safe area, sampled once the view is on screen — never from
    /// inside `body`; see `ScreenSafeArea`.
    @State private var screenInsets = ScreenSafeArea()

    /// The level's start card, shown before the first round and dismissed by
    /// the player. The session only begins once it is gone.
    @State private var showsIntro = true
    /// The same card doubles as the in-level pause screen. Keeping this state
    /// separate from `showsIntro` lets a brand-new run still say Start while a
    /// pause made before the first answer already says Continue.
    @State private var showsPauseCard = false
    /// After the card, the fish gets the stage to itself for one short looping
    /// entrance. The first round only opens when that animation is finished.
    @State private var playsFishEntrance = false
    /// A completed board gets one last moment in the reef before its result
    /// card appears. Other endings (no lives, or leaving) remain immediate.
    @State private var playsLevelCompletion = false
    @State private var showsResult = false
    /// The tutorial switch on the start card. It only decides what the start
    /// button says and does; the run itself is driven by the view model.
    @State private var isTutorialArmed = false
    /// Where the lives meter sits, measured in the same space the playing field
    /// draws in, so a caught heart can be flown to the exact heart it fills.
    @State private var livesFrame: CGRect = .zero
    /// Hearts on their way from the flight path to the meter.
    @State private var heartFlights: [HeartFlight] = []
    /// The broken heart that explains a wrong tutorial hoop, travelling from
    /// the lesson icon to the life that just disappeared from the meter.
    @State private var tutorialHeartLossFlights: [HeartFlight] = []
    @State private var tutorialMessageIconFrame: CGRect = .zero
    /// The short pop a heart leaves on the meter as it lands.
    @State private var heartLandings: [HeartLanding] = []
    /// Bumped when a heart lands, which is when the meter says "+1".
    @State private var lifeGainToken = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: GameSessionRequest) {
        self.request = request
        _model = StateObject(wrappedValue: GameViewModel(request: request))
        // The welcome flow hands over with the tutorial already switched on, so
        // its start card opens saying Start tutorial. The card itself stays:
        // it is what tells the player which level they are about to play, and
        // the whole pond — scenery, artwork, the first swarm's food — is built
        // behind it. Opening straight into the level meant paying for all of
        // that on the first frame of the game, in full view.
        _isTutorialArmed = State(initialValue: request.startsGuided)
    }

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        ZStack {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // The level's own wallpaper used to sit here. The pond fills the
            // whole screen opaquely on top of it, so all it ever contributed
            // was a screenful of glyph layers for the compositor to blend away
            // behind the playfield on every single frame.

            // Keep the level visible underneath every card. The result is an
            // overlay over the reef that was just played, exactly like the
            // start and pause cards, rather than a replacement for the game.
            playfield
                .blur(radius: showsResult ? 4 : 0)
                .saturation(showsResult ? 0.84 : 1)
                .animation(.easeInOut(duration: 0.42), value: showsResult)
                .transition(.opacity)

            if showsResult {
                ResultView(result: model.result,
                           board: request.board,
                           character: character,
                           onPlayAgain: {
                               showsResult = false
                               playsLevelCompletion = false
                               playsFishEntrance = true
                               model.restart()
                           },
                           onExit: { dismiss() })
                    // ResultView owns its staged backdrop and card entrance.
                    // A second transition here made the whole overlay—including
                    // its dimming layer—arrive as one abrupt block.
                    .transition(.identity)
                    .zIndex(1)
            }

            if showsIntro {
                LevelIntroCard(board: request.board,
                               theme: character,
                               isPauseCard: showsPauseCard,
                               lastMissedChallenge: model.lastMissedChallenge,
                               isTutorialArmed: $isTutorialArmed,
                               onStart: startSession,
                               onExit: { dismiss() })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        // What the level fills with is what the HUD counts and what the
        // celebrations rain down, all the way through the start card, the
        // playfield and the result card.
        .animation(.easeInOut(duration: 0.28), value: model.isGameOver)
        .animation(.easeInOut(duration: 0.25), value: showsIntro)
        .onAppear {
            screenInsets = ScreenSafeArea.current
            // Let the start card reach the screen first, then use the covered
            // playfield to prepare every sum and the first visible glyphs.
            DispatchQueue.main.async { model.prepare() }
        }
        .onChange(of: model.isGameOver) { _, isOver in
            guard isOver else {
                showsResult = false
                playsLevelCompletion = false
                return
            }
            if model.result.reason == .roundsCompleted {
                playsLevelCompletion = true
            } else {
                showsResult = true
            }
        }
        .onDisappear { model.end() }
    }

    private func startSession() {
        showsIntro = false
        if showsPauseCard, model.state != .intro {
            showsPauseCard = false
            model.resume()
        } else {
            showsPauseCard = false
            if isTutorialArmed {
                model.armTutorial()
                // However this run ends — taught out, finished early, or left
                // at the first sum — the menu owes the player its last step.
                TutorialCenter.shared.guidedRunStarted()
            }
            playsFishEntrance = true
        }
    }

    private func finishFishEntrance() {
        guard playsFishEntrance else { return }
        playsFishEntrance = false
        model.begin()
    }

    // MARK: - Playfield

    private var playfield: some View {
        // The reef is the whole screen — water from the very top edge down to
        // the sea floor at the very bottom — with the HUD laid over it. Reading
        // the insets here is what keeps the fish clear of the HUD and the sum
        // clear of the home indicator.
        // The HUD keeps a floor under it, so it still clears the status bar on
        // the very first frame, before the insets have been sampled.
        let topInset = max(screenInsets.top, isPad ? 24 : 16)

        return GeometryReader { proxy in
            ZStack(alignment: .top) {
                FlyingPenguinPlayfield(rounds: model.visibleRounds,
                              maximumRounds: model.maximumRounds,
                              character: character,
                              isPad: isPad,
                              isLive: model.acceptsInput,
                              isRunning: isReefRunning,
                              playsFishEntrance: playsFishEntrance,
                              preparesLevelCompletion: model.preparesLevelCompletion,
                              playsLevelCompletion: playsLevelCompletion,
                              reduceMotion: reduceMotion,
                              // The HUD's own height, so the swarm's ceiling is
                              // the underside of the HUD and never the status bar
                              // or the Dynamic Island behind it.
                              topReserve: topInset + (isPad ? 76 : 50),
                              bottomReserve: screenInsets.bottom,
                              // What the tutorial is teaching, what it is
                              // saying, and where its answers go back to. All
                              // three are inert in a normal session, and the
                              // playing field costs nothing for them.
                              tutorial: model.tutorial,
                              tutorialMessage: tutorialMessage,
                              onTutorialEvent: handleTutorialEvent(_:),
                              // The one rescue heart of a normal session.
                              isRescueHeartDue: model.isRescueHeartDue,
                              onRescueHeartPlaced: { model.placeRescueHeart() },
                              onLifeHeartCollected: collectLifeHeart(at:),
                              lifeHeartSize: hudHeartSize,
                              onHit: { optionID, usesSpeedBonus, usesHalfLifePenalty in
                                  model.select(optionID: optionID,
                                               usesSpeedBonus: usesSpeedBonus,
                                               wrongAnswerCostHalves: usesHalfLifePenalty ? 1 : nil)
                              },
                              onSwallow: { model.reportCatchOutcome(isCorrect: $0) },
                              onDive: { model.reportDiveOutcome() },
                              onFishEntranceComplete: finishFishEntrance,
                              onLevelCompletionFinished: finishLevelCompletion)
                    // The playing field is a simulation, not a page: every fly
                    // sits where the physics put it, and the tongue leaves from
                    // a mouth painted into the artwork at a fixed spot. Mirror
                    // it for a right-to-left language and the two stop agreeing
                    // — the flies flip but the tongue still reaches for where
                    // they were. It reads the same either way, so it is pinned.
                    .environment(\.layoutDirection, .leftToRight)

                hud
                    .padding(.horizontal, isPad ? 28 : 16)
                    .padding(.top, hudTop(below: topInset))
                    .opacity(showsGameplayHUD ? 1 : 0)
                    .scaleEffect(showsGameplayHUD ? 1 : 0.92, anchor: .topLeading)
                    .offset(x: showsGameplayHUD ? 0 : -12)
                    .animation(.spring(response: 0.34, dampingFraction: 0.82),
                               value: showsGameplayHUD)
                    .allowsHitTesting(showsGameplayHUD)

                if model.comboAnnouncementID > 0 {
                    ComboHoopBanner(token: model.comboAnnouncementID,
                                   character: character,
                                   isPad: isPad)
                        .padding(.top, topInset + (isPad ? 142 : 88))
                        .allowsHitTesting(false)
                }

                // Drawn over the HUD, because the whole point of the flight is
                // that it ends on the meter.
                ForEach(heartFlights) { flight in
                    HeartFlightView(flight: flight,
                                    tint: character.deepColor,
                                    size: hudHeartSize)
                }
                .allowsHitTesting(false)

                ForEach(tutorialHeartLossFlights) { flight in
                    TutorialHeartLossFlightView(flight: flight,
                                                tint: character.color,
                                                size: hudHeartSize)
                }
                .allowsHitTesting(false)

                ForEach(heartLandings) { landing in
                    HeartLandingPop(point: landing.point,
                                    tint: character.deepColor,
                                    size: hudHeartSize)
                }
                .allowsHitTesting(false)
            }
            .coordinateSpace(name: TutorialMessageCoordinateSpace.game)
            .onPreferenceChange(LivesFrameKey.self) { livesFrame = $0 }
            .onPreferenceChange(TutorialMessageIconFrameKey.self) {
                tutorialMessageIconFrame = $0
            }
        }
        .ignoresSafeArea()
    }

    /// A wrong passage in the life lesson gets one extra visual response before
    /// the director schedules its hand-over to the farewell.
    private func handleTutorialEvent(_ event: TutorialEvent) {
        if event == .passedWrongHoop, model.tutorial.step == .wrongHoop {
            flyTutorialHeartLossToHUD()
        }
        model.reportTutorial(event)
    }

    /// The life has already been charged by the engine when the passage is
    /// reported. Its new value therefore identifies the exact slot that was
    /// just emptied. Only after the broken heart reaches that slot is the life
    /// restored, making the subtraction and the return two readable events.
    private func flyTutorialHeartLossToHUD() {
        let duration = reduceMotion ? 0.28 : 0.72
        guard tutorialMessageIconFrame != .zero, livesFrame != .zero else {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                restoreTutorialLife(at: nil)
            }
            return
        }
        let target = livesTarget(filling: model.livesRemaining)
        let flight = HeartFlight(
            source: CGPoint(x: tutorialMessageIconFrame.midX,
                            y: tutorialMessageIconFrame.midY),
            target: target,
            arc: isPad ? 96 : 68,
            duration: duration
        )
        tutorialHeartLossFlights.append(flight)
        DispatchQueue.main.asyncAfter(deadline: .now() + flight.duration) {
            tutorialHeartLossFlights.removeAll { $0.id == flight.id }
            restoreTutorialLife(at: target)
        }
    }

    private func restoreTutorialLife(at point: CGPoint?) {
        AppAudio.shared.playLifePickup()
        landLifeHeart(at: point)
    }

    /// A heart was flown into. The heart itself travels first, unchanged in
    /// size and shape, to the exact slot on the meter it is going to fill — and
    /// only when it lands does the life count up. Carrying it there and then
    /// adding it is what makes the meter's answer legible; adding it at the
    /// pick-up and flying a ghost after it says nothing.
    private func collectLifeHeart(at point: CGPoint) {
        guard model.canTakeLifeHeart else { return }
        AppAudio.shared.playLifePickup()
        let target = livesTarget(filling: model.livesRemaining)
        guard livesFrame != .zero else {
            landLifeHeart(at: nil)
            return
        }
        let flight = HeartFlight(source: point,
                                 target: target,
                                 arc: isPad ? 90 : 64,
                                 duration: reduceMotion ? 0.28 : 0.62)
        heartFlights.append(flight)
        DispatchQueue.main.asyncAfter(deadline: .now() + flight.duration) {
            heartFlights.removeAll { $0.id == flight.id }
            landLifeHeart(at: target)
        }
    }

    /// The heart has arrived: the life goes on the meter, the meter pops, and
    /// the "+1" says what just happened.
    private func landLifeHeart(at point: CGPoint?) {
        guard model.collectLifeHeart() else { return }
        lifeGainToken &+= 1
        guard let point else { return }
        let pop = HeartLanding(point: point)
        heartLandings.append(pop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            heartLandings.removeAll { $0.id == pop.id }
        }
    }

    /// The centre of the heart that is about to fill. The meter draws its
    /// hearts as equal slices of one column, so the slot is worked out from the
    /// lives the player had before the pick-up rather than measured separately.
    private func livesTarget(filling livesBefore: Double) -> CGPoint {
        let capacity = max(1, Int(GameConfig.startingLives.rounded(.up)))
        let index = min(capacity - 1, max(0, Int(livesBefore.rounded(.down))))
        let slot = livesFrame.height / CGFloat(capacity)
        return CGPoint(x: livesFrame.midX,
                       y: livesFrame.minY + slot * (CGFloat(index) + 0.5))
    }

    /// The line the guided run is on, resolved in the language being read.
    private var tutorialMessage: String? {
        model.tutorial.step.map { L(key: $0.messageKey) }
    }

    private func finishLevelCompletion() {
        guard playsLevelCompletion else { return }
        showsResult = true
        // Keep the final bubble bloom under the card during its entrance so
        // there is never a flash of the bare playfield between both scenes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            playsLevelCompletion = false
        }
    }

    // MARK: - HUD

    /// Two balanced columns: pause and score on the left, three hearts on the
    /// right. Both columns have exactly the same total height.
    private var hud: some View {
        HStack(spacing: 0) {
            primaryHudGroup
            Spacer(minLength: 0)
        }
    }

    private func hudTop(below topInset: CGFloat) -> CGFloat {
        topInset + (isPad ? 12 : 6)
    }

    @ViewBuilder
    private var primaryHudGroup: some View {
        HStack(spacing: hudStackSpacing) {
            VStack(spacing: hudStackSpacing) {
                pauseButton
                progressCounter
            }
            LivesView(lives: model.livesRemaining,
                      character: character,
                      isPad: isPad,
                      glyphSize: hudHeartSize,
                      rowHeight: hudControlSize,
                      columnHeight: hudControlSize * 2 + hudStackSpacing)
                // Where the meter is, in the playing field's own coordinates.
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: LivesFrameKey.self,
                            value: proxy.frame(in: .named(TutorialMessageCoordinateSpace.game))
                        )
                    }
                }
                // A caught heart gives a life back. Saying so at the meter, as
                // the heart lands on it, is what makes three hearts again make
                // sense to a child who just watched one go.
                .overlay(alignment: .trailing) {
                    if lifeGainToken > 0 {
                        LifeGainBadge(token: lifeGainToken,
                                      character: character,
                                      isPad: isPad)
                            .fixedSize()
                            .offset(x: isPad ? 88 : 58)
                    }
                }
        }
    }

    /// Pausing freezes the reef in place and puts the level card over it. The
    /// player can continue immediately or leave for the main menu from there.
    private var pauseButton: some View {
        Button {
            AppAudio.shared.playMenuTap()
            model.pause()
            showsPauseCard = true
            showsIntro = true
        } label: {
            Circle()
                .fill(character.deepColor)
                .frame(width: hudControlSize, height: hudControlSize)
                .overlay {
                    Image(systemName: "pause.fill")
                        .font(.system(size: pauseGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().stroke(.white.opacity(0.92), lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pause")
    }

    /// Every status capsule shares one comfortable touch height, while the
    /// symbols retain enough breathing room to stay legible over the pond.
    private var hudControlSize: CGFloat { isPad ? 58 : 40 }
    private var hudStackSpacing: CGFloat { isPad ? 8 : 5 }
    private var hudHeartSize: CGFloat { isPad ? 34 : 22 }
    private var pauseGlyphSize: CGFloat { isPad ? 27 : 18 }
    private var hudNumberSize: CGFloat { isPad ? 29 : 19 }

    /// Just the bubbles banked this session. What the board holds is quoted on
    /// the start card and again on the result card, so the playing field does
    /// not have to carry it too.
    private var progressCounter: some View {
        ZStack {
            Circle()
                .fill(character.deepColor)
                .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: 3))
            Text(verbatim: "\(model.cards)")
                .font(.system(size: hudNumberSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .contentTransition(.numericText(value: Double(model.cards)))
                // Keep multi-digit scores optically inside the same circle on
                // both phone and iPad instead of letting their glyphs press
                // against the ring.
                .frame(width: hudControlSize * 0.72,
                       height: hudControlSize * 0.72)
                .foregroundStyle(.white)
        }
        .frame(width: hudControlSize, height: hudControlSize)
        .foregroundStyle(character.deepColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.cards)
        .accessibilityIdentifier("progress")
        // Named after what this character actually collects, in the app's
        // language — the counter has not been flies-for-everyone since each
        // animal got its own food.
    }

    private var showsGameplayHUD: Bool {
        !showsIntro && !playsFishEntrance && !playsLevelCompletion
    }

    /// The reef only ticks while the level is actually being played: never
    /// behind the start card or the result card, and never while the app is in
    /// the background.
    private var isReefRunning: Bool {
        !showsIntro && (!model.isGameOver || playsLevelCompletion) && scenePhase == .active
    }
}

// MARK: - Life hearts

/// One heart, drawn exactly as the lives meter draws a full one: a soft white
/// outline behind the character's own deep colour. Everything that stands for a
/// life uses this — the meter, the hearts floating in the flight path, and the
/// copy that flies between them — so a heart is recognisable wherever it is.
struct LifeHeartGlyph: View {
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.white.opacity(0.85))
                .scaleEffect(1.22)
            Image(systemName: "heart.fill")
                .foregroundStyle(tint)
        }
        .font(.system(size: size, weight: .bold))
        .frame(width: size, height: size)
    }
}

/// Where the lives meter is, published up to the screen so a caught heart knows
/// where to fly. The larger frame wins, which simply means the real one: an
/// empty default can never displace a measured rect.
private struct LivesFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// One heart landing on the meter, kept only for the length of its pop.
private struct HeartLanding: Identifiable {
    let id = UUID()
    let point: CGPoint
}

/// The beat that says the life was counted: the heart that just arrived swells
/// once and clears, leaving the meter's own heart lit behind it.
private struct HeartLandingPop: View {
    let point: CGPoint
    let tint: Color
    let size: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        LifeHeartGlyph(size: size, tint: tint)
            .scaleEffect(1 + progress * 0.85)
            .opacity(Double(1 - progress))
            .position(point)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
            }
    }
}

/// A heart travelling from the flight path to the meter.
private struct HeartFlight: Identifiable {
    let id = UUID()
    let source: CGPoint
    let target: CGPoint
    /// How high the arc lifts at its midpoint.
    let arc: CGFloat
    let duration: Double
}

/// Carries the caught heart up to the slot it fills. Same heart, same size,
/// same colour as the one already on the meter and the one it was picked up
/// from — it neither grows, shrinks nor fades on the way, so what arrives is
/// plainly the heart that left.
private struct HeartFlightView: View {
    let flight: HeartFlight
    let tint: Color
    let size: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        LifeHeartGlyph(size: size, tint: tint)
            .position(point(at: progress))
            .onAppear {
                withAnimation(.easeInOut(duration: flight.duration)) { progress = 1 }
            }
    }

    private func point(at t: CGFloat) -> CGPoint {
        CGPoint(x: flight.source.x + (flight.target.x - flight.source.x) * t,
                y: flight.source.y + (flight.target.y - flight.source.y) * t
                    - sin(t * .pi) * flight.arc)
    }
}

/// The loss lesson uses the same broken-heart glyph as its message and hoop
/// markers. It travels to the newly empty HUD slot; the model restores that
/// life only when this flight has finished.
private struct TutorialHeartLossFlightView: View {
    let flight: HeartFlight
    let tint: Color
    let size: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Image(systemName: "heart.slash.fill")
                .foregroundStyle(.white.opacity(0.90))
                .scaleEffect(1.22)
            Image(systemName: "heart.slash.fill")
                .foregroundStyle(tint)
        }
        .font(.system(size: size, weight: .black))
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .position(point(at: progress))
        .onAppear {
            withAnimation(.easeInOut(duration: flight.duration)) { progress = 1 }
        }
    }

    private func point(at t: CGFloat) -> CGPoint {
        CGPoint(x: flight.source.x + (flight.target.x - flight.source.x) * t,
                y: flight.source.y + (flight.target.y - flight.source.y) * t
                    - sin(t * .pi) * flight.arc)
    }
}

/// "+1" and a heart, once, beside the lives meter. It confirms that a normal
/// rescue heart from the flight path has restored one life.
private struct LifeGainBadge: View {
    let token: Int
    let character: AnimalCharacter
    let isPad: Bool
    @State private var visible = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
            Text(verbatim: "+1")
        }
        .font(.system(size: isPad ? 19 : 15, weight: .black, design: .rounded))
        .foregroundStyle(character.deepColor)
        .padding(.horizontal, isPad ? 10 : 8)
        .padding(.vertical, isPad ? 6 : 4)
        .background(.white.opacity(0.95), in: Capsule())
        .overlay(Capsule().stroke(character.color.opacity(0.55), lineWidth: 2))
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .scaleEffect(visible ? 1 : 0.6)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? -10 : 6)
        .onAppear { animate() }
        .onChange(of: token) { _, _ in animate() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func animate() {
        visible = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
        }
    }
}

private struct ComboHoopBanner: View {
    let token: Int
    let character: AnimalCharacter
    let isPad: Bool
    @State private var visible = false

    var body: some View {
        Text("game.combo \(GameConfig.hoopComboBonus)")
            .font(.system(size: isPad ? 22 : 17, weight: .black, design: .rounded))
            .foregroundStyle(character.deepColor)
            .padding(.horizontal, isPad ? 18 : 14)
            .padding(.vertical, isPad ? 9 : 7)
            .background(.white.opacity(0.92), in: Capsule())
            .scaleEffect(visible ? 1 : 0.65)
            .opacity(visible ? 1 : 0)
            .onAppear { animate() }
            .onChange(of: token) { _, _ in animate() }
    }

    private func animate() {
        visible = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.2)) { visible = false }
        }
    }
}

// MARK: - Level wallpaper

/// The level's own quiet wallpaper: a staggered grid of the level's number and
/// sign ("3×", "−4", "25%") or a stacked fraction, in a faint wash of the
/// theme colour. Carried over from the original game.
struct LevelWallpaper: View {
    let level: MathLevel
    let tint: Color

    /// The glyph that fills the wallpaper, built from the level's own card
    /// number so it reads like the level itself. Fractions draw a stacked
    /// fraction instead and return nil here.
    private var glyph: String? {
        let n = level.cardNumber
        switch level.topic {
        case .addition:    return "\(n)+"
        case .subtraction: return "−\(n)"
        case .tables:      return "\(n)×"
        case .percentages: return "\(n)%"
        case .mixed:       return "\(n)★"
        case .fractions:   return nil
        }
    }

    private var isPad: Bool { AppLayout.isPad }
    private var fontSize: CGFloat { isPad ? 30 : 22 }
    private var spacingX: CGFloat { isPad ? 118 : 86 }
    private var spacingY: CGFloat { isPad ? 104 : 76 }

    var body: some View {
        GeometryReader { proxy in
            let columns = Int(ceil(proxy.size.width / spacingX)) + 1
            let rows = Int(ceil(proxy.size.height / spacingY)) + 1

            ZStack {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        tile
                            .position(
                                // Every other row is offset by half a step, so
                                // the pattern staggers instead of gridding.
                                x: CGFloat(column) * spacingX
                                    + (row.isMultiple(of: 2) ? 0 : spacingX / 2),
                                y: CGFloat(row) * spacingY
                            )
                    }
                }
            }
        }
        .foregroundStyle(tint.opacity(0.10))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tile: some View {
        if let glyph {
            Text(verbatim: glyph)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
        } else {
            // The fraction levels have one denominator each, so the wallpaper
            // mirrors it: 1/3 on the thirds level, and so on.
            VStack(spacing: 1) {
                Text(verbatim: "1")
                Rectangle().frame(height: 2)
                Text(verbatim: level.cardNumber)
            }
            .font(.system(size: fontSize * 0.62, weight: .heavy, design: .rounded))
            .fixedSize()
        }
    }
}

// MARK: - Lives

struct LivesView: View {
    let lives: Double
    let character: AnimalCharacter
    let isPad: Bool
    /// Matches the bubble in the centre of the HUD.
    var glyphSize: CGFloat = 16
    /// Keeps every HUD group centred on the pause button's horizontal axis.
    var rowHeight: CGFloat = 34
    /// Fixed total height shared with the pause-and-score column.
    var columnHeight: CGFloat? = nil

    private var wholeHearts: Int { Int(lives.rounded(.down)) }
    private var hasHalf: Bool { lives - Double(wholeHearts) >= 0.5 }
    private var capacity: Int { Int(GameConfig.startingLives.rounded(.up)) }

    /// Hearts wear the character's own deep colour — the same one the counter
    /// and the close button use — rather than a generic red.
    private var heartColor: Color { character.deepColor }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<capacity, id: \.self) { index in
                heart(at: index)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: rowHeight, height: columnHeight, alignment: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: lives)
        .accessibilityElement()
        .accessibilityIdentifier("lives")
    }

    /// A full, half or empty heart. The half heart is the full glyph masked to
    /// its leading half over the empty one, so the two always align exactly.
    private func heart(at index: Int) -> some View {
        let size = glyphSize
        return ZStack {
            // A soft white outline behind every heart, full or empty, so the
            // row stays legible over any part of the pond.
            Image(systemName: "heart.fill")
                .foregroundStyle(.white.opacity(0.85))
                .scaleEffect(1.22)

            Image(systemName: "heart.fill")
                .foregroundStyle(heartColor.opacity(0.22))
            if index < wholeHearts {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
            } else if index == wholeHearts && hasHalf {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size / 2)
                    }
            }
        }
        .font(.system(size: size, weight: .bold))
        .frame(width: size, height: size)
    }
}
