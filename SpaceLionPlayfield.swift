import SwiftUI

private enum LionMotionPhase: Equatable {
    case idle
    case orientingOut
    case travellingOut
    case contact
    case pushingOff
    case travellingHome
    case settling
}

/// Space Lion's complete in-game surface. It deliberately keeps the same
/// boundary as the Flying Penguin field so the surrounding start, pause,
/// result, score and navigation flows remain untouched.
struct SpaceLionPlayfield: View {
    let rounds: [GameRound]
    let maximumRounds: Int
    let character: AnimalCharacter
    let isPad: Bool
    let isLive: Bool
    let isRunning: Bool
    let playsFishEntrance: Bool
    let preparesLevelCompletion: Bool
    let playsLevelCompletion: Bool
    let reduceMotion: Bool
    let topReserve: CGFloat
    let bottomReserve: CGFloat
    var tutorial: TutorialPlan = TutorialPlan()
    var tutorialMessage: String? = nil
    var onTutorialEvent: (TutorialEvent) -> Void = { _ in }
    var isRescueHeartDue: Bool = false
    var onRescueHeartPlaced: () -> Void = {}
    var onLifeHeartCollected: (CGPoint) -> Void = { _ in }
    var lifeHeartSize: CGFloat = 22
    let onHit: (UUID, Bool, Bool) -> Bool
    let onSwallow: (Bool) -> Void
    let onDive: () -> Void
    let onFishEntranceComplete: () -> Void
    let onLevelCompletionFinished: () -> Void

    @State private var motionOffset = CGSize.zero
    @State private var completionOffset = CGSize.zero
    @State private var lionScale: CGFloat = 1
    @State private var lionOpacity = 1.0
    @State private var motionPhase: LionMotionPhase = .idle
    @State private var phaseStarted = Date()
    @State private var actionRotation = 0.0
    @State private var idleRotationOffset = 0.0
    @State private var driftAmount: CGFloat = 1
    @State private var isMoving = false
    @State private var selectedOptionID: UUID?
    @State private var selectedWasCorrect = false
    @State private var buttonHasContact = false
    @State private var buttonImpactScale: CGFloat = 1
    @State private var actionSequence = 0
    @State private var tutorialSequence = 0

    private var round: GameRound? { rounds.first }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(size: proxy.size,
                                  topReserve: topReserve,
                                  bottomReserve: bottomReserve,
                                  isPad: isPad)
            ZStack {
                SpaceBackdrop(accent: character.color,
                              deep: character.deepColor,
                              isRunning: isRunning && !reduceMotion)

                if let round {
                    questionBadge(round.question.prompt, metrics: metrics)

                    ForEach(Array(round.options.prefix(8).enumerated()), id: \.element.id) { index, option in
                        answerButton(option,
                                     at: metrics.answerPoints[index],
                                     centre: metrics.centre,
                                     size: metrics.answerSize,
                                     lionSize: metrics.lionSize)
                    }
                }

                lion(metrics: metrics)

                if let tutorialMessage, tutorial.isRunning {
                    Text(tutorialMessage)
                        .font(.system(size: isPad ? 22 : 15, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, isPad ? 24 : 16)
                        .padding(.vertical, isPad ? 14 : 10)
                        .background(.black.opacity(0.68), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1.5))
                        .frame(maxWidth: metrics.size.width * 0.54)
                        .position(x: metrics.centre.x,
                                  y: metrics.size.height * 0.79)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                if playsFishEntrance { beginEntrance() }
                progressTutorial(tutorial.step)
            }
            .onChange(of: playsFishEntrance) { _, value in
                if value { beginEntrance() }
            }
            .onChange(of: playsLevelCompletion) { _, value in
                if value { beginCompletion(width: metrics.size.width) }
            }
            .onChange(of: tutorial.step) { _, step in
                progressTutorial(step)
            }
        }
        .ignoresSafeArea()
    }

    private func questionBadge(_ prompt: String, metrics: Metrics) -> some View {
        Text(prompt)
            .font(.system(size: metrics.questionFontSize, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, metrics.answerSize * 0.42)
            .padding(.vertical, metrics.answerSize * 0.13)
            .background {
                Capsule()
                    .fill(.black.opacity(0.48))
                    .overlay(Capsule().stroke(.white.opacity(0.60), lineWidth: 2))
                    .shadow(color: character.color.opacity(0.58), radius: 13)
            }
            .frame(maxWidth: metrics.size.width * 0.46)
            .position(x: metrics.centre.x, y: metrics.questionY)
            .accessibilityIdentifier("space-lion-question")
    }

    private func answerButton(_ option: AnswerOption,
                              at point: CGPoint,
                              centre: CGPoint,
                              size: CGFloat,
                              lionSize: CGFloat) -> some View {
        let isSelected = selectedOptionID == option.id
        let showsFeedback = isSelected && buttonHasContact
        let feedback: HoopFeedback = {
            guard showsFeedback else { return .none }
            return selectedWasCorrect ? .correct : .wrong
        }()
        // Depress the arcade cap while the lion is pressing into it.
        let isPressed = isSelected && (buttonHasContact || buttonImpactScale < 0.98)
        return Button {
            select(option,
                   at: point,
                   from: centre,
                   buttonSize: size,
                   lionSize: lionSize)
        } label: {
            AnswerHoop(text: option.text,
                       tint: character.color,
                       size: size,
                       textScale: 1,
                       feedback: feedback,
                       isPressed: isPressed)
                .scaleEffect(isSelected ? buttonImpactScale : 1)
        }
        .buttonStyle(.plain)
        .position(point)
        .disabled(!isLive || isMoving || tutorial.isRunning || playsLevelCompletion)
        .accessibilityIdentifier("space-lion-answer-\(option.text)")
    }

    private func lion(metrics: Metrics) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: !isRunning || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let driftX = reduceMotion
                ? 0
                : sin(time * 0.62) * metrics.lionSize * 0.075 * driftAmount
            let driftY = reduceMotion
                ? 0
                : cos(time * 0.78) * metrics.lionSize * 0.062 * driftAmount
            let rotation = isMoving
                ? actionRotation
                : idleRotation(at: timeline.date)
            let frameName = lionFrameName(at: timeline.date)

            Group {
                if frameName == "1.5" {
                    // Frame 1.5 is the clean, fully extended pointing pose.
                    // Keep its complete hand visible: its fingertip is what is
                    // positioned against the answer button below.
                    lionImage(frameName, size: metrics.lionSize)
                } else {
                    ZStack { lionImage(frameName, size: metrics.lionSize) }
                        // The other supplied frames contain a sliver of a
                        // neighbouring sprite at one edge.
                        .frame(width: metrics.lionSize * 0.84,
                               height: metrics.lionSize)
                        .clipped()
                }
            }
                .frame(width: metrics.lionSize, height: metrics.lionSize)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(lionScale)
                .opacity(lionOpacity)
                .offset(x: motionOffset.width + completionOffset.width + driftX,
                        y: motionOffset.height + completionOffset.height + driftY)
                .position(metrics.centre)
                .shadow(color: character.color.opacity(0.42), radius: 18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func lionImage(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func lionFrameName(at date: Date) -> String {
        let elapsed = max(0, date.timeIntervalSince(phaseStarted))
        switch motionPhase {
        case .idle, .orientingOut:
            return "1.1"
        case .travellingOut:
            // Exactly one extension: tuck, reach, point, then hold the fully
            // extended finger for the rest of the glide. Never loop here.
            let frames = ["1.2", "1.3", "1.4", "1.5"]
            return frames[min(frames.count - 1, Int(elapsed / 0.12))]
        case .contact:
            return "1.5"
        case .pushingOff:
            // Retract once while the finger is against the button. This reads
            // as a push-off instead of replaying the forward reach animation.
            let frames = ["1.5", "1.4", "1.3", "1.2"]
            return frames[min(frames.count - 1, Int(elapsed / 0.045))]
        case .travellingHome:
            return "1.2"
        case .settling:
            let frames = ["1.6", "1.7", "1.8"]
            return frames[min(frames.count - 1, Int(elapsed / 0.11))]
        }
    }

    private func select(_ option: AnswerOption,
                        at target: CGPoint,
                        from centre: CGPoint,
                        buttonSize: CGFloat,
                        lionSize: CGFloat) {
        guard isLive, !isMoving, !tutorial.isRunning, let round,
              round.options.contains(where: { $0.id == option.id }) else { return }
        actionSequence &+= 1
        let token = actionSequence
        let now = Date()
        isMoving = true
        motionPhase = .orientingOut
        phaseStarted = now
        selectedOptionID = option.id
        selectedWasCorrect = option.isCorrect
        buttonHasContact = false
        buttonImpactScale = 1

        let dx = target.x - centre.x
        let dy = target.y - centre.y
        let distance = max(1, hypot(dx, dy))
        let unitX = dx / distance
        let unitY = dy / distance
        let fingerReach = lionSize * 0.44
        let buttonRadius = buttonSize * 0.50
        let centreDistance = min(distance, fingerReach + buttonRadius)
        let destination = CGSize(width: dx - unitX * centreDistance,
                                 height: dy - unitY * centreDistance)
        let pressDepth = min(buttonSize * 0.10, lionSize * 0.055)
        let pressedDestination = CGSize(width: destination.width + unitX * pressDepth,
                                        height: destination.height + unitY * pressDepth)

        let travelAngle = atan2(dy, dx) * 180 / .pi
        let currentRotation = idleRotation(at: now)
        actionRotation = currentRotation
        let outwardAngle = nearestEquivalent(of: travelAngle, to: currentRotation)

        withAnimation(.easeInOut(duration: orientDuration)) {
            actionRotation = outwardAngle
            driftAmount = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + orientDuration) {
            guard actionSequence == token else { return }
            guard isLive, isRunning else {
                cancelAction(token: token)
                return
            }
            beginOutwardTravel(option,
                                destination: destination,
                                pressedDestination: pressedDestination,
                                token: token)
        }
    }

    private var orientDuration: Double { reduceMotion ? 0.10 : 0.42 }
    private var outwardDuration: Double { reduceMotion ? 0.20 : 0.98 }
    private var pressDuration: Double { reduceMotion ? 0.04 : 0.055 }
    private var pushOffDuration: Double { reduceMotion ? 0.08 : 0.18 }
    // Together, push-off and glide take exactly as long as the outward trip.
    private var returnDuration: Double { outwardDuration - pushOffDuration }
    private var settleDuration: Double { reduceMotion ? 0.06 : 0.18 }

    private func beginOutwardTravel(_ option: AnswerOption,
                                     destination: CGSize,
                                     pressedDestination: CGSize,
                                     token: Int) {
        motionPhase = .travellingOut
        phaseStarted = Date()
        // Ease into the flight, then keep meaningful velocity all the way to
        // the button. The former curve had a zero end velocity, which made the
        // final stretch visibly crawl despite a very fast first half.
        withAnimation(.timingCurve(0.30, 0.04, 0.70, 0.70,
                                   duration: outwardDuration)) {
            motionOffset = destination
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + outwardDuration) {
            guard actionSequence == token else { return }
            guard isLive, isRunning else {
                cancelAction(token: token)
                return
            }
            reachButton(option,
                        pressedDestination: pressedDestination,
                        token: token)
        }
    }

    private func reachButton(_ option: AnswerOption,
                             pressedDestination: CGSize,
                             token: Int) {
        motionPhase = .contact
        phaseStarted = Date()
        buttonHasContact = true
        AppAudio.shared.playButtonPress()
        let accepted = onHit(option.id, false, false)
        if accepted { onSwallow(option.isCorrect) }

        // Load the fingertip against the answer before releasing the spring.
        // This makes the return feel powered by the hand contact itself.
        withAnimation(.easeOut(duration: pressDuration)) {
            motionOffset = pressedDestination
            buttonImpactScale = 0.92
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pressDuration) {
            guard actionSequence == token else { return }
            beginPushOff(token: token)
        }
    }

    private func beginPushOff(token: Int) {
        motionPhase = .pushingOff
        phaseStarted = Date()
        // One continuous recoil avoids a velocity reset between push-off and
        // the glide home. The phase change below now affects only the pose.
        // This is the exact time-reverse of the outward timing curve. The lion
        // therefore leaves the button at its arrival speed and covers the same
        // distance home in the same amount of time.
        let recoilAnimation: Animation = reduceMotion
            ? .linear(duration: pushOffDuration + returnDuration)
            : .timingCurve(0.30, 0.30, 0.70, 0.96,
                           duration: pushOffDuration + returnDuration)
        let buttonAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.22, dampingFraction: 0.52)
        withAnimation(recoilAnimation) {
            motionOffset = .zero
        }
        withAnimation(buttonAnimation) {
            buttonImpactScale = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pushOffDuration) {
            guard actionSequence == token else { return }
            beginReturn(token: token)
        }
    }

    private func beginReturn(token: Int) {
        motionPhase = .travellingHome
        phaseStarted = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + returnDuration) {
            guard actionSequence == token else { return }
            beginSettling(token: token)
        }
    }

    private func beginSettling(token: Int) {
        motionPhase = .settling
        phaseStarted = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDuration) {
            guard actionSequence == token else { return }
            finishAction()
        }
    }

    private func nearestEquivalent(of angle: Double, to reference: Double) -> Double {
        var difference = (angle - reference).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return reference + difference
    }

    private func rawIdleRotation(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        let time = date.timeIntervalSinceReferenceDate
        let tumblePhase = time.truncatingRemainder(dividingBy: 28) / 28
        return tumblePhase * 360 + sin(time * 0.31) * 13
    }

    private func idleRotation(at date: Date) -> Double {
        rawIdleRotation(at: date) + idleRotationOffset
    }

    private func finishAction() {
        let now = Date()
        idleRotationOffset = actionRotation - rawIdleRotation(at: now)
        motionPhase = .idle
        phaseStarted = now
        selectedOptionID = nil
        buttonHasContact = false
        buttonImpactScale = 1
        isMoving = false
        withAnimation(.easeInOut(duration: reduceMotion ? 0.08 : 0.28)) {
            driftAmount = 1
        }
    }

    private func cancelAction(token: Int) {
        guard actionSequence == token else { return }
        withAnimation(.easeOut(duration: 0.18)) { motionOffset = .zero }
        finishAction()
    }

    private func beginEntrance() {
        actionSequence &+= 1
        isMoving = false
        motionPhase = .idle
        phaseStarted = Date()
        driftAmount = 1
        motionOffset = .zero
        completionOffset = .zero
        lionScale = reduceMotion ? 1 : 0.68
        lionOpacity = 0
        withAnimation(.spring(response: reduceMotion ? 0.18 : 0.58,
                              dampingFraction: 0.72)) {
            lionScale = 1
            lionOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.20 : 0.62)) {
            onFishEntranceComplete()
        }
    }

    private func beginCompletion(width: CGFloat) {
        actionSequence &+= 1
        let now = Date()
        isMoving = true
        motionPhase = .travellingOut
        phaseStarted = now
        actionRotation = idleRotation(at: now)
        driftAmount = 0
        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : 0.82)) {
            completionOffset = CGSize(width: width * 0.72, height: -width * 0.10)
            lionScale = 0.78
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.22 : 0.88)) {
            onLevelCompletionFinished()
        }
    }

    /// The inherited tutorial describes the old flight controls. Let its
    /// existing cards advance as a short, non-blocking introduction while the
    /// new tap controls remain self-evident.
    private func progressTutorial(_ step: TutorialStep?) {
        tutorialSequence &+= 1
        let token = tutorialSequence
        guard let step else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            guard tutorialSequence == token else { return }
            switch step {
            case .dragToFly:
                onTutorialEvent(.draggedLow)
                onTutorialEvent(.draggedHigh)
            case .tapToFly:
                onTutorialEvent(.tappedBelow)
                onTutorialEvent(.tappedAbove)
            case .diveUnder:
                onTutorialEvent(.passedUnderSet)
            case .correctHoop:
                onTutorialEvent(.passedCorrectHoop(withTurbo: false))
            case .turbo:
                onTutorialEvent(.passedCorrectHoop(withTurbo: true))
            case .wrongHoop:
                onTutorialEvent(.passedCorrectHoop(withTurbo: false))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard tutorialSequence == token else { return }
                    onTutorialEvent(.passedCorrectHoop(withTurbo: false))
                }
            case .goodLuck:
                break
            }
        }
    }
}

private extension SpaceLionPlayfield {
    struct Metrics {
        let size: CGSize
        let topReserve: CGFloat
        let bottomReserve: CGFloat
        let isPad: Bool

        var answerSize: CGFloat {
            min(isPad ? 90 : 70, max(isPad ? 72 : 54, size.height * 0.125))
        }
        var lionSize: CGFloat { min(size.width * 0.24, size.height * (isPad ? 0.37 : 0.39)) }
        var centre: CGPoint { CGPoint(x: size.width * 0.5, y: size.height * 0.54) }
        var questionY: CGFloat { max(34, topReserve * 0.52) }
        var questionFontSize: CGFloat { isPad ? 38 : max(24, size.height * 0.058) }

        /// Eight seats on the screen rim. Centres sit just inside the edge so
        /// the authored button canvases' visible metal housing meets the rim.
        var answerPoints: [CGPoint] {
            let inset = answerSize * 0.47
            let topY = max(topReserve + answerSize * 0.48, inset)
            let bottomY = min(size.height - bottomReserve - answerSize * 0.48,
                              size.height - inset)
            let upperSideY = size.height * 0.40
            let lowerSideY = size.height * 0.68
            let topXLeft = size.width * 0.32
            let topXRight = size.width * 0.68
            return [
                CGPoint(x: topXLeft, y: topY),
                CGPoint(x: topXRight, y: topY),
                CGPoint(x: size.width - inset, y: upperSideY),
                CGPoint(x: size.width - inset, y: lowerSideY),
                CGPoint(x: topXRight, y: bottomY),
                CGPoint(x: topXLeft, y: bottomY),
                CGPoint(x: inset, y: lowerSideY),
                CGPoint(x: inset, y: upperSideY)
            ]
        }
    }
}

private struct SpaceBackdrop: View {
    let accent: Color
    let deep: Color
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(
                                Gradient(colors: [Color(red: 0.025, green: 0.035, blue: 0.15),
                                                  Color(red: 0.10, green: 0.045, blue: 0.22),
                                                  Color(red: 0.015, green: 0.08, blue: 0.18)]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: size.width, y: size.height)))

                for index in 0..<96 {
                    let x = CGFloat((index * 73 + 19) % 101) / 101 * size.width
                    let y = CGFloat((index * 47 + 11) % 97) / 97 * size.height
                    let twinkle = 0.42 + 0.48 * (sin(time * 1.25 + Double(index)) + 1) * 0.5
                    let radius = CGFloat(index % 4 == 0 ? 2.0 : 1.1)
                    context.opacity = twinkle
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y,
                                                        width: radius * 2,
                                                        height: radius * 2)),
                                 with: .color(.white))
                }
                context.opacity = 1

                let planet = CGRect(x: size.width * 0.76,
                                    y: size.height * 0.70,
                                    width: size.height * 0.30,
                                    height: size.height * 0.30)
                context.fill(Path(ellipseIn: planet),
                             with: .radialGradient(
                                Gradient(colors: [accent.opacity(0.75), deep.opacity(0.72)]),
                                center: CGPoint(x: planet.midX - planet.width * 0.18,
                                                y: planet.midY - planet.height * 0.22),
                                startRadius: 2,
                                endRadius: planet.width * 0.62))
            }
        }
        .overlay {
            LinearGradient(colors: [.clear, accent.opacity(0.09), .clear],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
