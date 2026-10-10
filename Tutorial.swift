//
//  Tutorial.swift
//  Space Lion
//
//  The guided first run teaches the cockpit: match the question, read the time
//  allowed per question, read the green and yellow pace dots, and read how many
//  rounds this level contains. The farewell then hands the ship over.
//
//  Nothing here re-implements a rule. A step only decides what is highlighted,
//  when answers are accepted, and when the stage clock waits. The sums, the
//  dots and the round count come from the same session the player is about to
//  fly, which is what makes the lesson true.
//

import SwiftUI
import Combine

/// The tutorial card and the HUD both publish geometry in this screen-wide
/// coordinate space, allowing lesson feedback to travel exactly between them.
enum TutorialMessageCoordinateSpace {
    static let game = "game"
}

struct TutorialMessageIconFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Steps

/// The five taught beats of a guided run, in the order they are taught.
enum TutorialStep: Int, Equatable, CaseIterable {
    /// The question is at the top. Tap the answer that matches.
    case findMatch = 1
    /// Each round holds ten questions. How many seconds does each one get?
    case watchClock
    /// Green is within the question allowance, yellow is slower. Prove it twice.
    case paceDots
    /// Harder levels contain more rounds. How many does this one have?
    case countRounds
    /// Handing the ship over.
    case ready

    var messageKey: String { "tutorial.step\(rawValue)" }

    /// One glyph per lesson, so a step is recognisable before it is read.
    var symbolName: String {
        switch self {
        case .findMatch:   return "questionmark.circle.fill"
        case .watchClock:  return "timer"
        case .paceDots:    return "circle.grid.2x2.fill"
        case .countRounds: return "flag.checkered"
        case .ready:       return "paperplane.fill"
        }
    }
}

/// One of the two quizzes. The correct value is the number the cockpit is
/// highlighting, never a figure invented for the lesson.
struct TutorialQuiz: Equatable {
    enum Kind: Equatable {
        case time
        case rounds
    }

    var kind: Kind
    var choices: [Int]
    var correct: Int

    func label(for value: Int) -> String {
        switch kind {
        case .time:   return "\(value)s"
        case .rounds: return "\(value)"
        }
    }
}

/// A completed tutorial answer, shown back with the same colour the pace dots use.
struct TutorialPaceSample: Equatable, Identifiable {
    let index: Int
    let seconds: Double
    /// Within the question allowance. The cockpit paints that green; slower is yellow.
    let isFast: Bool
    var id: Int { index }
}

/// The warm stroke drawn around whichever instrument a step is talking about.
enum TutorialFocus {
    static let color = Color(red: 1.00, green: 0.90, blue: 0.28)
    static let fast = Color(red: 0.20, green: 0.90, blue: 0.42)
    static let steady = Color(red: 1.00, green: 0.78, blue: 0.08)
}

/// A soft pulse, so a highlight reads as "look here" without hiding the number.
struct TutorialPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (dim ? 0.45 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

// MARK: - What a step changes about the game

/// Everything the playing field and the view model have to know about the step
/// being taught, in one value. A default-constructed plan is an ordinary,
/// unguided session, which is what a finished tutorial leaves behind.
struct TutorialPlan: Equatable {
    var step: TutorialStep?

    /// No hoops at all: the first two steps are only about flying.
    var hidesHoops = false
    /// The water is off limits while movement is being taught.
    var blocksDiving = false
    /// Watch for the penguin being dragged to a low and to a high point.
    var tracksDrag = false
    /// Watch for a tap under and a tap above the penguin.
    var tracksTaps = false
    /// Every hoop in the set is wrong, so the only way through is underneath.
    var forcesNoCorrectAnswer = false
    /// Exactly one of the three hoops carries the answer.
    var forcesCorrectAnswer = false
    /// Put that answer in the top hoop. The turbo lesson asks for a tap on it
    /// while the cone, the wake and the message all live along the bottom of
    /// the screen; from the lowest lane the whole lesson piles up in one
    /// corner, and from the top it has room to be read.
    var putsAnswerOnTop = false
    /// Pulse the right hoop.
    var highlightsTurbo = false
    /// Freeze the next set as it arrives until the right hoop is tapped.
    var holdsForTurbo = false
    /// Put a broken-heart marker on each of the two wrong hoops.
    var marksWrongHoops = false
    /// Nothing a mistake does during this step may cost a life.
    var preventsLifeLoss = false
    /// Only passing underneath is free; a wrong hoop costs a life as it should.
    var preventsBypassLifeLoss = false
    /// The player has missed the dive lesson twice. The field demonstrates the
    /// complete move on the next set: down, underneath, and back into the air.
    var demonstratesDive = false

    /// The side buttons accept a tap. Quizzes and the farewell hold them.
    var blocksAnswers = false
    /// The stage clock and the question timer wait, so a quiz does not spend
    /// the time the lesson is asking about.
    var freezesPlay = false
    var highlightsQuestion = false
    var highlightsTimeAllowance = false
    var highlightsPaceDots = false
    var highlightsRoundCount = false
    var quiz: TutorialQuiz?
    var paceSamples: [TutorialPaceSample] = []
    /// The two pace answers have landed and are being shown back.
    var showsPaceReveal = false

    var isRunning: Bool { step != nil }
    /// Quizzes and the pace reveal own the touch, so a tap cannot also hit a sum.
    var capturesTouches: Bool { quiz != nil || showsPaceReveal }

    /// The rules that belong to a step.
    static func plan(for step: TutorialStep?) -> TutorialPlan {
        var plan = TutorialPlan()
        plan.step = step
        switch step {
        case .findMatch:
            plan.highlightsQuestion = true
        case .watchClock:
            plan.blocksAnswers = true
            plan.freezesPlay = true
            plan.highlightsTimeAllowance = true
        case .paceDots:
            plan.highlightsPaceDots = true
        case .countRounds:
            plan.blocksAnswers = true
            plan.freezesPlay = true
            plan.highlightsRoundCount = true
        case .ready:
            plan.blocksAnswers = true
            plan.freezesPlay = true
        case .none:
            break
        }
        return plan
    }
}

// MARK: - What the player did

/// The things a guided run listens for. They are raised by the playing field,
/// which is the only place that knows how a passage actually ended.
enum TutorialEvent: Equatable {
    /// Dragged down into the lower part of the flight band.
    case draggedLow
    /// Dragged up into the upper part of it.
    case draggedHigh
    /// Tapped below the penguin.
    case tappedBelow
    /// Tapped above it.
    case tappedAbove
    /// Flew underneath the complete set.
    case passedUnderSet
    /// Flew through the hoop carrying the answer.
    case passedCorrectHoop(withTurbo: Bool)
    /// Flew through one of the wrong hoops.
    case passedWrongHoop
}

// MARK: - Director

/// The state machine behind a guided run. It holds no sums of its own. The
/// view model tells it which answer landed, and which quiz figure was tapped.
@MainActor
final class TutorialDirector {
    private(set) var plan = TutorialPlan()

    var step: TutorialStep? { plan.step }
    var isRunning: Bool { plan.isRunning }

    /// Raised whenever the plan changed, so the view model can mirror it onto
    /// its published properties in one place.
    var onChange: (() -> Void)?

    /// How long a correct match is given before the next card replaces it.
    private static let matchHandover = 0.55
    /// How long the two pace times stay up before the rounds quiz, if the
    /// player does not tap Continue.
    private static let paceReveal = 4.2
    /// How long the closing message stays up.
    private static let farewell = 3.6
    /// Step 3 asks for two completed answers before it shows their times.
    private static let paceAnswers = 2

    /// Seconds the highlighted allowance actually grants. Stage 1 is 10.
    private var secondsPerQuestion = GameConfig.secondsPerQuestionByStage[0]
    /// Rounds in the level being taught. One round is ten questions.
    private var roundCount = 1
    private var paceSamples: [TutorialPaceSample] = []
    /// True between a step being satisfied and the next one arriving, so the
    /// step that is on its way out cannot be completed a second time.
    private var isAdvancing = false
    private var stepWork: DispatchWorkItem?

    // MARK: Lifecycle

    /// The figures the quizzes have to agree with. Called before `begin`.
    func prepare(secondsPerQuestion: Int, roundCount: Int) {
        self.secondsPerQuestion = max(1, secondsPerQuestion)
        self.roundCount = max(1, roundCount)
    }

    func begin() {
        guard plan.step == nil else { return }
        paceSamples = []
        isAdvancing = false
        apply(.findMatch)
    }

    /// Ends the run without finishing it — the screen is going away, or the
    /// session ended under the tutorial's feet.
    func cancel() {
        stepWork?.cancel()
        stepWork = nil
        isAdvancing = false
        paceSamples = []
        guard plan.step != nil else { return }
        plan = TutorialPlan()
        onChange?()
    }

    /// Legacy flight events. The retired playfield still reports them; a Space
    /// Lion lesson does not advance on a drag or a hoop.
    func report(_: TutorialEvent) {}

    // MARK: What happened

    /// A correct answer in the live session. Wrong answers retry the sum and
    /// do not count toward the pace lesson.
    func noteCorrectAnswer(seconds: Double, isFast: Bool) {
        guard let step = plan.step else { return }
        switch step {
        case .findMatch:
            guard !isAdvancing else { return }
            plan.blocksAnswers = true
            plan.freezesPlay = true
            onChange?()
            advance(to: .watchClock, after: Self.matchHandover)
        case .paceDots:
            guard !plan.showsPaceReveal, !plan.blocksAnswers else { return }
            paceSamples.append(TutorialPaceSample(index: paceSamples.count,
                                                  seconds: seconds,
                                                  isFast: isFast))
            plan.paceSamples = paceSamples
            if paceSamples.count >= Self.paceAnswers {
                plan.blocksAnswers = true
                plan.freezesPlay = true
                onChange?()
                schedule(after: Self.matchHandover) { [weak self] in
                    self?.showPaceReveal()
                }
            } else {
                onChange?()
            }
        case .watchClock, .countRounds, .ready:
            break
        }
    }

    /// A tap on one of the three quiz figures. A wrong figure stays on screen.
    @discardableResult
    func choose(_ value: Int) -> Bool {
        guard let quiz = plan.quiz,
              plan.step == .watchClock || plan.step == .countRounds else { return false }
        if isAdvancing { return value == quiz.correct }
        guard value == quiz.correct else { return false }
        let next: TutorialStep = plan.step == .watchClock ? .paceDots : .ready
        advance(to: next, after: 0.28)
        return true
    }

    func continueAfterPaceReveal() {
        guard plan.step == .paceDots, plan.showsPaceReveal, !isAdvancing else { return }
        advance(to: .countRounds, after: 0.05)
    }

    // MARK: Plumbing

    private func showPaceReveal() {
        guard plan.step == .paceDots, !isAdvancing else { return }
        plan.showsPaceReveal = true
        plan.blocksAnswers = true
        plan.freezesPlay = true
        plan.paceSamples = paceSamples
        onChange?()
        schedule(after: Self.paceReveal) { [weak self] in
            guard let self, self.plan.showsPaceReveal, !self.isAdvancing else { return }
            self.advance(to: .countRounds, after: 0)
        }
    }

    private func advance(to step: TutorialStep, after delay: Double) {
        isAdvancing = true
        schedule(after: delay) { [weak self] in
            self?.apply(step)
        }
    }

    private func apply(_ step: TutorialStep) {
        isAdvancing = false
        var next = TutorialPlan.plan(for: step)
        switch step {
        case .watchClock:
            next.quiz = TutorialQuiz(kind: .time,
                                     choices: Self.options(correct: secondsPerQuestion, delta: 5),
                                     correct: secondsPerQuestion)
        case .paceDots:
            next.paceSamples = paceSamples
        case .countRounds:
            next.quiz = TutorialQuiz(kind: .rounds,
                                     choices: Self.options(correct: roundCount, delta: 1),
                                     correct: roundCount)
        case .findMatch, .ready:
            break
        }
        plan = next
        onChange?()

        guard step == .ready else { return }
        schedule(after: Self.farewell) { [weak self] in
            self?.cancel()
        }
    }

    /// Three different positive figures, one of them the cockpit's own number.
    private static func options(correct: Int, delta: Int) -> [Int] {
        var values = [correct]
        let candidates = [correct - delta, correct + delta,
                          correct - 1, correct + 1, correct + 2,
                          1, 2, 3]
        for candidate in candidates where candidate > 0 && !values.contains(candidate) {
            values.append(candidate)
            if values.count == 3 { break }
        }
        return values.shuffled()
    }

    private func schedule(after delay: Double, work: @escaping () -> Void) {
        stepWork?.cancel()
        let item = DispatchWorkItem(block: work)
        stepWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

// MARK: - Hand-overs between screens

/// The one piece of tutorial state that outlives a screen: the welcome flow asks
/// for a level to be opened straight into a guided run.
@MainActor
final class TutorialCenter: ObservableObject {
    static let shared = TutorialCenter()

    private static let completedKey = "tutorial.completed"

    /// The level the welcome flow wants opened, guided, the moment the menu
    /// appears. Nil at every other launch.
    @Published private(set) var autoStartLevel: MathLevel?

    /// True from the last welcome answer until the guided level is on screen.
    /// While it holds, the welcome screen stays put and the menu is built up
    /// behind it: the child answered a question and the game rises over that
    /// same screen, rather than the menu flashing past in between.
    @Published private(set) var isHandingOverFromWelcome = false

    private init() {}

    /// Whether the player has ever been through a guided run. Only used to keep
    /// the welcome flow from insisting a second time on a replayed onboarding.
    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// Called as the welcome flow hands over: the level selected by the
    /// player's starting-point choice is what they will be taught on.
    func requestAutoStart(topic: MathTopic, index: Int) {
        autoStartLevel = MathLevel(topic: topic, index: index)
        isHandingOverFromWelcome = true
    }

    /// Taken by the menu, once.
    func takeAutoStartLevel() -> MathLevel? {
        defer { autoStartLevel = nil }
        return autoStartLevel
    }

    /// The guided level covers the screen, so the welcome screen underneath it
    /// has nothing left to hold. Also called when the hand-over cannot happen,
    /// so a failed start can never leave the welcome screen on top.
    func finishWelcomeHandover() {
        isHandingOverFromWelcome = false
    }

    /// A guided run has begun.
    func guidedRunStarted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }
}

// MARK: - The message card

/// What a tutorial says, wherever it says it. Deliberately the same card the
/// standing sum is drawn on — white, the character's own colour around it — so a
/// tutorial message reads as part of the game rather than as an overlay on it.
struct TutorialMessageCard: View {
    let text: String
    /// The glyph for this particular lesson — see `TutorialStep.symbolName`.
    let symbolName: String
    let theme: AnimalCharacter
    var isPad: Bool = AppLayout.isPad
    /// The playing field hands over a fixed band so the swarm can steer around
    /// it; the menu lets the card size itself.
    var fixedSize: CGSize?

    var body: some View {
        HStack(alignment: .center, spacing: isPad ? 14 : 10) {
            Image(systemName: symbolName)
                .font(.system(size: isPad ? 26 : 20, weight: .bold))
                .foregroundStyle(theme.color)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialMessageIconFrameKey.self,
                            value: proxy.frame(in: .named(TutorialMessageCoordinateSpace.game))
                        )
                    }
                }

            Text(verbatim: text)
                .font(.system(size: isPad ? 20 : 15.5, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.deepColor)
                .multilineTextAlignment(.leading)
                // One line, always. The card is a band across the bottom of a
                // landscape screen with three lanes of hoops above it: a second
                // line grows downward into the lowest lane and covers the very
                // answer the lesson is talking about. A long sentence in a long
                // language shrinks to fit instead — the caller caps how wide
                // the card may get, and the type follows.
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
        }
        .padding(.horizontal, isPad ? 20 : 14)
        .padding(.vertical, isPad ? 14 : 10)
        .frame(width: fixedSize?.width, height: fixedSize?.height)
        .background(.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: isPad ? 23 : 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPad ? 23 : 18, style: .continuous)
                .stroke(theme.color, lineWidth: isPad ? 5 : 4)
        }
        .shadow(color: theme.deepColor.opacity(0.18), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "Not now" notice

/// Shown when the tutorial is asked for in the middle of a run. It is the same
/// card the level intro is built from — white sheet, one heavy heading, one line
/// of explanation and a single filled button in the character's deep colour.
struct TutorialNoticeCard: View {
    let theme: AnimalCharacter
    let onDismiss: () -> Void

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14 * scale) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 30 * scale, weight: .bold))
                    .foregroundStyle(theme.color)

                Text("tutorial.notice.title")
                    .font(.system(size: 22 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .multilineTextAlignment(.center)

                Text("tutorial.notice.message")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(theme.deepColor.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("common.ok")
                        .font(.system(size: 17 * scale, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13 * scale)
                        .foregroundStyle(.white)
                        .background(theme.deepColor,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial-notice-ok")
                .padding(.top, 2 * scale)
            }
            .padding(24 * scale)
            .frame(width: isPad ? 420 : 340)
            // Same light fill as the start/pause card: `.background` turns
            // black in Dark Mode against this card's deep-purple copy.
            .background(Color.white.opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
            .shadow(color: theme.deepColor.opacity(0.3), radius: 18, y: 8)
        }
        .transition(.opacity)
    }
}

// MARK: - Cockpit coach

/// The lesson card, the three quiz figures, and the pace replay. It sits on
/// the deck, under the question, and only its buttons take a touch.
struct TutorialCoach: View {
    let plan: TutorialPlan
    let text: String
    let theme: AnimalCharacter
    var isPad: Bool = AppLayout.isPad
    let onChoose: (Int) -> Bool
    let onContinue: () -> Void

    @ObservedObject private var language = LanguageManager.shared
    @State private var rejected: Int?
    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(spacing: isPad ? 12 : 8) {
            message
                .allowsHitTesting(false)

            if let quiz = plan.quiz {
                HStack(spacing: isPad ? 14 : 10) {
                    ForEach(quiz.choices, id: \.self) { value in
                        choice(value, in: quiz)
                    }
                }
            }

            if plan.showsPaceReveal, !plan.paceSamples.isEmpty {
                HStack(spacing: isPad ? 22 : 16) {
                    ForEach(plan.paceSamples) { sample in
                        paceSample(sample)
                    }
                }
                .allowsHitTesting(false)

                Button(action: onContinue) {
                    Text("common.continue")
                        .font(.system(size: isPad ? 18 : 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.deepColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isPad ? 12 : 9)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial-pace-continue")
            }
        }
        .padding(isPad ? 16 : 12)
        .frame(maxWidth: isPad ? 640 : 420)
        .background(.black.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: isPad ? 22 : 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPad ? 22 : 16, style: .continuous)
                .stroke(theme.color.opacity(0.9), lineWidth: isPad ? 3 : 2)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onChange(of: plan.step) { _, _ in
            rejected = nil
            shake = 0
        }
    }

    private var message: some View {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = String(parts.first ?? "")
        let body = parts.count > 1 ? String(parts[1]) : ""
        return VStack(alignment: .leading, spacing: isPad ? 6 : 4) {
            HStack(alignment: .center, spacing: isPad ? 10 : 8) {
                if let symbol = plan.step?.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: isPad ? 22 : 16, weight: .bold))
                        .foregroundStyle(theme.color)
                }
                Text(verbatim: title)
                    .font(.system(size: isPad ? 22 : 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !body.isEmpty {
                Text(verbatim: body)
                    .font(.system(size: isPad ? 18 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func choice(_ value: Int, in quiz: TutorialQuiz) -> some View {
        let isRejected = rejected == value
        return Button {
            if onChoose(value) {
                rejected = nil
            } else {
                rejected = value
                shake = 0
                withAnimation(.linear(duration: 0.36)) { shake = 1 }
            }
        } label: {
            Text(verbatim: quiz.label(for: value))
                .font(.system(size: isPad ? 28 : 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: isPad ? 96 : 72, minHeight: isPad ? 64 : 48)
                .background(Color(red: 0.08, green: 0.12, blue: 0.28),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isRejected
                                ? Color(red: 1.00, green: 0.38, blue: 0.28)
                                : theme.color,
                                lineWidth: isPad ? 3 : 2.5)
                }
        }
        .buttonStyle(.plain)
        .modifier(TutorialChoiceShake(travel: isRejected ? shake : 0))
        .accessibilityIdentifier("tutorial-choice-\(value)")
    }

    private func paceSample(_ sample: TutorialPaceSample) -> some View {
        HStack(spacing: isPad ? 8 : 6) {
            Circle()
                .fill(sample.isFast ? TutorialFocus.fast : TutorialFocus.steady)
                .frame(width: isPad ? 18 : 14, height: isPad ? 18 : 14)
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
            Text(verbatim: paceLabel(sample.seconds))
                .font(.system(size: isPad ? 22 : 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tutorial-pace-\(sample.index)")
    }

    /// One decimal, in the language on screen, so 8.4 and 8,4 both read as time.
    private func paceLabel(_ seconds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: NSNumber(value: seconds)) ?? String(format: "%.1f", seconds)
        return number + "s"
    }
}

/// A short sideways shake for a quiz figure that is not the cockpit's number.
private struct TutorialChoiceShake: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(travel * .pi * 4) * 7
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
