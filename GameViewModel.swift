//
//  GameViewModel.swift
//  Elephant Challenge: Math Memory
//
//  The bridge between the pure `MemoryGame` engine and SwiftUI. It owns the
//  timing of a round (sum → answers → feedback → next sum), the audio and
//  haptics, and the persistence of a finished session.
//
//  It never re-implements a rule: every tap is forwarded to the engine, and the
//  engine's answer decides what happens. That is what keeps rapid tapping from
//  scoring twice or costing two lives.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class GameViewModel: ObservableObject {
    private let request: GameSessionRequest
    private var engine: MemoryGame

    // Published mirrors of the engine, so SwiftUI observes value changes.
    @Published private(set) var state: GameState = .intro
    @Published private(set) var round: GameRound?
    @Published private(set) var roundNumber = 0
    @Published private(set) var cards = 0
    @Published private(set) var livesRemaining = GameConfig.startingLives
    @Published private(set) var selectedOptionID: UUID?
    @Published private(set) var isGameOver = false
    @Published private(set) var result = SessionResult()
    @Published private(set) var hasBonusFishPower = false
    @Published private(set) var isHeartFishAvailable = false
    @Published private(set) var comboAnnouncementID = 0
    /// The most recent question answered incorrectly, with its answer filled
    /// in. It remains part of this run until a fresh run is started.
    @Published private(set) var lastMissedChallenge: String?
    @Published private(set) var visibleRounds: [GameRound] = []
    /// The guided run, if this session is one: what is being taught and which
    /// rules it bends. A mirror of the director below, published the same way
    /// the engine's state is.
    @Published private(set) var tutorial = TutorialPlan()
    /// Whether the session's one rescue heart is owed to the next set of hoops.
    /// Never during a guided run: the life lesson is about losing a heart, and
    /// a rescue heart in the same flight would teach the opposite thing.
    @Published private(set) var isRescueHeartDue = false

    /// Invalidates pending timed work when a round is superseded (restart, or
    /// leaving the screen), so a late callback can never touch a newer round.
    private var generation = 0
    private var hasRecordedResult = false
    private var isPaused = false
    /// A round-resolution callback that became due while the pause card was
    /// covering the reef. It runs once on continue instead of behind the card.
    private var pendingScheduledWork: (() -> Void)?
    private var lastCorrectCatchTime: TimeInterval?
    /// The guided run's state machine. It is asked what to show and which rules
    /// the step being taught bends; it never touches the engine itself.
    private let director = TutorialDirector()

    var maximumRounds: Int { engine.maximumRounds }

    /// True during the short feedback beat after the passage that will fill
    /// the board. The playfield uses this head start to glide into its finale
    /// instead of waiting motionless for the engine to close the round.
    var preparesLevelCompletion: Bool {
        guard engine.state == .resolving, engine.livesRemaining > 0 else { return false }
        return engine.cards >= request.board.maximum || engine.roundNumber >= engine.maximumRounds
    }
    var acceptsInput: Bool { state == .answering && !isPaused }

    init(request: GameSessionRequest) {
        self.request = request
        self.engine = MemoryGame(level: request.level,
                            mixedVariant: request.mixedVariant,
                            mode: request.mode)
        // Not seeded from the request: the welcome flow only pre-arms the start
        // card's switch, and the player is free to turn it off there. What the
        // card was showing when Start was pressed is what counts, and that
        // arrives through `armTutorial`.
        director.onChange = { [weak self] in self?.syncTutorial() }
    }

    // MARK: - Tutorial

    /// Arms the guided run for the session about to start. Only meaningful
    /// before `begin()`: a run already in progress is never taken over.
    ///
    /// The first step is applied here rather than at `begin()`, because the
    /// cannon puts the first set of hoops on the conveyor while the penguin is
    /// still in the barrel — and the lesson that opens the run is the one that
    /// says there are no hoops yet. Nothing of it is visible this early: the
    /// message card waits for the flight to settle.
    func armTutorial() {
        guard engine.state == .intro else { return }
        director.begin()
    }

    /// The playing field is the only place that knows how a passage actually
    /// ended, so every lesson is driven from there.
    func reportTutorial(_ event: TutorialEvent) {
        guard director.isRunning else { return }
        director.report(event)
    }

    private func syncTutorial() {
        set(\.tutorial, director.plan)
        set(\.isRescueHeartDue, engine.isRescueHeartDue && !director.isRunning)
    }

    // MARK: - Life hearts

    /// Whether a heart still has a life to give. Asked before the caught heart
    /// sets off for the meter, because the life is only put on the meter when
    /// it arrives — there is no point flying one to a full row of hearts.
    var canTakeLifeHeart: Bool {
        livesRemaining > 0 && livesRemaining < GameConfig.startingLives
    }

    /// A heart in the flight path has arrived at the meter. The pickup sound
    /// already played at contact; arrival only updates the life and its haptic.
    @discardableResult
    func collectLifeHeart() -> Bool {
        guard engine.restoreLifeHalves(GameConfig.lifeHeartRecoveryHalves) > 0 else { return false }
        PlaytimeTracker.shared.registerInteraction()
        sync()
        haptic(.success)
        return true
    }

    /// The rescue heart has been put in the world. Placing it is what spends
    /// it: flying past one is a miss, not a second chance.
    func placeRescueHeart() {
        engine.spendRescueHeart()
        sync()
    }

    // MARK: - Lifecycle

    /// Prepares questions while the start card is still covering the field.
    /// Publishing the first three also lets the playfield bake their food
    /// glyphs before the display link and tongue animation start running.
    func prepare() {
        guard engine.state == .intro else { return }
        let resumedRound = PausedSessionStore.shared.session(request.board)?.roundNumber ?? 1
        engine.prepare(startingAt: resumedRound)
#if canImport(UIKit)
        // Allocate and wake every feedback generator while the intro card still
        // covers the playfield. The first answer used to lazily create the
        // notification generator on the main thread in the same frame as the
        // score, hoop feedback and swallow animation, producing a one-off hitch.
        prepareHaptics()
#endif
        sync()
    }

    /// Starts the level, resuming a paused session when one is waiting.
    func begin() {
        guard engine.state == .intro else { return }
        isPaused = false
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true)
        AppAudio.shared.playSessionStart()
        if let paused = PausedSessionStore.shared.session(request.board) {
            engine.resume(from: paused)
            hasBonusFishPower = paused.hasBonusFishPower ?? false
            lastMissedChallenge = paused.lastMissedChallenge
        } else {
            engine.start()
        }
        openRound()
        announceRound()
        sync()
    }

    /// Opens a round for play. Under water there is nothing to memorise: the
    /// sum stands on the coral from the first frame, so the round goes straight
    /// through to accepting an answer.
    private func openRound() {
        engine.turnCardsOver()
        engine.beginAnswering()
    }

    private func announceRound() {
        AppAudio.shared.playCardReveal()
    }

    func end() {
        director.cancel()
        // Leaving without finishing pauses the level rather than discarding it.
        savePausedSessionIfNeeded()
        recordResultIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false)
        generation &+= 1
        pendingScheduledWork = nil
        lastCorrectCatchTime = nil
    }

    /// Temporarily stops an active run without ending it. The snapshot also
    /// makes the same run available if the player chooses the main menu from
    /// the pause card instead of continuing immediately.
    func pause() {
        guard engine.state != .gameOver else { return }
        isPaused = true
        savePausedSessionIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false)
        lastCorrectCatchTime = nil
    }

    /// Continues the in-memory run after its pause card. No round is rebuilt,
    /// so the player returns to the exact question, score and remaining lives.
    func resume() {
        guard engine.state != .intro, engine.state != .gameOver else { return }
        isPaused = false
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true)
        sync()
        let work = pendingScheduledWork
        pendingScheduledWork = nil
        work?()
    }

    /// The close button: the level is put on pause with its cards intact, and
    /// those cards are banked to the player's total straight away.
    func quit() {
        savePausedSessionIfNeeded()
        engine.quit()
        recordResultIfNeeded()
        sync()
    }

    /// Freezes the session for this level, so re-entering it continues from
    /// here. A finished session has nothing to store and clears the record.
    ///
    /// A run that has not banked a single card is not worth coming back to:
    /// storing it would only put a pause marker on the menu for a level the
    /// player would restart from zero anyway.
    private func savePausedSessionIfNeeded() {
        guard !hasRecordedResult,
              let paused = engine.pausedSession(
                hasBonusFishPower: hasBonusFishPower,
                lastMissedChallenge: lastMissedChallenge
              )
        else { return }
        guard paused.cards > 0 else {
            PausedSessionStore.shared.clear(request.board)
            return
        }
        PausedSessionStore.shared.save(paused)
    }

    /// Play again always starts a clean run, so any paused record for this
    /// level is spent.
    func restart() {
        // Play again is an ordinary run: the lesson was taught once.
        director.cancel()
        generation &+= 1
        hasRecordedResult = false
        isPaused = false
        pendingScheduledWork = nil
        PausedSessionStore.shared.clear(request.board)
        engine = MemoryGame(level: request.level,
                            mixedVariant: request.mixedVariant,
                            mode: request.mode)
        engine.start()
        hasBonusFishPower = false
        lastMissedChallenge = nil
        comboAnnouncementID = 0
        lastCorrectCatchTime = nil
        AppAudio.shared.playSessionStart()
        openRound()
        announceRound()
        sync()
    }

    // MARK: - Round flow

    /// Forwards an answer bubble the fish touched. The engine decides whether
    /// it counts; a touch that arrives while feedback is still playing comes
    /// back as `.ignored` and changes nothing at all. The returned flag tells
    /// the reef whether to burst the bubble.
    @discardableResult
    func select(optionID: UUID,
                usesSpeedBonus: Bool = false,
                wrongAnswerCostHalves: Int? = nil) -> Bool {
        // A guided step never refuses an answer — the passage always resolves
        // and the run moves on. What it does change is the price: while the
        // early lessons are being taught a mistake costs nothing, and in the
        // life lesson only a wrong hoop the penguin really flew through does.
        // A non-nil cost here is the playing field saying the set was passed
        // underneath, which is the one case that half-price penalty covers.
        let costHalves = tutorial.preventsLifeLoss
            || (tutorial.preventsBypassLifeLoss && wrongAnswerCostHalves != nil)
            ? 0
            : wrongAnswerCostHalves
        let spendsBonusFish = hasBonusFishPower
        let outcome = engine.select(optionID: optionID,
                                    usesBonusFish: usesSpeedBonus || spendsBonusFish,
                                    wrongAnswerCostHalves: costHalves)
        guard outcome != .ignored else { return false }
        // Every real interaction advances the playtime clock. Without these the
        // tracker only ever sees one gap from the first touch to the last,
        // which its idle limit then discards — a whole session counting as no
        // time.
        PlaytimeTracker.shared.registerInteraction()
        let token = generation
        let delay: Double
        let announcesNextRound: Bool
        switch outcome {
        case .correct(_, let usedBonusFish):
            let now = ProcessInfo.processInfo.systemUptime
            if let previous = lastCorrectCatchTime, now - previous <= 1 {
                engine.awardFlyComboBonus()
                comboAnnouncementID &+= 1
            }
            lastCorrectCatchTime = now
            if usedBonusFish {
                if spendsBonusFish { hasBonusFishPower = false }
                AppAudio.shared.playDoubleScore()
            }
            delay = GameConfig.nextRoundDelay.correct
            announcesNextRound = true
        case .wrong:
            lastMissedChallenge = engine.round?.question.solvedPrompt
            lastCorrectCatchTime = nil
            // Neither the verdict's sound nor its haptic fires here any more —
            // both wait for `reportCatchOutcome`. The life going is no longer
            // sounded at all: it played on the strike and drowned out the
            // wrong-answer sound arriving at the mouth behind it.
            delay = GameConfig.nextRoundDelay.wrong
            // `wrong_2` intentionally has a long tail. The reveal chime used
            // to start 0.46 seconds after the passage and sounded like a second
            // positive verdict on top of it.
            announcesNextRound = false
        case .ignored:
            return false
        }

        // Score, combo bonus and answer state are published together. In a
        // fast run this avoids rebuilding the game once for the normal reward
        // and immediately again for the combo reward.
        sync()

        schedule(after: delay, token: token) { [weak self] in
            guard let self else { return }
            guard self.engine.finishResolving() else { return }
            let previousRoundID = self.engine.round?.id
            self.engine.advance()
            if self.engine.state == .gameOver {
                self.finishSession(playsFanfare: announcesNextRound)
            } else if self.engine.round?.id != previousRoundID {
                // Every completed passage opens the already-previewed next sum.
                if announcesNextRound { self.announceRound() }
                self.openRound()
            }
            self.sync()
        }
        return true
    }

    /// Announces the verdict on a catch. The answer is scored the moment the
    /// tongue reaches the food, but it is only heard and felt here — when the
    /// food arrives in the mouth — so sound, haptic and the mark over the
    /// character's head all land on the swallow the child is watching rather
    /// than a third of a second ahead of it.
    func reportCatchOutcome(isCorrect: Bool) {
        if isCorrect {
            AppAudio.shared.playCorrect()
            haptic(.success)
        } else {
            AppAudio.shared.playWrongAnswer()
            haptic(.wrongAnswer)
        }
    }

    /// A correct dive has audio feedback, but deliberately no haptic: the
    /// water animation itself is the physical cue and should stay calm.
    func reportDiveOutcome() {
        AppAudio.shared.playCorrect()
    }

    /// Called by the reef when the player catches the passing 2x fish. Multiple
    /// catches do not stack: one aura always represents one doubled answer.
    func catchBonusFish() {
        guard !hasBonusFishPower else { return }
        hasBonusFishPower = true
        AppAudio.shared.playDoubleCardAppear()
        haptic(.rigid)
    }

    /// The heart fish is a direct life reward, not a power held for the next
    /// answer, so the engine applies it immediately.
    @discardableResult
    func catchHeartFish() -> Bool {
        let restoredHalves = engine.catchHeartFish()
        guard restoredHalves > 0 else { return false }
        PlaytimeTracker.shared.registerInteraction()
        sync()
        AppAudio.shared.playLifePickup()
        haptic(.success)
        return true
    }

    func missHeartFish() {
        engine.missHeartFish()
        sync()
    }

    // MARK: - Finishing

    private func finishSession(playsFanfare: Bool) {
        // The board filling up, or the lives running out, ends the lesson with
        // the session it was being taught in.
        director.cancel()
        recordResultIfNeeded(playsFanfare: playsFanfare)
    }

    /// Writes the session to disk exactly once, whichever way the screen is
    /// left: game over, the close button, or a swipe away.
    private func recordResultIfNeeded(playsFanfare: Bool = true) {
        guard engine.state == .gameOver, !hasRecordedResult else { return }
        hasRecordedResult = true
        // A level that reached its end is finished, not paused.
        if engine.gameOverReason != .quit, playsFanfare {
            PausedSessionStore.shared.clear(request.board)
        }

        let store = Progress.store
        let previousTotal = store.totalCards
        let newTotal = store.addCards(engine.cards)
        // The score belongs to the board this session was played on: the card
        // count, and on Supermix the combination, keep separate bests.
        let board = request.board
        let best = store.recordScore(engine.cards, board: board)
        let unlocked = CharacterUnlocks.newlyUnlocked(from: previousTotal, to: newTotal)

        // Reaching this board's maximum is tallied every time, which is what
        // the ×N badge on a completed card counts.
        let maximum = board.maximum
        if engine.cards >= maximum {
            store.recordMaxCompletion(board)
        }

        engine.applyProgressOutcome(previousBest: best.previousBest,
                                    isNewPersonalBest: best.isNewBest,
                                    unlockedCharacterIDs: unlocked)

        ReviewRequestCoordinator.shared.recordCompletedGame(
            isNewHighScore: best.isNewBest,
            score: engine.cards,
            maximumScore: maximum
        )

        // Leaving a level part-way through is not an achievement: the pause
        // button banks the cards quietly, with no end-of-session fanfare.
        if engine.gameOverReason != .quit {
            if best.isNewBest && engine.cards > 0 { AppAudio.shared.playHighScore() }
            else { AppAudio.shared.playSessionComplete() }
        }
        result = engine.result
    }

    // MARK: - Plumbing

    /// Copies the engine's state onto the published properties in one pass, so
    /// a single tap causes exactly one SwiftUI update rather than eight.
    ///
    /// Every assignment goes through `set`, which drops the ones that would
    /// announce a value the view already has. `@Published` has no opinion about
    /// that: assigning the same number still fires `objectWillChange`, and the
    /// whole game screen — the playfield included — is rebuilt behind it. A
    /// single answer runs this three times (the tap, the combo bonus, the round
    /// turning over) and almost every field is unchanged on all three.
    private func sync() {
        set(\.state, engine.state)
        set(\.round, engine.round)
        set(\.roundNumber, engine.roundNumber)
        set(\.cards, engine.cards)
        set(\.livesRemaining, engine.livesRemaining)
        set(\.selectedOptionID, engine.selectedOptionID)
        // Publish the completed result before the game-over flag. GameView
        // uses its reason to decide whether to play the reef finale first.
        if engine.state == .gameOver { set(\.result, engine.result) }
        set(\.isGameOver, engine.state == .gameOver)
        set(\.isHeartFishAvailable, engine.isHeartFishAvailable)
        set(\.isRescueHeartDue, engine.isRescueHeartDue && !director.isRunning)
        set(\.visibleRounds, engine.visibleRounds)
    }

    private func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<GameViewModel, Value>,
                                       _ value: Value) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    /// Runs `work` after a delay, unless the session moved on in the meantime.
    private func schedule(after delay: Double, token: Int, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            guard !self.isPaused else {
                self.pendingScheduledWork = work
                return
            }
            work()
        }
    }

    private enum Haptic { case light, rigid, success, error, wrongAnswer }

#if canImport(UIKit)
    // Kept for the whole session rather than built per answer. A fresh
    // generator has to wake the Taptic engine before it can fire, which is
    // main-thread work landing in the same frame as the catch that asked for
    // it; a warm one fires immediately. `prepare()` afterwards keeps it warm
    // for the next answer, which during a fast streak is moments away.
    private lazy var lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private lazy var rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
#endif

    private func haptic(_ kind: Haptic) {
#if canImport(UIKit)
        switch kind {
        case .light:
            lightGenerator.impactOccurred()
            rearm { $0.lightGenerator }
        case .rigid:
            rigidGenerator.impactOccurred()
            rearm { $0.rigidGenerator }
        case .success:
            notificationGenerator.notificationOccurred(.success)
            rearm { $0.notificationGenerator }
        case .error:
            notificationGenerator.notificationOccurred(.error)
            rearm { $0.notificationGenerator }
        case .wrongAnswer:
            // The system's error pattern on its own is a polite little stutter,
            // easy to miss with the device flat on a table or in a thick case.
            // A full-strength knock in front of it gives the mistake a body,
            // and the gap is what keeps the two from merging into one buzz.
            heavyGenerator.impactOccurred(intensity: 1)
            rearm { $0.heavyGenerator }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.notificationGenerator.notificationOccurred(.error)
                self.rearm { $0.notificationGenerator }
            }
        }
#endif
    }

#if canImport(UIKit)
    /// Performs the one-time generator allocation away from a live gameplay
    /// frame and primes the Taptic engine for the first interaction.
    private func prepareHaptics() {
        lightGenerator.prepare()
        rigidGenerator.prepare()
        heavyGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Keeps a generator warm for the next answer without doing it here.
    /// `prepare()` wakes the Taptic engine, and the frame it was being called on
    /// is the frame a catch lands: the answer's sound, its verdict mark, the
    /// score and the whole swarm all change on that same frame. A warm-up is the
    /// one part of that with no deadline, so it waits for the next turn of the
    /// run loop and leaves the frame alone.
    private func rearm(_ generator: @escaping (GameViewModel) -> UIFeedbackGenerator) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            generator(self).prepare()
        }
    }
#endif
}
