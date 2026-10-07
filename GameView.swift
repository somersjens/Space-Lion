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
            model.setSceneActive(scenePhase == .active)
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
            } else if model.result.reason == .timeExpired {
                // Leave the zero on the cockpit for one last beat. Without
                // this, the result card covers the clock in the same update
                // that expires it and the ending feels unexplained.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
                    guard model.isGameOver,
                          model.result.reason == .timeExpired else { return }
                    showsResult = true
                }
            } else {
                showsResult = true
            }
        }
        .onDisappear { model.end() }
        .onChange(of: scenePhase) { _, phase in
            model.setSceneActive(phase == .active)
        }
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
            let topReserve = topInset + (isPad ? 112 : 78)
            let cockpitMetrics = SpaceLionPlayfield.Metrics(
                size: proxy.size,
                topReserve: topReserve,
                bottomReserve: screenInsets.bottom,
                leftReserve: screenInsets.left,
                rightReserve: screenInsets.right,
                isPad: isPad
            )
            let hudInsets = cockpitMetrics.hudInsets(pauseWidth: hudControlSize)
            ZStack(alignment: .top) {
                SpaceLionPlayfield(rounds: model.visibleRounds,
                              character: character,
                              isPad: isPad,
                              isLive: model.acceptsInput,
                              isRunning: isReefRunning,
                              playsFishEntrance: playsFishEntrance,
                              playsLevelCompletion: playsLevelCompletion,
                              destinationStage: model.stageNumber,
                              isTravelling: model.isStageTransitioning,
                              journeyID: model.stageJourneyID,
                              reduceMotion: reduceMotion,
                              // The HUD's own height, so the swarm's ceiling is
                              // the underside of the HUD and never the status bar
                              // or the Dynamic Island behind it.
                              topReserve: topReserve,
                              bottomReserve: screenInsets.bottom,
                              leftReserve: screenInsets.left,
                              rightReserve: screenInsets.right,
                              // What the tutorial is teaching, what it is
                              // saying, and where its answers go back to. All
                              // three are inert in a normal session, and the
                              // playing field costs nothing for them.
                              tutorial: model.tutorial,
                              tutorialMessage: tutorialMessage,
                              onTutorialEvent: handleTutorialEvent(_:),
                              onHit: { optionID, usesSpeedBonus, usesHalfLifePenalty in
                                  model.select(optionID: optionID,
                                               usesSpeedBonus: usesSpeedBonus,
                                               wrongAnswerCostHalves: 0)
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
                    // In landscape the Dynamic Island lives in a horizontal
                    // safe area. The actual paddings come from the same cockpit
                    // geometry as the answer banks: pause is centred over the
                    // left column and the score edge ends over the right one.
                    .padding(.leading, hudInsets.leading)
                    .padding(.trailing, hudInsets.trailing)
                    .padding(.top, hudTop(below: topInset))
                    .opacity(showsGameplayHUD ? 1 : 0)
                    .allowsHitTesting(showsGameplayHUD)

                if model.comboAnnouncementID > 0 {
                    ComboHoopBanner(token: model.comboAnnouncementID,
                                   character: character,
                                   isPad: isPad)
                        .padding(.top, topInset + (isPad ? 142 : 88))
                        .allowsHitTesting(false)
                }

                if !showsIntro,
                   !model.isStageTransitioning,
                   model.timeRemaining <= 3 {
                    StageCountdownPulse(value: model.timeRemaining,
                                        isPad: isPad,
                                        accent: timerLamp,
                                        reduceMotion: reduceMotion)
                        .id(model.timeRemaining)
                        .position(cockpitMetrics.centre)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("stage-countdown")
                }

            }
            .coordinateSpace(name: TutorialMessageCoordinateSpace.game)
        }
        .ignoresSafeArea()
    }

    /// A wrong passage in the life lesson gets one extra visual response before
    /// the director schedules its hand-over to the farewell.
    private func handleTutorialEvent(_ event: TutorialEvent) {
        model.reportTutorial(event)
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

    /// One continuous cockpit rail: pause, the active sum, remaining mission
    /// time and distance against the board target. It fills the usable width
    /// without entering either landscape sensor safe area.
    private var hud: some View {
        HStack(spacing: isPad ? 12 : 7) {
            pauseButton

            cockpitPanel(holographic: true) {
                questionReadout
            }
            .frame(maxWidth: .infinity)

            timerCounter
            scoreCounter
        }
        .frame(maxWidth: .infinity)
    }

    private func hudTop(below topInset: CGFloat) -> CGFloat {
        topInset + (isPad ? 10 : 5)
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
            cockpitPanel {
                Image(systemName: "pause.fill")
                    .font(.system(size: pauseGlyphSize, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("Pause"))
            }
            .frame(width: hudControlSize)
            .contentShape(RoundedRectangle(cornerRadius: isPad ? 18 : 13,
                                           style: .continuous))
        }
        .buttonStyle(CockpitPressStyle())
        .hoverEffect(.lift)
        .accessibilityIdentifier("pause")
    }

    private var hudControlSize: CGFloat { isPad ? 72 : 54 }
    private var pauseGlyphSize: CGFloat { isPad ? 28 : 20 }
    private var hudNumberSize: CGFloat { isPad ? 28 : 20 }

    /// 0 while plenty of time remains, 1 when the clock is about to run out.
    /// The lamp shifts through that range instead of flipping colour at a cliff.
    private var timerUrgency: Double {
        let total = max(1, model.currentStageDuration)
        let fraction = Double(model.timeRemaining) / Double(total)
        return min(1, max(0, (0.30 - fraction) / 0.30))
    }

    private var timerLamp: Color {
        let urgency = timerUrgency
        return Color(red: 0.00 + urgency * 1.00,
                     green: 0.78 - urgency * 0.28,
                     blue: 1.00 - urgency * 0.90)
    }

    private var timerCounter: some View {
        let minutes = model.timeRemaining / 60
        let seconds = model.timeRemaining % 60
        let total = max(1, model.currentStageDuration)
        let progress = CGFloat(min(1, max(0, Double(model.timeRemaining) / Double(total))))
        let lamp = timerLamp
        return cockpitPanel {
            HStack(spacing: isPad ? 8 : 5) {
                // This is a decorative sweep around a once-per-second value;
                // it does not need a separate 30 fps display link.
                TimelineView(.animation(minimumInterval: 1.0 / 8.0,
                                        paused: !isReefRunning || reduceMotion)) { timeline in
                    let spin = timeline.date.timeIntervalSinceReferenceDate * 70
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.14), lineWidth: isPad ? 4 : 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(lamp,
                                    style: StrokeStyle(lineWidth: isPad ? 4 : 3,
                                                       lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: lamp.opacity(0.85), radius: isPad ? 5 : 3)
                        Circle()
                            .trim(from: 0, to: 0.18)
                            .stroke(.white.opacity(0.95),
                                    style: StrokeStyle(lineWidth: isPad ? 2.4 : 1.8,
                                                       lineCap: .round))
                            .rotationEffect(.degrees(spin))
                            .shadow(color: lamp, radius: 3)
                        Image(systemName: "timer")
                            .font(.system(size: isPad ? 22 : 16, weight: .bold))
                            .foregroundStyle(lamp)
                    }
                }
                .frame(width: isPad ? 40 : 30, height: isPad ? 40 : 30)
                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(size: hudNumberSize, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(timerUrgency > 0.55 ? lamp : .white)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                    Text(verbatim: "\(model.stageNumber)/\(model.totalStages)")
                    Text(verbatim: "· \(model.secondsPerQuestion)s")
                }
                .font(.system(size: isPad ? 10 : 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .offset(y: isPad ? 7 : 5)
            }
        }
        .frame(width: isPad ? 178 : 122)
        .accessibilityIdentifier("level-timer")
    }

    private var scoreCounter: some View {
        cockpitPanel {
            VStack(spacing: isPad ? 5 : 3) {
                HStack(spacing: isPad ? 8 : 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: isPad ? 23 : 16, weight: .bold))
                        .foregroundStyle(hudCyan)
                    Text(verbatim: "\(model.completedQuestions) / \(request.board.maximum)")
                        .environment(\.layoutDirection, .leftToRight)
                        .font(.system(size: hudNumberSize, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .contentTransition(.numericText(value: Double(model.completedQuestions)))
                }
                progressSegments
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: isPad ? 210 : 142)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: model.completedQuestions)
        .accessibilityIdentifier("progress")
    }

    private var progressSegments: some View {
        let count = 4
        let maximum = max(1, request.board.maximum)
        let progress = min(1, max(0, Double(model.completedQuestions) / Double(maximum)))
        return HStack(spacing: isPad ? 5 : 3) {
            ForEach(0..<count, id: \.self) { index in
                let threshold = Double(index + 1) / Double(count)
                let filled = progress + 0.0001 >= threshold
                Capsule()
                    .fill(filled
                          ? LinearGradient(colors: [Color(red: 0.55, green: 1.00, blue: 0.78),
                                                    Color(red: 0.10, green: 0.92, blue: 0.62)],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                          : LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.30),
                                                    Color(red: 0.08, green: 0.12, blue: 0.22)],
                                           startPoint: .leading,
                                           endPoint: .trailing))
                    .overlay(Capsule().stroke(.white.opacity(filled ? 0.45 : 0.12), lineWidth: 0.7))
                    .shadow(color: filled
                            ? Color(red: 0.30, green: 1.00, blue: 0.70).opacity(0.9)
                            : .clear,
                            radius: isPad ? 5 : 3)
                    .scaleEffect(y: filled ? 1 : 0.82)
            }
        }
        .frame(height: isPad ? 9 : 7)
        .animation(.spring(response: 0.34, dampingFraction: 0.68), value: model.completedQuestions)
        .accessibilityHidden(true)
    }

    private var questionReadout: some View {
        questionLabel(model.round?.question.prompt ?? "—")
            .id(model.round?.id)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .accessibilityIdentifier("space-lion-question")
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.round?.id)
    }

    private func questionLabel(_ prompt: String) -> some View {
        let marker = prompt.range(of: "?")
        let leading = marker.map { String(prompt[..<$0.lowerBound]) } ?? prompt
        let trailing = marker.map { String(prompt[$0.upperBound...]) } ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: leading)
                .foregroundStyle(.white)
            if marker != nil {
                Text(verbatim: "?")
                    .foregroundStyle(hudOrange)
                    .shadow(color: hudOrange.opacity(0.95), radius: isPad ? 8 : 5)
            }
            if !trailing.isEmpty {
                Text(verbatim: trailing)
                    .foregroundStyle(.white)
            }
        }
        .font(.system(size: isPad ? 38 : 27, weight: .black, design: .rounded))
        .shadow(color: .black.opacity(0.55), radius: 0, y: 1)
    }

    private func cockpitPanel<Content: View>(
        holographic: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let cut: CGFloat = isPad ? 14 : 10
        let fill = holographic
            ? [Color(red: 0.10, green: 0.16, blue: 0.42),
               Color(red: 0.04, green: 0.05, blue: 0.18),
               Color(red: 0.07, green: 0.03, blue: 0.16)]
            : [Color(red: 0.14, green: 0.20, blue: 0.38),
               Color(red: 0.03, green: 0.05, blue: 0.12),
               Color(red: 0.012, green: 0.02, blue: 0.06)]
        return content()
            .foregroundStyle(.white)
            .padding(.horizontal, isPad ? 17 : 10)
            .frame(height: hudControlSize)
            .background {
                ZStack {
                    CockpitHUDShape(cut: cut)
                        .fill(LinearGradient(colors: fill,
                                             startPoint: .top,
                                             endPoint: .bottom))
                    CockpitHUDShape(cut: cut)
                        .fill(LinearGradient(colors: [.white.opacity(holographic ? 0.16 : 0.10),
                                                      .clear],
                                             startPoint: .top,
                                             endPoint: .center))
                    CockpitHUDShape(cut: cut)
                        .stroke(Color.black.opacity(0.88), lineWidth: isPad ? 8 : 5)
                    CockpitHUDShape(cut: cut)
                        .stroke(hudCyan.opacity(0.95), lineWidth: isPad ? 2.6 : 1.8)
                        .padding(isPad ? 3.5 : 2.2)
                        .shadow(color: hudCyan.opacity(0.65), radius: isPad ? 6 : 4)
                    CockpitHUDShape(cut: cut)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                        .padding(isPad ? 6 : 4)
                    CockpitHUDSideAccents(cut: cut)
                        .stroke(hudOrange,
                                style: StrokeStyle(lineWidth: isPad ? 5 : 3,
                                                   lineCap: .round))
                        .padding(isPad ? 3.5 : 2.2)
                        .shadow(color: hudOrange.opacity(0.9), radius: 5)
                }
                .overlay(alignment: .bottom) {
                    CockpitPanelEnergyRail(
                        color: holographic ? hudOrange : hudCyan,
                        isRunning: isReefRunning && !reduceMotion
                    )
                        .frame(width: isPad ? 72 : 46, height: isPad ? 3 : 2)
                        .padding(.bottom, isPad ? 5 : 3)
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                .shadow(color: hudCyan.opacity(0.28), radius: 10, y: 2)
            }
            // These displays hang from the roof rather than lying flat on the
            // screen. A restrained forward pitch exposes the lower housing and
            // creates depth without compromising text legibility or hit areas.
            .rotation3DEffect(.degrees(isPad ? 4.2 : 5.0),
                              axis: (x: 1, y: 0, z: 0),
                              anchor: .top,
                              perspective: 0.22)
            .shadow(color: .black.opacity(0.34), radius: isPad ? 5 : 3,
                    y: isPad ? 6 : 4)
    }

    private var hudCyan: Color { Color(red: 0.00, green: 0.75, blue: 1.00) }
    /// The secondary cockpit light follows the selected character. For the
    /// lion this is the same warm yellow used by its suit and portrait.
    private var hudOrange: Color { character.color }

    private var showsGameplayHUD: Bool {
        // The HUD belongs to the level reveal, not to the end of the character
        // entrance. Keeping it visible during that entrance prevents the
        // cockpit from appearing first and its instruments popping in later.
        !showsIntro && !playsLevelCompletion
    }

    /// The reef only ticks while the level is actually being played: never
    /// behind the start card or the result card, and never while the app is in
    /// the background.
    private var isReefRunning: Bool {
        !showsIntro && (!model.isGameOver || playsLevelCompletion) && scenePhase == .active
    }
}

/// A large, unmistakable final count in the windshield. Each integer gets its
/// own fresh view identity, so 3, 2 and 1 all land as separate beats.
private struct StageCountdownPulse: View {
    let value: Int
    let isPad: Bool
    let accent: Color
    let reduceMotion: Bool

    @State private var landed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.58))
                .overlay {
                    Circle()
                        .stroke(accent.opacity(0.88), lineWidth: isPad ? 5 : 3)
                        .shadow(color: accent, radius: isPad ? 18 : 11)
                }
            Circle()
                .trim(from: 0.06, to: 0.94)
                .stroke(.white.opacity(0.72),
                        style: StrokeStyle(lineWidth: isPad ? 3 : 2,
                                           lineCap: .round,
                                           dash: [isPad ? 9 : 6, isPad ? 7 : 5]))
                .rotationEffect(.degrees(landed ? 130 : -70))
            Group {
                if value > 0 {
                    Text(verbatim: "\(value)")
                        .font(.system(size: isPad ? 90 : 62,
                                      weight: .black,
                                      design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: isPad ? 64 : 44, weight: .black))
                }
            }
            .foregroundStyle(.white)
            .shadow(color: accent, radius: isPad ? 16 : 10)
        }
        .frame(width: isPad ? 164 : 112, height: isPad ? 164 : 112)
        .scaleEffect(reduceMotion ? 1 : (landed ? 1 : 1.42))
        .opacity(landed ? 1 : 0.28)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                landed = true
            }
        }
        .accessibilityLabel(Text(verbatim: value > 0 ? "\(value)" : "0"))
    }
}

private struct CockpitHUDShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) * 0.22)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}

/// Short character-coloured conductors embedded in both side rails. Drawing
/// them on the same path as the cyan outline makes them read as part of
/// the HUD housing instead of as loose lights floating inside the display.
private struct CockpitHUDSideAccents: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) * 0.22)
        let verticalRail = max(0, rect.height - 2 * c)
        let inset = verticalRail * 0.16
        let top = rect.minY + c + inset
        let bottom = rect.maxY - c - inset

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom))
        path.move(to: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        return path
    }
}

private struct CockpitPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.66),
                       value: configuration.isPressed)
    }
}

/// A restrained status rail for the HUD. This used to give every HUD panel its
/// own animation clock. A fixed highlight has the same illuminated read at
/// this scale without three extra main-thread updates ten times per second.
private struct CockpitPanelEnergyRail: View {
    let color: Color
    let isRunning: Bool

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [color.opacity(0.12),
                         color.opacity(0.55),
                         .white.opacity(0.88),
                         color.opacity(0.55),
                         color.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .opacity(isRunning ? 1 : 0.65)
        .accessibilityHidden(true)
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
