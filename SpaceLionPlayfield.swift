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
    let character: AnimalCharacter
    let isPad: Bool
    let isLive: Bool
    let isRunning: Bool
    let playsFishEntrance: Bool
    let playsLevelCompletion: Bool
    let reduceMotion: Bool
    let topReserve: CGFloat
    let bottomReserve: CGFloat
    let leftReserve: CGFloat
    let rightReserve: CGFloat
    var tutorial: TutorialPlan = TutorialPlan()
    var tutorialMessage: String? = nil
    var onTutorialEvent: (TutorialEvent) -> Void = { _ in }
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
                                  leftReserve: leftReserve,
                                  rightReserve: rightReserve,
                                  isPad: isPad)
            ZStack {
                SpaceshipCockpit(accent: character.color,
                                 deep: character.deepColor,
                                 topReserve: topReserve,
                                 isRunning: isRunning && !reduceMotion)

                if let round {
                    ForEach(Array(round.options.prefix(8).enumerated()), id: \.element.id) { index, option in
                        answerButton(option,
                                     at: metrics.answerPoints[index],
                                     orientation: metrics.answerOrientations[index],
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

    private func answerButton(_ option: AnswerOption,
                              at point: CGPoint,
                              orientation: Double,
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
            SpaceConsoleButton(text: option.text,
                               size: size,
                               feedback: feedback,
                               isPressed: isPressed,
                               orientationDegrees: orientation)
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
        let leftReserve: CGFloat
        let rightReserve: CGFloat
        let isPad: Bool

        var answerSize: CGFloat {
            min(isPad ? 164 : 126,
                max(isPad ? 132 : 100, size.height * (isPad ? 0.23 : 0.27)))
        }
        var lionSize: CGFloat { min(size.width * 0.23, size.height * (isPad ? 0.35 : 0.38)) }
        var centre: CGPoint { CGPoint(x: size.width * 0.5, y: size.height * 0.55) }

        /// Six controls live in the side columns and two in the lower console,
        /// matching the cockpit's construction instead of floating in space.
        var answerPoints: [CGPoint] {
            let leftX = max(answerSize * 0.54,
                            leftReserve + answerSize * 0.54)
            let rightX = min(size.width - answerSize * 0.54,
                             size.width - rightReserve - answerSize * 0.54)
            let topY = max(topReserve + answerSize * 0.46,
                           size.height * 0.34)
            let lowerY = size.height - bottomReserve - answerSize * 0.53
            let middleY = (topY + lowerY) / 2
            let consoleY = min(size.height - bottomReserve - answerSize * 0.43,
                               size.height * 0.86)
            return [
                CGPoint(x: leftX, y: topY),
                CGPoint(x: rightX, y: topY),
                CGPoint(x: leftX, y: middleY),
                CGPoint(x: rightX, y: middleY),
                CGPoint(x: leftX, y: lowerY),
                CGPoint(x: rightX, y: lowerY),
                CGPoint(x: size.width * 0.38, y: consoleY),
                CGPoint(x: size.width * 0.62, y: consoleY)
            ]
        }

        /// The housing follows the surface it is bolted to: overhead controls
        /// face down, side controls face inward and console controls face up.
        /// SpaceConsoleButton counter-rotates its number so every value stays upright.
        var answerOrientations: [Double] {
            [-90, 90, -90, 90, -90, 90, 0, 0]
        }
    }
}

/// A cockpit control built entirely from vector shapes. Its octagonal mounting
/// plate turns with the wall it belongs to, while the answer remains upright.
private struct SpaceConsoleButton: View {
    let text: String
    let size: CGFloat
    let feedback: HoopFeedback
    let isPressed: Bool
    let orientationDegrees: Double

    private let cyan = Color(red: 0.00, green: 0.78, blue: 1.00)
    private let electricBlue = Color(red: 0.06, green: 0.28, blue: 0.92)
    private let orange = Color(red: 1.00, green: 0.54, blue: 0.08)

    private var lightColor: Color {
        switch feedback {
        case .correct, .revealedCorrect, .bonus:
            return Color(red: 0.12, green: 0.92, blue: 0.46)
        case .wrong:
            return Color(red: 1.00, green: 0.18, blue: 0.30)
        case .bypassed:
            return .cyan
        case .none, .inactive:
            return cyan
        }
    }

    var body: some View {
        ZStack {
            SpaceModuleShape(cut: size * 0.18)
                .fill(LinearGradient(
                    colors: [Color(red: 0.16, green: 0.24, blue: 0.44),
                             Color(red: 0.045, green: 0.075, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    SpaceModuleShape(cut: size * 0.18)
                        .stroke(Color(red: 0.015, green: 0.025, blue: 0.07),
                                lineWidth: size * 0.075)
                }
                .overlay {
                    SpaceModuleShape(cut: size * 0.18)
                        .stroke(electricBlue.opacity(0.75), lineWidth: size * 0.022)
                        .padding(size * 0.075)
                }

            Circle()
                .fill(Color(red: 0.015, green: 0.04, blue: 0.11))
                .padding(size * 0.145)
                .overlay {
                    Circle()
                        .stroke(lightColor.opacity(0.35), lineWidth: size * 0.11)
                        .padding(size * 0.17)
                        .blur(radius: size * 0.035)
                }
                .overlay {
                    Circle()
                        .stroke(lightColor, lineWidth: size * 0.038)
                        .padding(size * 0.17)
                }

            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.90),
                             lightColor,
                             electricBlue],
                    center: .topLeading,
                    startRadius: 1,
                    endRadius: size * 0.43
                ))
                .padding(size * (isPressed ? 0.245 : 0.215))
                .offset(y: isPressed ? size * 0.035 : 0)
                .shadow(color: lightColor.opacity(0.85), radius: size * 0.10)

            Capsule()
                .fill(orange)
                .frame(width: size * 0.30, height: size * 0.045)
                .offset(y: -size * 0.42)
                .shadow(color: orange.opacity(0.80), radius: size * 0.035)

            Text(text)
                .font(.system(size: size * 0.29, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.01, green: 0.08, blue: 0.20))
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .frame(width: size * 0.48, height: size * 0.32)
                .shadow(color: .white.opacity(0.55), radius: 0.5, y: 1)
                .rotationEffect(.degrees(-orientationDegrees))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(orientationDegrees))
        .opacity(feedback == .inactive ? 0.55 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isPressed)
        .animation(.easeInOut(duration: 0.24), value: feedback)
        .contentShape(SpaceModuleShape(cut: size * 0.18))
    }
}

private struct SpaceModuleShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) * 0.28)
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

private struct SpaceshipCockpit: View {
    let accent: Color
    let deep: Color
    let topReserve: CGFloat
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawCockpit(in: context, size: size, time: time)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func drawCockpit(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
                let cyan = Color(red: 0.00, green: 0.72, blue: 1.00)
                let blue = Color(red: 0.055, green: 0.24, blue: 0.72)
                let orange = Color(red: 1.00, green: 0.52, blue: 0.07)
                let hullLight = Color(red: 0.15, green: 0.22, blue: 0.40)
                let hullDark = Color(red: 0.018, green: 0.035, blue: 0.09)
                let roofHeight = max(topReserve * 0.94, size.height * 0.18)
                let windowRect = CGRect(x: size.width * 0.145,
                                        y: roofHeight + size.height * 0.018,
                                        width: size.width * 0.71,
                                        height: size.height * 0.57)
                let window = chamferedPath(in: windowRect,
                                           cut: min(size.width * 0.035,
                                                    size.height * 0.07))

                // One solid hull first; every later seam and inset therefore
                // reads as part of the same ship rather than separate cards.
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(
                                Gradient(colors: [hullLight, hullDark, .black]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: size.width, y: size.height)))

                // Recess the windshield deeply into the hull before drawing
                // what is outside it.
                context.stroke(window, with: .color(.black.opacity(0.88)), lineWidth: 42)
                context.stroke(window, with: .color(blue.opacity(0.58)), lineWidth: 30)
                context.stroke(window, with: .color(hullDark), lineWidth: 20)

                context.drawLayer { space in
                    space.clip(to: window)
                    space.fill(Path(windowRect),
                               with: .linearGradient(
                                Gradient(colors: [Color(red: 0.005, green: 0.015, blue: 0.09),
                                                  Color(red: 0.01, green: 0.025, blue: 0.20),
                                                  Color(red: 0.055, green: 0.015, blue: 0.16)]),
                                startPoint: CGPoint(x: windowRect.minX, y: windowRect.minY),
                                endPoint: CGPoint(x: windowRect.maxX, y: windowRect.maxY)))

                    // A soft galaxy band, constructed from translucent paths.
                    for band in 0..<5 {
                        var galaxy = Path()
                        let offset = CGFloat(band) * 7
                        galaxy.move(to: CGPoint(x: windowRect.minX - 20,
                                                y: windowRect.maxY - offset))
                        galaxy.addCurve(to: CGPoint(x: windowRect.maxX + 30,
                                                    y: windowRect.minY + offset * 0.55),
                                        control1: CGPoint(x: windowRect.midX * 0.72,
                                                          y: windowRect.midY + 40 - offset),
                                        control2: CGPoint(x: windowRect.midX * 1.34,
                                                          y: windowRect.midY - 50 + offset))
                        space.stroke(galaxy,
                                     with: .color(Color(red: 0.28, green: 0.18, blue: 0.85)
                                        .opacity(0.08 + Double(band) * 0.025)),
                                     lineWidth: 9 + CGFloat(band) * 3)
                    }

                    let starTravel = CGFloat(time.truncatingRemainder(dividingBy: 24)) / 24
                    for index in 0..<142 {
                        let baseX = CGFloat((index * 79 + 17) % 149) / 149
                        let shifted = (baseX - starTravel * (index.isMultiple(of: 4) ? 0.20 : 0.10) + 1)
                            .truncatingRemainder(dividingBy: 1)
                        let x = windowRect.minX + shifted * windowRect.width
                        let y = windowRect.minY
                            + CGFloat((index * 53 + 7) % 137) / 137 * windowRect.height
                        let pulse = 0.45 + (sin(time * 1.1 + Double(index)) + 1) * 0.24
                        let radius = CGFloat(index.isMultiple(of: 13) ? 2.1 : (index.isMultiple(of: 4) ? 1.25 : 0.75))
                        space.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                         width: radius * 2,
                                                         height: radius * 2)),
                                   with: .color((index.isMultiple(of: 5) ? cyan : .white)
                                    .opacity(pulse)))
                        if index.isMultiple(of: 17) {
                            var sparkle = Path()
                            sparkle.move(to: CGPoint(x: x - radius * 3.2, y: y))
                            sparkle.addLine(to: CGPoint(x: x + radius * 3.2, y: y))
                            sparkle.move(to: CGPoint(x: x, y: y - radius * 3.2))
                            sparkle.addLine(to: CGPoint(x: x, y: y + radius * 3.2))
                            space.stroke(sparkle, with: .color(.white.opacity(0.72)), lineWidth: 0.8)
                        }
                    }
                    // A large moving planet sits partly below the window edge.
                    let orbit = CGFloat(time.truncatingRemainder(dividingBy: 88)) / 88
                    let planetSide = size.height * 0.55
                    let planet = CGRect(x: windowRect.maxX - planetSide * (0.68 + orbit * 0.34),
                                        y: windowRect.maxY - planetSide * 0.31,
                                        width: planetSide,
                                        height: planetSide)
                    space.fill(Path(ellipseIn: planet),
                               with: .radialGradient(
                                Gradient(colors: [.white.opacity(0.96),
                                                  cyan,
                                                  Color(red: 0.02, green: 0.18, blue: 0.72),
                                                  Color(red: 0.005, green: 0.03, blue: 0.16)]),
                                center: CGPoint(x: planet.midX - planet.width * 0.20,
                                                y: planet.midY - planet.height * 0.22),
                                startRadius: 1,
                                endRadius: planet.width * 0.61))
                    space.stroke(Path(ellipseIn: planet.insetBy(dx: -3, dy: -3)),
                                 with: .color(cyan.opacity(0.75)), lineWidth: 5)

                    // Windshield tint and reflected light.
                    space.fill(Path(windowRect),
                               with: .linearGradient(
                                Gradient(colors: [cyan.opacity(0.08), .clear, accent.opacity(0.05)]),
                                startPoint: CGPoint(x: windowRect.minX, y: windowRect.minY),
                                endPoint: CGPoint(x: windowRect.maxX, y: windowRect.maxY)))
                }

                // Four nested rails give the opening the depth and blue/orange
                // rhythm of a real illuminated frame.
                context.stroke(window, with: .color(blue), lineWidth: 14)
                context.stroke(window, with: .color(orange), lineWidth: 7)
                context.stroke(window, with: .color(cyan), lineWidth: 3)
                context.stroke(chamferedPath(in: windowRect.insetBy(dx: 7, dy: 7),
                                             cut: min(size.width * 0.029, size.height * 0.058)),
                               with: .color(.white.opacity(0.24)), lineWidth: 1.2)

                // Upper hull plates and ribs.
                for row in 0..<3 {
                    let y = roofHeight * (0.28 + CGFloat(row) * 0.22)
                    var seam = Path()
                    seam.move(to: CGPoint(x: size.width * 0.10, y: y))
                    seam.addLine(to: CGPoint(x: size.width * 0.90, y: y))
                    context.stroke(seam, with: .color(.black.opacity(0.48)), lineWidth: 2)
                    context.stroke(seam, with: .color(blue.opacity(0.24)), lineWidth: 0.8)
                }

                let leftRibX = windowRect.minX - size.width * 0.025
                let rightRibX = windowRect.maxX + size.width * 0.025
                for x in [leftRibX, rightRibX] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: x, y: roofHeight * 0.25))
                    rib.addLine(to: CGPoint(x: x, y: windowRect.maxY + size.height * 0.04))
                    context.stroke(rib, with: .color(.black.opacity(0.62)), lineWidth: 9)
                    context.stroke(rib, with: .color(blue.opacity(0.55)), lineWidth: 3)
                }

                // Floor/console in perspective, including concentric centre
                // rings and converging plate seams.
                let floorTop = windowRect.maxY + size.height * 0.025
                var floorLip = Path()
                floorLip.move(to: CGPoint(x: size.width * 0.08, y: size.height))
                floorLip.addLine(to: CGPoint(x: size.width * 0.20, y: floorTop))
                floorLip.addLine(to: CGPoint(x: size.width * 0.80, y: floorTop))
                floorLip.addLine(to: CGPoint(x: size.width * 0.92, y: size.height))
                floorLip.closeSubpath()
                context.fill(floorLip,
                             with: .linearGradient(
                                Gradient(colors: [hullLight.opacity(0.90), hullDark]),
                                startPoint: CGPoint(x: 0, y: floorTop),
                                endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(floorLip, with: .color(blue.opacity(0.72)), lineWidth: 3)
                context.stroke(floorLip, with: .color(orange.opacity(0.72)), lineWidth: 1.3)

                for fraction in stride(from: CGFloat(0.18), through: 0.82, by: 0.16) {
                    var seam = Path()
                    seam.move(to: CGPoint(x: size.width * fraction, y: size.height))
                    seam.addLine(to: CGPoint(x: size.width * 0.5
                                              + (fraction - 0.5) * size.width * 0.28,
                                              y: floorTop))
                    context.stroke(seam, with: .color(blue.opacity(0.25)), lineWidth: 1.2)
                }

                let ringRect = CGRect(x: size.width * 0.38,
                                      y: size.height * 0.88,
                                      width: size.width * 0.24,
                                      height: size.height * 0.20)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.black.opacity(0.75)), lineWidth: 15)
                context.stroke(Path(ellipseIn: ringRect), with: .color(blue.opacity(0.80)), lineWidth: 7)
                context.stroke(Path(ellipseIn: ringRect.insetBy(dx: 9, dy: 7)),
                               with: .color(cyan.opacity(0.68)), lineWidth: 2.5)

                // Repeated light bars unify roof, side columns and console.
                for center in [CGPoint(x: size.width * 0.34, y: roofHeight * 0.72),
                               CGPoint(x: size.width * 0.66, y: roofHeight * 0.72)] {
                    drawLightBar(in: context, center: center,
                                 length: size.width * 0.14, thickness: 5,
                                 color: cyan, horizontal: true)
                }
                for y in [size.height * 0.31, size.height * 0.63] {
                    drawLightBar(in: context,
                                 center: CGPoint(x: size.width * 0.105, y: y),
                                 length: size.height * 0.10, thickness: 4,
                                 color: cyan, horizontal: false)
                    drawLightBar(in: context,
                                 center: CGPoint(x: size.width * 0.895, y: y),
                                 length: size.height * 0.10, thickness: 4,
                                 color: cyan, horizontal: false)
                }
                for x in [size.width * 0.22, size.width * 0.50, size.width * 0.78] {
                    drawLightBar(in: context,
                                 center: CGPoint(x: x, y: size.height * 0.965),
                                 length: size.width * 0.09, thickness: 4,
                                 color: cyan, horizontal: true)
                }

                // Rivets and small orange status lamps keep the large surfaces
                // from reading as flat gradients.
                for index in 0..<18 {
                    let x = size.width * (0.035 + CGFloat(index % 9) * 0.116)
                    let y = index < 9 ? roofHeight * 0.16 : size.height * 0.955
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.7, y: y - 1.7,
                                                        width: 3.4, height: 3.4)),
                                 with: .color(.white.opacity(0.28)))
                }
                drawLightBar(in: context,
                             center: CGPoint(x: size.width * 0.055, y: roofHeight * 0.38),
                             length: size.width * 0.036, thickness: 4,
                             color: orange, horizontal: true)
                drawLightBar(in: context,
                             center: CGPoint(x: size.width * 0.945, y: roofHeight * 0.38),
                             length: size.width * 0.036, thickness: 4,
                             color: orange, horizontal: true)
    }

    private func chamferedPath(in rect: CGRect, cut: CGFloat) -> Path {
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

    private func drawLightBar(in context: GraphicsContext,
                              center: CGPoint,
                              length: CGFloat,
                              thickness: CGFloat,
                              color: Color,
                              horizontal: Bool) {
        let outer = horizontal
            ? CGRect(x: center.x - length / 2, y: center.y - thickness,
                     width: length, height: thickness * 2)
            : CGRect(x: center.x - thickness, y: center.y - length / 2,
                     width: thickness * 2, height: length)
        let inner = outer.insetBy(dx: horizontal ? 2 : 1,
                                  dy: horizontal ? 1 : 2)
        context.fill(Path(roundedRect: outer, cornerRadius: thickness),
                     with: .color(color.opacity(0.20)))
        context.fill(Path(roundedRect: inner, cornerRadius: thickness),
                     with: .color(color.opacity(0.95)))
    }
}
