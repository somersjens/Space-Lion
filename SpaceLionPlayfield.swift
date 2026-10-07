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

private struct SpaceAnswerBurstState: Identifiable {
    let id = UUID()
    let point: CGPoint
    let isCorrect: Bool
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
    @State private var feedbackBurst: SpaceAnswerBurstState?
    @State private var actionSequence = 0
    @State private var tutorialSequence = 0
    /// Extra spin layered on the travel pose. A correct answer flips the lion
    /// once on the way home; the value is cleared only when it is a full turn.
    @State private var celebrationSpin = 0.0

    private var round: GameRound? { rounds.first }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(size: proxy.size,
                                  topReserve: topReserve,
                                  bottomReserve: bottomReserve,
                                  leftReserve: leftReserve,
                                  rightReserve: rightReserve,
                                  isPad: isPad)
            let cockpitFeedbacks = round.map {
                $0.options.prefix(GameConfig.answerBubbleCount).map(feedback(for:))
            } ?? []
            ZStack {
                SpaceshipCockpit(layout: metrics.cockpit,
                                 character: character,
                                 isPad: isPad,
                                 isRunning: isRunning && !reduceMotion,
                                 feedbacks: cockpitFeedbacks)

                if let round {
                    let answers = Array(round.options.prefix(GameConfig.answerBubbleCount))
                    ForEach(Array(answers.enumerated()), id: \.element.id) { index, option in
                        answerButton(option,
                                     index: index,
                                     at: metrics.answerPoints[index],
                                     centre: metrics.centre,
                                     size: metrics.answerSize,
                                     lionSize: metrics.lionSize)
                    }
                }

                if let feedbackBurst {
                    SpaceAnswerBurst(burst: feedbackBurst,
                                     size: metrics.answerSize * 1.55,
                                     reduceMotion: reduceMotion)
                        .id(feedbackBurst.id)
                        .position(feedbackBurst.point)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                lion(metrics: metrics)

                if playsLevelCompletion {
                    VictoryBloom(size: metrics.cockpit.windowRect.width * 0.55,
                                 reduceMotion: reduceMotion)
                        .position(metrics.centre)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                SpaceViewportGlass(window: metrics.cockpit.windowRect,
                                   cut: min(metrics.cockpit.windowRect.width,
                                            metrics.cockpit.windowRect.height) * 0.11,
                                   isRunning: isRunning && !reduceMotion)

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
                              index: Int,
                              at point: CGPoint,
                              centre: CGPoint,
                              size: CGFloat,
                              lionSize: CGFloat) -> some View {
        let isSelected = selectedOptionID == option.id
        let feedback = feedback(for: option)
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
                               isPressed: isPressed)
        }
        .buttonStyle(SpaceAnswerPressStyle())
        .hoverEffect(.highlight)
        .position(point)
        .disabled(!isLive || isMoving || tutorial.isRunning || playsLevelCompletion)
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        .accessibilityLabel(Text(verbatim: option.text))
        .accessibilityHint(Text(verbatim: "Answer \(index + 1)"))
        .accessibilityIdentifier("space-lion-answer-\(option.text)")
        .transition(.opacity.combined(with: .scale(scale: 0.88)))
    }

    private func feedback(for option: AnswerOption) -> HoopFeedback {
        guard selectedOptionID == option.id, buttonHasContact else { return .none }
        return selectedWasCorrect ? .correct : .wrong
    }

    private func lion(metrics: Metrics) -> some View {
        // Pose, drift and the reach frames follow the clock. The flight itself
        // must stay outside that clock: reading `motionOffset` inside the
        // timeline makes SwiftUI drop the in-flight interpolation, so the lion
        // vanishes between roughly a third and two thirds of the trip and then
        // appears further along the path.
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
            let breathe = (reduceMotion || isMoving) ? 1 : (1 + sin(time * 1.35) * 0.022)

            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 0.35, green: 0.75, blue: 1).opacity(0.38),
                                                  .clear],
                                         center: .center,
                                         startRadius: 0,
                                         endRadius: metrics.lionSize * 0.36))
                    .frame(width: metrics.lionSize * 0.78, height: metrics.lionSize * 0.30)
                    .blur(radius: metrics.lionSize * 0.035)
                    .offset(y: metrics.lionSize * 0.30)
                    .allowsHitTesting(false)

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
                .offset(poseAnchor(for: frameName, size: metrics.lionSize))
                .rotationEffect(.degrees(rotation))
                .scaleEffect(breathe)
            }
            .offset(x: driftX, y: driftY)
        }
        .frame(width: metrics.lionSize, height: metrics.lionSize)
        .rotationEffect(.degrees(celebrationSpin))
        .scaleEffect(lionScale)
        .opacity(lionOpacity)
        .offset(x: motionOffset.width + completionOffset.width,
                y: motionOffset.height + completionOffset.height)
        .shadow(color: Color(red: 0.25, green: 0.70, blue: 1).opacity(0.45), radius: 16)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
        .position(metrics.centre)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            // One tuck, then the pointing pose for the rest of the glide.
            // Stepping through every in-between frame shifted the body and
            // read as a hitch along the path.
            return elapsed < 0.18 ? "1.2" : "1.5"
        case .contact, .pushingOff:
            return "1.5"
        case .travellingHome:
            return elapsed < 0.28 ? "1.5" : "1.2"
        case .settling:
            return elapsed < 0.34 ? "1.2" : "1.1"
        }
    }

    /// The supplied poses are not drawn on the same body centre. Nudging each
    /// one onto the pointing pose keeps the lion from stepping sideways every
    /// time the artwork changes. Frame 1.5 stays put: the fingertip reach is
    /// measured from that pose.
    private func poseAnchor(for frame: String, size: CGFloat) -> CGSize {
        let fraction: (CGFloat, CGFloat)
        switch frame {
        case "1.1": fraction = (0.063, -0.055)
        case "1.2": fraction = (0.101, -0.050)
        case "1.3": fraction = (0.146, -0.069)
        case "1.4": fraction = (0.096, -0.062)
        case "1.6": fraction = (-0.012, 0.001)
        case "1.7": fraction = (0.039, -0.003)
        case "1.8": fraction = (0.074, -0.007)
        default: fraction = (0, 0)
        }
        return CGSize(width: fraction.0 * size, height: fraction.1 * size)
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
                                target: target,
                                pressedDestination: pressedDestination,
                                token: token)
        }
    }

    private var orientDuration: Double { reduceMotion ? 0.10 : 0.38 }
    private var outwardDuration: Double { reduceMotion ? 0.20 : 1.16 }
    private var pressDuration: Double { reduceMotion ? 0.04 : 0.10 }
    private var pushOffDuration: Double { reduceMotion ? 0.08 : 0.20 }
    /// Long enough for a weightless arrival: most of the distance is covered
    /// early, and the last stretch only drifts to a stop.
    private var returnDuration: Double { reduceMotion ? 0.24 : 1.28 }
    private var settleDuration: Double { reduceMotion ? 0.08 : 0.56 }

    private func beginOutwardTravel(_ option: AnswerOption,
                                     target: CGPoint,
                                     pressedDestination: CGSize,
                                     token: Int) {
        motionPhase = .travellingOut
        phaseStarted = Date()
        // Leave gently and arrive at rest, already pressed into the button.
        // A second animation for that last nudge used to cut the glide.
        withAnimation(.timingCurve(0.35, 0.00, 0.55, 1.00,
                                   duration: outwardDuration)) {
            motionOffset = pressedDestination
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + outwardDuration) {
            guard actionSequence == token else { return }
            guard isLive, isRunning else {
                cancelAction(token: token)
                return
            }
            reachButton(option,
                        target: target,
                        token: token)
        }
    }

    private func reachButton(_ option: AnswerOption,
                             target: CGPoint,
                             token: Int) {
        motionPhase = .contact
        phaseStarted = Date()
        buttonHasContact = true
        AppAudio.shared.playButtonPress()
        let accepted = onHit(option.id, false, false)
        if accepted {
            onSwallow(option.isCorrect)
            let burst = SpaceAnswerBurstState(point: target, isCorrect: option.isCorrect)
            feedbackBurst = burst
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.28 : 0.76)) {
                guard feedbackBurst?.id == burst.id else { return }
                feedbackBurst = nil
            }
            if !option.isCorrect, !reduceMotion {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.46)) {
                    lionScale = 0.94
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    guard actionSequence == token else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                        lionScale = 1
                    }
                }
            }
        }

        // The glide already ended on the pressed fingertip. Only the button
        // cap moves here, so the lion's path is not retargeted mid-flight.
        withAnimation(.timingCurve(0.20, 0.00, 0.40, 1.00, duration: pressDuration)) {
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
        // One continuous glide home. It leaves with the push and spends the
        // last third of the trip drifting to a stop, instead of arriving with
        // speed and then halting.
        let recoilAnimation: Animation = reduceMotion
            ? .linear(duration: pushOffDuration + returnDuration)
            : .timingCurve(0.18, 0.35, 0.36, 1.00,
                           duration: pushOffDuration + returnDuration)
        let buttonAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.22, dampingFraction: 0.52)
        withAnimation(recoilAnimation) {
            motionOffset = .zero
            if selectedWasCorrect, !reduceMotion {
                celebrationSpin += 360
            }
        }
        withAnimation(buttonAnimation) {
            buttonImpactScale = 1
        }

        let homeDuration = pushOffDuration + returnDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + homeDuration * 0.58) {
            guard actionSequence == token else { return }
            withAnimation(.easeInOut(duration: homeDuration * 0.62)) {
                driftAmount = 1
            }
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
        // A slow weightless sway. The face stays readable; the full turn is
        // reserved for the happy flip after a correct answer.
        return sin(time * 0.42) * 10 + sin(time * 0.17) * 4
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
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            celebrationSpin = 0
        }
        if driftAmount < 1 {
            withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.45)) {
                driftAmount = 1
            }
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
        celebrationSpin = 0
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
            completionOffset = CGSize(width: width * 0.62, height: -width * 0.16)
            lionScale = 1.12
            if !reduceMotion { celebrationSpin += 220 }
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

extension SpaceLionPlayfield {
    struct Metrics {
        let size: CGSize
        let topReserve: CGFloat
        let bottomReserve: CGFloat
        let leftReserve: CGFloat
        let rightReserve: CGFloat
        let isPad: Bool

        /// The answer bank starts immediately below the overhead rail. The
        /// proportional nudge keeps the same visual breathing room on a short
        /// phone and a large iPad instead of relying on one device-sized gap.
        private var columnTop: CGFloat {
            topReserve + max(isPad ? 14 : 8, size.height * 0.018)
        }
        private var columnBottom: CGFloat {
            let safeBottom = size.height - max(bottomReserve, isPad ? 16 : 8)
            // End the answer bank just above the deck. The larger modules sit
            // lower here while the last answer still clears the foreground
            // console instead of floating against the bottom edge.
            return min(safeBottom - size.height * (isPad ? 0.10 : 0.08),
                       size.height * (isPad ? 0.78 : 0.80))
        }
        private var slotHeight: CGFloat {
            max(1, (columnBottom - columnTop) / CGFloat(GameConfig.answerColumnCount))
        }

        var answerSize: CGFloat {
            // `size` is the complete mechanical module; the illuminated stone
            // inside remains comfortably above the 44 pt touch minimum.
            min(max(slotHeight * 1.09, isPad ? 103 : 80),
                isPad ? 181 : 132,
                size.width * 0.194)
        }
        private var columnPadding: CGFloat { answerSize * 0.13 }
        /// Physical cabinet visible outside the answer modules. Keeping this
        /// proportional (and capped by the module size) leaves enough room for
        /// a readable side face on phones without swallowing the play window
        /// on an iPad.
        private var cabinetDepth: CGFloat {
            min(size.width * 0.04, answerSize * 0.34)
        }
        private var leftX: CGFloat {
            max(leftReserve, isPad ? 16 : 8) + cabinetDepth + answerSize * 0.56
        }
        private var rightX: CGFloat {
            size.width - max(rightReserve, isPad ? 16 : 8) - cabinetDepth - answerSize * 0.56
        }

        /// Three controls in each side column, read top to bottom: the lowest
        /// values on the left wall, the highest on the right wall. These are
        /// deliberately on one vertical axis: perspective belongs to the room
        /// around the controls, never to the control alignment itself.
        var answerPoints: [CGPoint] {
            let rows = (0..<GameConfig.answerColumnCount).map {
                columnTop + slotHeight * (CGFloat($0) + 0.5)
            }
            return rows.map { CGPoint(x: leftX, y: $0) }
                + rows.map { CGPoint(x: rightX, y: $0) }
        }

        fileprivate var cockpit: CockpitLayout {
            let leftEdge = leftX + answerSize / 2 + columnPadding
            let rightEdge = rightX - answerSize / 2 - columnPadding
            let gap: CGFloat = isPad ? 36 : 22
            let top = topReserve + (isPad ? 16 : 10)
            let bottom = max(top + 60, size.height * (isPad ? 0.72 : 0.73))
            return CockpitLayout(
                windowRect: CGRect(x: leftEdge + gap,
                                   y: top,
                                   width: max(60, rightEdge - leftEdge - gap * 2),
                                   height: bottom - top),
                leftEdge: leftEdge,
                rightEdge: rightEdge,
                buttonPoints: answerPoints,
                buttonSize: answerSize)
        }

        /// Shared with the HUD so the pause control sits on the exact same
        /// vertical axis as the left answers, and the score panel terminates on
        /// the outside edge of the right answer bank at every device size.
        func hudInsets(pauseWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
            let leading = max(0, leftX - pauseWidth / 2)
            let trailing = max(0, size.width - (rightX + answerSize / 2))
            return (leading, trailing)
        }

        var centre: CGPoint {
            let window = cockpit.windowRect
            return CGPoint(x: window.midX, y: window.midY)
        }

        var lionSize: CGFloat {
            min(size.width * 0.23,
                size.height * (isPad ? 0.35 : 0.38),
                cockpit.windowRect.height * 0.74)
        }
    }
}

private func cockpitWrap(_ value: Double) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: 1)
    return remainder < 0 ? remainder + 1 : remainder
}

/// Where the cockpit's fixed structure sits, so the painted bays line up
/// exactly with the interactive buttons laid over them.
private struct CockpitLayout {
    let windowRect: CGRect
    let leftEdge: CGFloat
    let rightEdge: CGFloat
    let buttonPoints: [CGPoint]
    let buttonSize: CGFloat
}

/// The interactive part of a wall control: a glossy answer cap sitting in the
/// cockpit's recessed well. The shared cockpit canvas paints the lamp ring.
private struct SpaceConsoleButton: View {
    let text: String
    let size: CGFloat
    let feedback: HoopFeedback
    let isPressed: Bool
    @State private var shakePhase: CGFloat = 0

    private struct Palette {
        let glow: Color
        let highlight: Color
        let deep: Color
        let ink: Color
    }

    private var palette: Palette {
        switch feedback {
        case .correct, .revealedCorrect, .bonus:
            return Palette(glow: Color(red: 0.20, green: 0.95, blue: 0.50),
                           highlight: Color(red: 0.86, green: 1.00, blue: 0.90),
                           deep: Color(red: 0.00, green: 0.45, blue: 0.22),
                           ink: Color(red: 0.00, green: 0.22, blue: 0.10))
        case .wrong:
            return Palette(glow: Color(red: 1.00, green: 0.48, blue: 0.22),
                           highlight: Color(red: 1.00, green: 0.90, blue: 0.78),
                           deep: Color(red: 0.55, green: 0.16, blue: 0.04),
                           ink: Color(red: 0.32, green: 0.08, blue: 0.02))
        case .none, .inactive, .bypassed:
            return Palette(glow: Color(red: 0.16, green: 0.76, blue: 1.00),
                           highlight: Color(red: 0.84, green: 0.97, blue: 1.00),
                           deep: Color(red: 0.03, green: 0.24, blue: 0.78),
                           ink: Color(red: 0.00, green: 0.08, blue: 0.32))
        }
    }

    private var glowStrength: Double {
        switch feedback {
        case .correct, .revealedCorrect, .bonus, .wrong:
            return 0.88
        case .none, .inactive, .bypassed:
            return 0.46
        }
    }

    var body: some View {
        let colors = palette
        ZStack {
            // One self-contained control module. The plate, socket, rails and
            // cap scale together, so this button remains part of the cabinet
            // instead of looking like a circle laid over a background image.
            SpaceModuleShape(cut: size * 0.23)
                .fill(LinearGradient(
                    colors: [Color(red: 0.28, green: 0.36, blue: 0.54),
                             Color(red: 0.08, green: 0.12, blue: 0.24),
                             Color(red: 0.025, green: 0.035, blue: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    SpaceModuleShape(cut: size * 0.23)
                        .stroke(LinearGradient(colors: [.white.opacity(0.46),
                                                        .white.opacity(0.05),
                                                        .black.opacity(0.88)],
                                               startPoint: .top,
                                               endPoint: .bottom),
                                lineWidth: max(1, size * 0.025))
                }
                .shadow(color: .black.opacity(0.75), radius: size * 0.055,
                        y: size * 0.035)

            SpaceModuleShape(cut: size * 0.18)
                .fill(Color(red: 0.025, green: 0.04, blue: 0.10))
                .overlay {
                    SpaceModuleShape(cut: size * 0.18)
                        .stroke(colors.glow.opacity(0.34),
                                lineWidth: max(1, size * 0.012))
                }
                .padding(size * 0.075)

            // Recessed vertical service channels visually lock the module into
            // the continuous console bank painted behind it.
            HStack(spacing: size * 0.68) {
                ForEach(0..<2, id: \.self) { side in
                    ZStack {
                        Capsule()
                            .fill(.black.opacity(0.72))
                            .frame(width: size * 0.075, height: size * 0.43)
                        Capsule()
                            .fill(LinearGradient(colors: [colors.glow.opacity(0.95),
                                                          colors.glow.opacity(0.18)],
                                                 startPoint: .top,
                                                 endPoint: .bottom))
                            .frame(width: size * 0.025, height: size * 0.31)
                            .shadow(color: colors.glow.opacity(0.72),
                                    radius: size * 0.035)
                        if side == 0 {
                            ForEach(0..<3, id: \.self) { index in
                                Capsule()
                                    .fill(.white.opacity(0.22))
                                    .frame(width: size * 0.035, height: size * 0.008)
                                    .offset(y: (CGFloat(index) - 1) * size * 0.095)
                            }
                        }
                    }
                }
            }

            // Mechanical corner fasteners and short amber power brackets.
            ForEach(0..<4, id: \.self) { index in
                let x: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                let y: CGFloat = index < 2 ? -1 : 1
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.78),
                                                      Color(red: 0.34, green: 0.43, blue: 0.58),
                                                      .black],
                                             center: UnitPoint(x: 0.35, y: 0.30),
                                             startRadius: 0,
                                             endRadius: size * 0.035))
                        .frame(width: size * 0.07, height: size * 0.07)
                    Capsule()
                        .fill(Color(red: 1.00, green: 0.57, blue: 0.08))
                        .frame(width: size * 0.11, height: size * 0.025)
                        .offset(x: -x * size * 0.075)
                        .shadow(color: Color(red: 1.00, green: 0.45, blue: 0.04),
                                radius: size * 0.025)
                }
                .offset(x: x * size * 0.35, y: y * size * 0.35)
            }

            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.28, green: 0.36, blue: 0.52),
                                              Color(red: 0.08, green: 0.11, blue: 0.20),
                                              Color(red: 0.02, green: 0.03, blue: 0.07)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .overlay(
                    Circle().stroke(LinearGradient(colors: [.white.opacity(0.50),
                                                            .white.opacity(0.05),
                                                            .black.opacity(0.75)],
                                                   startPoint: .top,
                                                   endPoint: .bottom),
                                    lineWidth: size * 0.014)
                )
                .padding(size * 0.145)
                .shadow(color: .black.opacity(0.55), radius: size * 0.045, y: size * 0.025)

            Circle()
                .stroke(colors.glow.opacity(0.28), lineWidth: size * 0.010)
                .padding(size * 0.168)
            Circle()
                .stroke(colors.glow.opacity(glowStrength), lineWidth: size * 0.034)
                .blur(radius: size * 0.018)
                .padding(size * 0.198)
            Circle()
                .stroke(colors.glow.opacity(0.95), lineWidth: size * 0.012)
                .padding(size * 0.198)
            Circle()
                .stroke(.white.opacity(0.70), lineWidth: max(1, size * 0.008))
                .padding(size * 0.214)

            cap(colors, diameter: size * 0.54)
        }
        .frame(width: size, height: size)
        .modifier(SpaceShakeEffect(progress: shakePhase, distance: size * 0.045))
        .opacity(feedback == .inactive ? 0.55 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isPressed)
        .animation(.easeInOut(duration: 0.24), value: feedback)
        .onChange(of: feedback) { _, value in
            guard value == .wrong else { return }
            withAnimation(.linear(duration: 0.34)) { shakePhase += 1 }
        }
        .contentShape(SpaceModuleShape(cut: size * 0.24))
    }

    private func cap(_ colors: Palette, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors.highlight, colors.glow, colors.deep, .black.opacity(0.35)],
                                     center: UnitPoint(x: 0.38, y: 0.28),
                                     startRadius: 0,
                                     endRadius: diameter * 0.72))
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.75), colors.deep.opacity(0.2), .black.opacity(0.55)],
                                   startPoint: .top,
                                   endPoint: .bottom),
                    lineWidth: diameter * 0.045
                )
            Circle()
                .stroke(colors.glow.opacity(0.55), lineWidth: diameter * 0.02)
                .padding(diameter * 0.08)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .frame(width: diameter * 0.62, height: diameter * 0.30)
                .offset(y: -diameter * 0.24)
            Ellipse()
                .fill(.white.opacity(0.22))
                .frame(width: diameter * 0.18, height: diameter * 0.10)
                .offset(x: -diameter * 0.16, y: -diameter * 0.22)

            Text(verbatim: text)
                .font(.system(size: diameter * 0.50, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.36)
                .frame(width: diameter * 0.82)
                .shadow(color: colors.ink, radius: 0, y: diameter * 0.03)
                .shadow(color: colors.ink.opacity(0.9), radius: diameter * 0.04)
                .shadow(color: .black.opacity(0.35), radius: diameter * 0.02, y: diameter * 0.02)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressed ? 0.90 : 1)
        .offset(y: isPressed ? diameter * 0.035 : 0)
        .brightness(isPressed ? 0.08 : 0)
        .shadow(color: colors.glow.opacity(isPressed ? 1 : glowStrength * 0.9),
                radius: size * (isPressed ? 0.14 : 0.07))
    }
}

/// Gives every answer an immediate, tactile response while the lion begins its
/// longer flight toward the chosen control.
private struct SpaceAnswerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
            configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? 0.10 : 0)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.spring(response: 0.16, dampingFraction: 0.58),
                       value: configuration.isPressed)
    }
}

private struct SpaceShakeEffect: GeometryEffect {
    var progress: CGFloat
    let distance: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(progress * .pi * 6) * distance
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// A lightweight GPU-friendly reward bloom. Correct answers throw stars and
/// cool sparks; mistakes keep the same motion but use a soft encouraging amber.
private struct SpaceAnswerBurst: View {
    let burst: SpaceAnswerBurstState
    let size: CGFloat
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0

    private var particleCount: Int { burst.isCorrect ? 14 : 8 }
    private var primary: Color {
        burst.isCorrect
            ? Color(red: 0.28, green: 1.00, blue: 0.55)
            : Color(red: 1.00, green: 0.45, blue: 0.18)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(primary.opacity(0.85), lineWidth: max(2, size * 0.025))
                .scaleEffect(0.35 + progress * 0.85)
                .opacity(Double(1 - progress))
                .shadow(color: primary, radius: size * 0.08)

            ForEach(0..<particleCount, id: \.self) { index in
                let fraction = CGFloat(index) / CGFloat(particleCount)
                let angle = fraction * .pi * 2 + CGFloat(index % 3) * 0.17
                let distance = size * (0.28 + CGFloat((index * 37) % 11) / 40)
                Group {
                    if burst.isCorrect && index.isMultiple(of: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: size * (index.isMultiple(of: 2) ? 0.105 : 0.075),
                                          weight: .black))
                    } else {
                        Capsule()
                            .frame(width: size * 0.035, height: size * 0.10)
                    }
                }
                .foregroundStyle(index.isMultiple(of: 2) ? primary : .white)
                .shadow(color: primary, radius: size * 0.04)
                .rotationEffect(.radians(Double(angle + progress * 1.4)))
                .offset(x: cos(angle) * distance * progress,
                        y: sin(angle) * distance * progress)
                .scaleEffect(0.45 + (1 - progress) * 0.65)
                .opacity(Double(1 - progress))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            progress = 0
            withAnimation(.easeOut(duration: reduceMotion ? 0.22 : 0.70)) {
                progress = 1
            }
        }
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

/// The glass in front of the viewport: a slow reflection and a soft inner
/// vignette. It never accepts hits, so the answer buttons stay outside it.
private struct SpaceViewportGlass: View {
    let window: CGRect
    let cut: CGFloat
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning)) { timeline in
            let travel = isRunning
                ? cockpitWrap(timeline.date.timeIntervalSinceReferenceDate * 0.06)
                : 0.22
            ZStack {
                LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.02), .clear],
                               startPoint: .top,
                               endPoint: UnitPoint(x: 0.5, y: 0.42))
                LinearGradient(colors: [.clear, .black.opacity(0.14)],
                               startPoint: UnitPoint(x: 0.5, y: 0.78),
                               endPoint: .bottom)
                GeometryReader { proxy in
                    let band = proxy.size.width * 0.18
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: band)
                        .rotationEffect(.degrees(16))
                        .offset(x: -band + (proxy.size.width + band * 2) * travel,
                                y: -proxy.size.height * 0.08)
                }
            }
            .clipShape(SpaceModuleShape(cut: cut))
        }
        .frame(width: window.width, height: window.height)
        .position(x: window.midX, y: window.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rings and sparks when a board is completed, before the result card.
private struct VictoryBloom: View {
    let size: CGFloat
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(Color(red: 0.45, green: 0.90, blue: 1.00).opacity(0.85),
                            lineWidth: max(2, size * 0.012))
                    .frame(width: size * 0.45, height: size * 0.45)
                    .scaleEffect(0.35 + progress * (0.7 + CGFloat(ring) * 0.38))
                    .opacity(Double(1 - progress) * 0.9)
            }
            ForEach(0..<10, id: \.self) { index in
                let angle = CGFloat(index) / 10 * .pi * 2
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.045, weight: .black))
                    .foregroundStyle(index.isMultiple(of: 2)
                                     ? Color(red: 1.00, green: 0.78, blue: 0.28)
                                     : .white)
                    .offset(x: cos(angle) * size * 0.42 * progress,
                            y: sin(angle) * size * 0.28 * progress)
                    .opacity(Double(1 - progress))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.78)) {
                progress = 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The cockpit interior: a roof under the HUD, two button columns, a large
/// chamfered windshield onto a nebula and a planet, and a perspective floor
/// with a teleporter pad. Everything is drawn from paths and gradients.
private struct SpaceshipCockpit: View {
    private struct StarSample {
        let depth: CGFloat
        let x: CGFloat
        let y: CGFloat
        let twinkleRate: Double
    }

    let layout: CockpitLayout
    let character: AnimalCharacter
    let isPad: Bool
    let isRunning: Bool
    let feedbacks: [HoopFeedback]

    private let cyan = Color(red: 0.20, green: 0.82, blue: 1.00)
    private let blue = Color(red: 0.08, green: 0.34, blue: 0.95)
    private let orange = Color(red: 1.00, green: 0.62, blue: 0.12)
    private let metalLight = Color(red: 0.55, green: 0.64, blue: 0.82)
    private let metal = Color(red: 0.16, green: 0.22, blue: 0.38)
    private let metalDark = Color(red: 0.035, green: 0.05, blue: 0.11)

    /// Normalised star data is invariant for the life of the app. Precomputing
    /// it avoids four integer hash sequences per star on every animation frame.
    private static let starSamples: [StarSample] = (0..<320).map { index in
        let depth = seededValue(index, 1)
        return StarSample(depth: depth,
                          x: seededValue(index, 2),
                          y: seededValue(index, 4),
                          twinkleRate: 0.8 + Double(seededValue(index, 5)) * 2.2)
    }

    var body: some View {
        ZStack {
            // The hull, nebula, planet and control sockets do not change from
            // frame to frame. Keeping them in their own canvas prevents the
            // animation clock from rebuilding hundreds of paths and gradients
            // just to move a few small lights.
            Canvas(opaque: true, rendersAsynchronously: true) { context, size in
                drawStatic(in: context, size: size)
            }

            // One shared clock drives every live cockpit light. Previously
            // every answer button owned a TimelineView and Canvas of its own.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: true) { context, size in
                    drawAnimated(in: context, size: size, time: time)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var frameWidth: CGFloat { isPad ? 26 : 18 }

    private func drawStatic(in context: GraphicsContext, size: CGSize) {
        let window = layout.windowRect
        let cut = min(window.width, window.height) * 0.11
        let floorTop = window.maxY + frameWidth * 0.5 + (isPad ? 14 : 9)

        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [metal, metalDark, .black]),
                                           startPoint: .zero,
                                           endPoint: CGPoint(x: 0, y: size.height)))
        drawRoof(in: context, size: size, window: window)
        drawFloor(in: context, size: size, top: floorTop, time: 0)
        drawSpace(in: context, window: window, cut: cut, time: 0)
        drawWindowFrame(in: context, window: window, cut: cut)
        drawSill(in: context, window: window, floorTop: floorTop)
        drawColumn(in: context, size: size,
                   minX: -2, maxX: layout.leftEdge, innerIsTrailing: true,
                   window: window)
        drawColumn(in: context, size: size,
                   minX: layout.rightEdge, maxX: size.width + 2, innerIsTrailing: false,
                   window: window)
    }

    private func drawAnimated(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let window = layout.windowRect
        let cut = min(window.width, window.height) * 0.11

        // Stars are the only moving part behind the glass. The much heavier
        // nebula and planet remain in the static canvas below.
        context.drawLayer { space in
            space.clip(to: chamfered(window, cut: cut))
            drawStars(in: space, window: window, time: time)
            drawAsteroids(in: space, window: window, time: time)
            drawAtmosphereShimmer(in: space, window: window, time: time)
            drawSpaceDust(in: space, window: window, time: time)
            drawGalaxyShimmer(in: space, window: window, time: time)
        }

        drawAnimatedControls(in: context, window: window, time: time)
        drawHullEnergyFlow(in: context, window: window, time: time)
        drawPlatformPulse(in: context, size: size, time: time)
        drawCabinetPulse(in: context, window: window, time: time)
    }

    /// The fixed part of the two armoured cables from a control to the glass.
    private func drawConduits(in context: GraphicsContext,
                              from startX: CGFloat,
                              to endX: CGFloat,
                              y: CGFloat) {
        let spacing = layout.buttonSize * 0.12
        for cable in 0..<2 {
            let cableY = y + (cable == 0 ? -spacing : spacing)
            var path = Path()
            path.move(to: CGPoint(x: startX, y: cableY))
            path.addLine(to: CGPoint(x: endX, y: cableY))
            context.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: isPad ? 7 : 5)
            context.stroke(path, with: .color(metal), lineWidth: isPad ? 4 : 3)
            context.stroke(path, with: .color(cyan.opacity(0.55)), lineWidth: isPad ? 1.4 : 1)
        }
    }

    private func drawAnimatedControls(in context: GraphicsContext,
                                      window: CGRect,
                                      time: TimeInterval) {
        for (index, point) in layout.buttonPoints.enumerated() {
            let phase = Double(index)
            let isLeft = point.x < window.midX
            let outward: CGFloat = isLeft ? -1 : 1
            let innerX = point.x - outward * layout.buttonSize * 0.58
            let frameX = isLeft
                ? window.minX - frameWidth * 0.5
                : window.maxX + frameWidth * 0.5

            if point.y > window.minY + frameWidth, point.y < window.maxY - frameWidth {
                drawConduitEnergyBars(in: context,
                                      from: innerX,
                                      to: frameX,
                                      y: point.y,
                                      phase: phase,
                                      time: time)
            }

            let feedback = index < feedbacks.count ? feedbacks[index] : .none
            drawControlLights(in: context,
                              at: point,
                              feedback: feedback)
        }
    }

    /// Long, slow energy bars replace the old fast dots. Both rails flow from
    /// each answer bank toward the central window without any frantic chasing.
    private func drawConduitEnergyBars(in context: GraphicsContext,
                                       from startX: CGFloat,
                                       to endX: CGFloat,
                                       y: CGFloat,
                                       phase: Double,
                                       time: TimeInterval) {
        let spacing = layout.buttonSize * 0.12
        for cable in 0..<2 {
            let cableY = y + (cable == 0 ? -spacing : spacing)
            let progress = CGFloat(cockpitWrap(time * 0.16
                                               + phase * 0.11
                                               + Double(cable) * 0.50))
            let span = abs(endX - startX)
            let length = min(span * 0.58, layout.buttonSize * 0.27)
            let thickness: CGFloat = isPad ? 3.0 : 2.0
            let direction: CGFloat = endX >= startX ? 1 : -1
            let travelStart = startX - direction * length * 0.5
            let travelEnd = endX + direction * length * 0.5
            let centre = CGPoint(x: travelStart + (travelEnd - travelStart) * progress,
                                 y: cableY)
            let clipRect = CGRect(x: min(startX, endX),
                                  y: cableY - thickness * 3,
                                  width: span,
                                  height: thickness * 6)

            context.drawLayer { rail in
                rail.clip(to: Path(clipRect))
                drawEnergyBar(in: rail,
                              centre: centre,
                              length: length,
                              thickness: thickness,
                              vertical: false,
                              color: cyan,
                              opacity: 0.78)
            }
        }
    }

    /// The eight lamps are intentionally fixed. Feedback can change their
    /// colour, but neither their position nor their brightness ever chases.
    private func drawControlLights(in context: GraphicsContext,
                                   at centre: CGPoint,
                                   feedback: HoopFeedback) {
        var glow = context
        glow.blendMode = .plusLighter
        let buttonSize = layout.buttonSize
        let excited = feedback != .none && feedback != .inactive && feedback != .bypassed
        let lampColor = controlLampColor(for: feedback)
        let orbit = buttonSize * 0.385
        let radius = buttonSize * 0.032
        let intensity: Double = excited ? 0.84 : 0.40

        let plate = CGRect(x: centre.x - buttonSize * 0.5,
                           y: centre.y - buttonSize * 0.5,
                           width: buttonSize,
                           height: buttonSize)
        glow.stroke(chamfered(plate, cut: buttonSize * 0.24),
                    with: .color(lampColor.opacity(excited ? 0.22 : 0.08)),
                    lineWidth: isPad ? 8 : 5)

        for lampIndex in 0..<8 {
            let fraction = Double(lampIndex) / 8
            let angle = fraction * 2 * .pi - .pi / 2
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * orbit,
                                y: centre.y + CGFloat(sin(angle)) * orbit)

            let core = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            glow.fill(Path(ellipseIn: core),
                      with: .color(lampColor.opacity(0.28 + 0.50 * intensity)))
            glow.fill(Path(ellipseIn: core.insetBy(dx: radius * 0.35, dy: radius * 0.35)),
                      with: .color(Color.white.opacity(0.18 + 0.42 * intensity)))
            let halo = core.insetBy(dx: -radius * 2.4, dy: -radius * 2.4)
            glow.fill(Path(ellipseIn: halo),
                      with: .radialGradient(Gradient(colors: [lampColor.opacity(0.30 * intensity),
                                                              lampColor.opacity(0)]),
                                            center: point,
                                            startRadius: 0,
                                            endRadius: halo.width / 2))
        }
    }

    /// Four measured light bars circulate through the reinforced window rails.
    /// Their long travel and deliberately different periods keep the cockpit
    /// alive without turning the frame into a flashing marquee.
    private func drawHullEnergyFlow(in context: GraphicsContext,
                                    window: CGRect,
                                    time: TimeInterval) {
        let horizontalLength = min(window.width * 0.16, isPad ? 150 : 92)
        let verticalLength = min(window.height * 0.18, isPad ? 110 : 66)
        let thickness: CGFloat = isPad ? 3.4 : 2.2
        let topY = window.minY - frameWidth * 0.53
        let bottomY = window.maxY + frameWidth * 0.58
        let leftX = window.minX - frameWidth * 0.55
        let rightX = window.maxX + frameWidth * 0.55

        let topProgress = CGFloat(cockpitWrap(time * 0.090))
        let bottomProgress = CGFloat(cockpitWrap(1 - time * 0.074))
        let leftProgress = CGFloat(cockpitWrap(time * 0.068 + 0.24))
        let rightProgress = CGFloat(cockpitWrap(1 - time * 0.061 + 0.68))

        let horizontalClip = CGRect(x: window.minX,
                                    y: topY - thickness * 4,
                                    width: window.width,
                                    height: bottomY - topY + thickness * 8)
        context.drawLayer { rails in
            rails.clip(to: Path(horizontalClip))

            let topX = window.minX - horizontalLength * 0.5
                + (window.width + horizontalLength) * topProgress
            drawEnergyBar(in: rails,
                          centre: CGPoint(x: topX, y: topY),
                          length: horizontalLength,
                          thickness: thickness,
                          vertical: false,
                          color: cyan,
                          opacity: 0.78)

            let bottomX = window.minX - horizontalLength * 0.5
                + (window.width + horizontalLength) * bottomProgress
            drawEnergyBar(in: rails,
                          centre: CGPoint(x: bottomX, y: bottomY),
                          length: horizontalLength * 0.86,
                          thickness: thickness,
                          vertical: false,
                          color: orange,
                          opacity: 0.72)
        }

        let verticalClip = CGRect(x: leftX - thickness * 4,
                                  y: window.minY,
                                  width: rightX - leftX + thickness * 8,
                                  height: window.height)
        context.drawLayer { rails in
            rails.clip(to: Path(verticalClip))

            let leftY = window.minY - verticalLength * 0.5
                + (window.height + verticalLength) * leftProgress
            drawEnergyBar(in: rails,
                          centre: CGPoint(x: leftX, y: leftY),
                          length: verticalLength,
                          thickness: thickness,
                          vertical: true,
                          color: cyan,
                          opacity: 0.66)

            let rightY = window.minY - verticalLength * 0.5
                + (window.height + verticalLength) * rightProgress
            drawEnergyBar(in: rails,
                          centre: CGPoint(x: rightX, y: rightY),
                          length: verticalLength,
                          thickness: thickness,
                          vertical: true,
                          color: cyan,
                          opacity: 0.66)
        }
    }

    /// Paints one soft-edged power segment with a narrow white-hot centre.
    private func drawEnergyBar(in context: GraphicsContext,
                               centre: CGPoint,
                               length: CGFloat,
                               thickness: CGFloat,
                               vertical: Bool,
                               color: Color,
                               opacity: Double) {
        let rect = CGRect(x: centre.x - (vertical ? thickness : length) * 0.5,
                          y: centre.y - (vertical ? length : thickness) * 0.5,
                          width: vertical ? thickness : length,
                          height: vertical ? length : thickness)
        let glowRect = rect.insetBy(dx: -thickness * 2.2, dy: -thickness * 2.2)
        let start = vertical
            ? CGPoint(x: centre.x, y: rect.minY)
            : CGPoint(x: rect.minX, y: centre.y)
        let end = vertical
            ? CGPoint(x: centre.x, y: rect.maxY)
            : CGPoint(x: rect.maxX, y: centre.y)
        let gradient = Gradient(colors: [color.opacity(0),
                                         color.opacity(opacity * 0.75),
                                         .white.opacity(opacity),
                                         color.opacity(opacity * 0.75),
                                         color.opacity(0)])

        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(roundedRect: glowRect, cornerRadius: thickness * 2.5),
                  with: .color(color.opacity(opacity * 0.12)))
        glow.fill(Path(roundedRect: rect, cornerRadius: thickness * 0.5),
                  with: .linearGradient(gradient, startPoint: start, endPoint: end))
    }

    private func controlLampColor(for feedback: HoopFeedback) -> Color {
        switch feedback {
        case .correct, .revealedCorrect, .bonus:
            return Color(red: 0.20, green: 0.95, blue: 0.50)
        case .wrong:
            return Color(red: 1.00, green: 0.48, blue: 0.22)
        case .none, .inactive, .bypassed:
            return orange
        }
    }

    // MARK: Hull

    private func drawRoof(in context: GraphicsContext, size: CGSize, window: CGRect) {
        let bottom = window.minY - frameWidth * 0.5
        guard bottom > 0 else { return }
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: bottom)),
                     with: .linearGradient(Gradient(colors: [metalDark, metal, metalLight]),
                                           startPoint: .zero,
                                           endPoint: CGPoint(x: 0, y: bottom)))
        for fraction in [0.34, 0.68] as [CGFloat] {
            seam(context,
                 from: CGPoint(x: 0, y: bottom * fraction),
                 to: CGPoint(x: size.width, y: bottom * fraction))
        }
        for fraction in stride(from: CGFloat(0.2), through: 0.8, by: 0.2) {
            seam(context,
                 from: CGPoint(x: size.width * fraction, y: bottom * 0.68),
                 to: CGPoint(x: size.width * fraction, y: bottom))
        }
        drawVent(context,
                 rect: CGRect(x: size.width * 0.06, y: bottom * 0.18,
                              width: size.width * 0.08, height: bottom * 0.42))
        drawVent(context,
                 rect: CGRect(x: size.width * 0.86, y: bottom * 0.18,
                              width: size.width * 0.08, height: bottom * 0.42))
    }

    private func drawVent(_ context: GraphicsContext, rect: CGRect) {
        guard rect.width > 8, rect.height > 8 else { return }
        context.fill(Path(roundedRect: rect, cornerRadius: 3),
                     with: .color(.black.opacity(0.45)))
        let slots = 5
        let gap = rect.height / CGFloat(slots * 2)
        for slot in 0..<slots {
            let y = rect.minY + gap + CGFloat(slot) * gap * 2
            let bar = CGRect(x: rect.minX + 3, y: y, width: rect.width - 6, height: max(1.5, gap * 0.45))
            context.fill(Path(roundedRect: bar, cornerRadius: 1),
                         with: .color(metalLight.opacity(0.35)))
        }
    }

    private func drawColumn(in context: GraphicsContext,
                            size: CGSize,
                            minX: CGFloat,
                            maxX: CGFloat,
                            innerIsTrailing: Bool,
                            window: CGRect) {
        guard maxX > minX else { return }
        let innerX = innerIsTrailing ? maxX : minX
        let outerX = innerIsTrailing ? minX : maxX
        let outward: CGFloat = innerIsTrailing ? -1 : 1
        let towardInner = -outward
        let buttonSize = layout.buttonSize
        let mounts = layout.buttonPoints.enumerated().filter { $0.element.x > minX && $0.element.x < maxX }
        let points = mounts.map(\.element)
        guard let first = points.first, let last = points.last else { return }

        // The answer rack is part of the rear wall and therefore stays truly
        // vertical. The room depth lives outside it: lines on the side wall
        // spread toward the viewer (the screen edge) and converge toward the
        // centre of the rear viewport.
        let controlX = first.x
        let outerModuleX = controlX + outward * buttonSize * 0.58
        let innerModuleX = controlX + towardInner * buttonSize * 0.58
        let vanishingY = window.midY
        let frontSpread: CGFloat = isPad ? 1.34 : 1.40

        func frontY(for backY: CGFloat) -> CGFloat {
            vanishingY + (backY - vanishingY) * frontSpread
        }

        /// `depth` is zero at the near, cropped screen edge and one at the
        /// rear wall beside the answer rack.
        func wallPoint(backY: CGFloat, depth: CGFloat) -> CGPoint {
            let nearY = frontY(for: backY)
            return CGPoint(x: outerX + (outerModuleX - outerX) * depth,
                           y: nearY + (backY - nearY) * depth)
        }

        // One closed side wall. It reaches beyond the canvas at the near edge
        // so no strip of the star field can read as an accidental side window.
        var sideWall = Path()
        sideWall.move(to: wallPoint(backY: 0, depth: 0))
        sideWall.addLine(to: wallPoint(backY: 0, depth: 1))
        sideWall.addLine(to: wallPoint(backY: size.height, depth: 1))
        sideWall.addLine(to: wallPoint(backY: size.height, depth: 0))
        sideWall.closeSubpath()
        context.fill(sideWall,
                     with: .linearGradient(
                        Gradient(colors: innerIsTrailing
                                 ? [Color(red: 0.015, green: 0.025, blue: 0.065),
                                    Color(red: 0.16, green: 0.22, blue: 0.40),
                                    Color(red: 0.035, green: 0.055, blue: 0.14)]
                                 : [Color(red: 0.035, green: 0.055, blue: 0.14),
                                    Color(red: 0.16, green: 0.22, blue: 0.40),
                                    Color(red: 0.015, green: 0.025, blue: 0.065)]),
                        startPoint: CGPoint(x: outerX, y: vanishingY),
                        endPoint: CGPoint(x: outerModuleX, y: vanishingY)))

        // Broad wall facets share the same vanishing point. Their seams are
        // depth lines, not vertical cage bars.
        let facetStops: [CGFloat] = [0, 0.235, 0.50, 0.765, 1]
        for index in 0..<(facetStops.count - 1) {
            let backTop = size.height * facetStops[index]
            let backBottom = size.height * facetStops[index + 1]
            var facet = Path()
            facet.move(to: wallPoint(backY: backTop, depth: 0))
            facet.addLine(to: wallPoint(backY: backTop, depth: 1))
            facet.addLine(to: wallPoint(backY: backBottom, depth: 1))
            facet.addLine(to: wallPoint(backY: backBottom, depth: 0))
            facet.closeSubpath()
            context.fill(facet,
                         with: .linearGradient(
                            Gradient(colors: index.isMultiple(of: 2)
                                     ? [Color(red: 0.035, green: 0.055, blue: 0.13),
                                        Color(red: 0.20, green: 0.27, blue: 0.47),
                                        Color(red: 0.06, green: 0.095, blue: 0.22)]
                                     : [Color(red: 0.015, green: 0.025, blue: 0.075),
                                        Color(red: 0.11, green: 0.17, blue: 0.33),
                                        Color(red: 0.025, green: 0.04, blue: 0.11)]),
                            startPoint: wallPoint(backY: backTop, depth: 0.08),
                            endPoint: wallPoint(backY: backBottom, depth: 0.92)))

            guard index > 0 else { continue }
            let seamY = backTop
            var rib = Path()
            rib.move(to: wallPoint(backY: seamY, depth: 0))
            rib.addLine(to: wallPoint(backY: seamY, depth: 0.98))
            context.stroke(rib, with: .color(.black.opacity(0.88)),
                           lineWidth: isPad ? 10 : 7)
            context.stroke(rib, with: .color(metalLight.opacity(0.46)),
                           lineWidth: isPad ? 4.2 : 2.8)
            context.stroke(rib.offsetBy(dx: 0, dy: -1.4),
                           with: .color(index == 2 ? cyan.opacity(0.42) : orange.opacity(0.26)),
                           lineWidth: isPad ? 1.8 : 1.1)
        }

        // Low, raised armour plates sit on that side wall. The front face,
        // lower edge and cast shadow all obey the same perspective projection.
        // Keeping them shallow avoids recreating the old stack of grey boxes.
        let plateBands: [(CGFloat, CGFloat)] = [(-0.015, 0.155),
                                                (0.295, 0.445),
                                                (0.565, 0.715),
                                                (0.855, 1.015)]
        let lift = min(buttonSize * 0.075, isPad ? 12 : 8)
        for (index, band) in plateBands.enumerated() {
            let backTop = size.height * band.0
            let backBottom = size.height * band.1
            let nearDepth: CGFloat = 0.08
            let farDepth: CGFloat = 0.70

            var face = Path()
            face.move(to: wallPoint(backY: backTop, depth: nearDepth))
            face.addLine(to: wallPoint(backY: backTop, depth: farDepth))
            face.addLine(to: wallPoint(backY: backBottom, depth: farDepth + 0.035))
            face.addLine(to: wallPoint(backY: backBottom, depth: nearDepth + 0.02))
            face.closeSubpath()

            context.fill(face.offsetBy(dx: outward * lift * 0.34, dy: lift * 0.58),
                         with: .color(.black.opacity(0.66)))

            let lowerNear = wallPoint(backY: backBottom, depth: nearDepth + 0.02)
            let lowerFar = wallPoint(backY: backBottom, depth: farDepth + 0.035)
            var lowerFace = Path()
            lowerFace.move(to: lowerNear)
            lowerFace.addLine(to: lowerFar)
            lowerFace.addLine(to: CGPoint(x: lowerFar.x + outward * lift * 0.26,
                                          y: lowerFar.y + lift * 0.56))
            lowerFace.addLine(to: CGPoint(x: lowerNear.x + outward * lift * 0.26,
                                          y: lowerNear.y + lift * 0.56))
            lowerFace.closeSubpath()
            context.fill(lowerFace,
                         with: .linearGradient(
                            Gradient(colors: [metal.opacity(0.72), .black.opacity(0.96)]),
                            startPoint: lowerNear,
                            endPoint: CGPoint(x: lowerNear.x, y: lowerNear.y + lift)))

            context.fill(face,
                         with: .linearGradient(
                            Gradient(colors: [metalLight.opacity(0.72),
                                              Color(red: 0.09, green: 0.14, blue: 0.29),
                                              Color(red: 0.022, green: 0.035, blue: 0.105)]),
                            startPoint: wallPoint(backY: backTop, depth: nearDepth),
                            endPoint: wallPoint(backY: backBottom, depth: farDepth)))
            context.stroke(face, with: .color(.black.opacity(0.86)),
                           lineWidth: isPad ? 3.2 : 2)

            var topHighlight = Path()
            topHighlight.move(to: wallPoint(backY: backTop, depth: nearDepth))
            topHighlight.addLine(to: wallPoint(backY: backTop, depth: farDepth))
            context.stroke(topHighlight, with: .color(.white.opacity(0.32)),
                           lineWidth: isPad ? 2.2 : 1.4)

            let detailStart = wallPoint(backY: (backTop + backBottom) * 0.5, depth: 0.22)
            let detailEnd = wallPoint(backY: (backTop + backBottom) * 0.5, depth: 0.53)
            var detail = Path()
            detail.move(to: detailStart)
            detail.addLine(to: detailEnd)
            context.stroke(detail, with: .color(.black.opacity(0.80)),
                           lineWidth: isPad ? 8 : 5)
            context.stroke(detail,
                           with: .color((index.isMultiple(of: 2) ? cyan : orange).opacity(0.72)),
                           lineWidth: isPad ? 2.8 : 1.8)
        }

        // A compact rear-wall equipment recess carries all three buttons. It
        // ends just beyond the first and last module instead of becoming a
        // floor-to-ceiling bar.
        let bankTop = max(0, first.y - buttonSize * 0.60)
        let bankBottom = min(size.height, last.y + buttonSize * 0.60)
        let bayMinX = min(outerModuleX, innerX)
        let bayMaxX = max(outerModuleX, innerX)
        let bayRect = CGRect(x: bayMinX,
                             y: bankTop,
                             width: bayMaxX - bayMinX,
                             height: bankBottom - bankTop)
        let bayCut = min(buttonSize * 0.18, bayRect.width * 0.22)
        let bay = chamfered(bayRect, cut: bayCut)
        context.fill(bay,
                     with: .linearGradient(
                        Gradient(colors: [Color(red: 0.10, green: 0.15, blue: 0.29),
                                          Color(red: 0.018, green: 0.03, blue: 0.085),
                                          Color(red: 0.06, green: 0.09, blue: 0.19)]),
                        startPoint: CGPoint(x: outerModuleX, y: bankTop),
                        endPoint: CGPoint(x: innerX, y: bankBottom)))

        // Short top and bottom returns reveal the thickness of the vertical
        // rack; there are intentionally no full-height side rails.
        let capDepth = min(buttonSize * 0.12, isPad ? 20 : 14)
        for (y, direction) in [(bankTop, CGFloat(1)), (bankBottom, CGFloat(-1))] {
            var cap = Path()
            cap.move(to: CGPoint(x: outerModuleX, y: y))
            cap.addLine(to: CGPoint(x: innerX, y: y))
            cap.addLine(to: CGPoint(x: innerX - towardInner * capDepth * 0.22,
                                    y: y + direction * capDepth))
            cap.addLine(to: CGPoint(x: outerModuleX + towardInner * capDepth * 0.34,
                                    y: y + direction * capDepth))
            cap.closeSubpath()
            context.fill(cap,
                         with: .linearGradient(
                            Gradient(colors: direction > 0
                                     ? [.white.opacity(0.30), metal.opacity(0.70), .black.opacity(0.78)]
                                     : [metal.opacity(0.58), .black.opacity(0.95)]),
                            startPoint: CGPoint(x: 0, y: y),
                            endPoint: CGPoint(x: 0, y: y + direction * capDepth)))
            context.stroke(cap, with: .color(.black.opacity(0.78)),
                           lineWidth: isPad ? 2.5 : 1.6)
        }

        let frameX = innerIsTrailing
            ? window.minX - frameWidth * 0.5
            : window.maxX + frameWidth * 0.5

        for (index, mount) in mounts.enumerated() {
            let point = mount.element

            if point.y > window.minY + frameWidth, point.y < window.maxY - frameWidth {
                drawConduits(in: context, from: innerModuleX, to: frameX,
                             y: point.y)
            }

            drawButtonMount(in: context, at: point, size: buttonSize)

            guard index + 1 < points.count else { continue }
            let between = (point.y + points[index + 1].y) / 2
            let bridgeStart = CGPoint(x: outerModuleX + towardInner * buttonSize * 0.08,
                                      y: between)
            let bridgeEnd = CGPoint(x: innerModuleX, y: between)
            seam(context, from: bridgeStart, to: bridgeEnd)
            let bridgeWidth = abs(bridgeEnd.x - bridgeStart.x)
            lightBar(context,
                     center: CGPoint(x: (bridgeStart.x + bridgeEnd.x) / 2, y: between),
                     length: min(buttonSize * 0.24, bridgeWidth * 0.55),
                     thickness: isPad ? 3.5 : 2.5,
                     color: cyan,
                     vertical: false)
        }
    }

    /// The octagonal plate, fixed lamp groove and recessed well are part of the
    /// wall. The live cap and stationary indicator lamps sit over this socket.
    private func drawButtonMount(in context: GraphicsContext,
                                 at point: CGPoint,
                                 size buttonSize: CGFloat) {
        var glow = context
        glow.blendMode = .plusLighter
        let flange = CGRect(x: point.x - buttonSize * 0.56,
                            y: point.y - buttonSize * 0.56,
                            width: buttonSize * 1.12,
                            height: buttonSize * 1.12)
        let plate = CGRect(x: point.x - buttonSize * 0.5,
                           y: point.y - buttonSize * 0.5,
                           width: buttonSize,
                           height: buttonSize)
        let flangePath = chamfered(flange, cut: buttonSize * 0.28)
        let platePath = chamfered(plate, cut: buttonSize * 0.24)

        context.fill(flangePath,
                     with: .linearGradient(Gradient(colors: [metalDark, metal]),
                                           startPoint: CGPoint(x: 0, y: flange.minY),
                                           endPoint: CGPoint(x: 0, y: flange.maxY)))
        context.stroke(flangePath, with: .color(.black.opacity(0.7)), lineWidth: 2)

        context.fill(platePath,
                     with: .linearGradient(Gradient(colors: [metalLight, metal, metalDark]),
                                           startPoint: CGPoint(x: 0, y: plate.minY),
                                           endPoint: CGPoint(x: 0, y: plate.maxY)))
        context.stroke(platePath, with: .color(.black.opacity(0.75)), lineWidth: 2.2)
        context.stroke(chamfered(plate.insetBy(dx: buttonSize * 0.035, dy: buttonSize * 0.035),
                                 cut: buttonSize * 0.20),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.28), .white.opacity(0.04)]),
                                             startPoint: CGPoint(x: 0, y: plate.minY),
                                             endPoint: CGPoint(x: 0, y: plate.maxY)),
                       lineWidth: 1)

        glow.stroke(platePath, with: .color(cyan.opacity(0.12)), lineWidth: isPad ? 8 : 5)

        let trackRadius = buttonSize * 0.385
        let track = CGRect(x: point.x - trackRadius, y: point.y - trackRadius,
                           width: trackRadius * 2, height: trackRadius * 2)
        context.stroke(Path(ellipseIn: track),
                       with: .color(.black.opacity(0.78)),
                       lineWidth: buttonSize * 0.09)
        context.stroke(Path(ellipseIn: track),
                       with: .color(Color(red: 0.16, green: 0.10, blue: 0.05)),
                       lineWidth: buttonSize * 0.055)
        glow.stroke(Path(ellipseIn: track),
                    with: .color(orange.opacity(0.55)),
                    lineWidth: buttonSize * 0.028)

        for inset in [0.33, 0.41] as [CGFloat] {
            let ringRadius = buttonSize * inset
            let ring = CGRect(x: point.x - ringRadius, y: point.y - ringRadius,
                              width: ringRadius * 2, height: ringRadius * 2)
            context.stroke(Path(ellipseIn: ring),
                           with: .color(.white.opacity(inset < 0.36 ? 0.20 : 0.10)),
                           lineWidth: 1)
        }

        let wellRadius = buttonSize * 0.30
        let well = CGRect(x: point.x - wellRadius, y: point.y - wellRadius,
                          width: wellRadius * 2, height: wellRadius * 2)
        context.fill(Path(ellipseIn: well.insetBy(dx: -buttonSize * 0.02, dy: -buttonSize * 0.02)),
                     with: .color(.black.opacity(0.55)))
        context.fill(Path(ellipseIn: well),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.01, green: 0.02, blue: 0.06),
                                                             Color(red: 0.05, green: 0.07, blue: 0.14)]),
                                           center: point,
                                           startRadius: 0,
                                           endRadius: wellRadius))
        context.stroke(Path(ellipseIn: well),
                       with: .linearGradient(Gradient(colors: [metalLight, metalDark]),
                                             startPoint: CGPoint(x: 0, y: well.minY),
                                             endPoint: CGPoint(x: 0, y: well.maxY)),
                       lineWidth: isPad ? 3 : 2)

        let boltRadius = max(1.4, buttonSize * 0.028)
        let inset = buttonSize * 0.14
        for boltPoint in [CGPoint(x: plate.minX + inset, y: plate.minY + inset),
                          CGPoint(x: plate.maxX - inset, y: plate.minY + inset),
                          CGPoint(x: plate.minX + inset, y: plate.maxY - inset),
                          CGPoint(x: plate.maxX - inset, y: plate.maxY - inset)] {
            let bolt = Path(ellipseIn: CGRect(x: boltPoint.x - boltRadius,
                                              y: boltPoint.y - boltRadius,
                                              width: boltRadius * 2,
                                              height: boltRadius * 2))
            context.fill(bolt, with: .color(metalLight))
            context.stroke(bolt, with: .color(.black.opacity(0.65)), lineWidth: 0.8)
        }
    }

    private func drawSill(in context: GraphicsContext, window: CGRect, floorTop: CGFloat) {
        let top = window.maxY + frameWidth * 0.5
        guard floorTop > top, layout.rightEdge > layout.leftEdge else { return }
        let sill = CGRect(x: layout.leftEdge, y: top,
                          width: layout.rightEdge - layout.leftEdge,
                          height: floorTop - top)
        context.fill(Path(sill),
                     with: .linearGradient(Gradient(colors: [metal, metalDark]),
                                           startPoint: CGPoint(x: 0, y: sill.minY),
                                           endPoint: CGPoint(x: 0, y: sill.maxY)))
        seam(context, from: CGPoint(x: sill.minX, y: sill.minY),
             to: CGPoint(x: sill.maxX, y: sill.minY))

        for fraction in [0.14, 0.32, 0.5, 0.68, 0.86] as [CGFloat] {
            lightBar(context,
                     center: CGPoint(x: sill.minX + sill.width * fraction, y: sill.midY),
                     length: sill.width * 0.09,
                     thickness: isPad ? 3.5 : 2.5,
                     color: cyan)
        }

        var lip = Path()
        lip.move(to: CGPoint(x: sill.minX, y: sill.maxY - 0.75))
        lip.addLine(to: CGPoint(x: sill.maxX, y: sill.maxY - 0.75))
        var glow = context
        glow.blendMode = .plusLighter
        glow.stroke(lip, with: .color(orange.opacity(0.35)), lineWidth: 5)
        context.stroke(lip, with: .color(orange), lineWidth: 1.5)
    }

    private func drawFloor(in context: GraphicsContext, size: CGSize, top: CGFloat, time: TimeInterval) {
        let bottom = size.height
        guard bottom > top else { return }
        let depth = bottom - top
        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: depth)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.46),
                                                             Color(red: 0.07, green: 0.11, blue: 0.25),
                                                             Color(red: 0.02, green: 0.04, blue: 0.11)]),
                                           startPoint: CGPoint(x: 0, y: top),
                                           endPoint: CGPoint(x: 0, y: bottom)))

        var glow = context
        glow.blendMode = .plusLighter
        let sheen = CGRect(x: size.width * 0.18, y: top - depth * 0.3,
                           width: size.width * 0.64, height: depth * 0.9)
        glow.fill(Path(ellipseIn: sheen),
                  with: .radialGradient(Gradient(colors: [cyan.opacity(0.14), cyan.opacity(0)]),
                                        center: CGPoint(x: sheen.midX, y: sheen.midY),
                                        startRadius: 0,
                                        endRadius: sheen.width * 0.5))

        // Layered shoulder consoles fill the space freed by the lifted answer
        // banks. Their converging edges carry the side cabinets into the floor
        // instead of ending at a flat horizontal strip.
        for side in [-1.0, 1.0] as [CGFloat] {
            let isLeft = side < 0
            let outer = isLeft ? CGFloat(0) : size.width
            let innerTop = size.width * (isLeft ? 0.31 : 0.69)
            let innerBottom = size.width * (isLeft ? 0.22 : 0.78)
            var shoulder = Path()
            shoulder.move(to: CGPoint(x: outer, y: top))
            shoulder.addLine(to: CGPoint(x: innerTop, y: top))
            shoulder.addLine(to: CGPoint(x: innerBottom, y: bottom))
            shoulder.addLine(to: CGPoint(x: outer, y: bottom))
            shoulder.closeSubpath()
            context.fill(shoulder,
                         with: .linearGradient(
                            Gradient(colors: [metalLight.opacity(0.62),
                                              metal,
                                              metalDark]),
                            startPoint: CGPoint(x: innerTop, y: top),
                            endPoint: CGPoint(x: outer, y: bottom)
                         ))
            context.stroke(shoulder, with: .color(.black.opacity(0.78)), lineWidth: isPad ? 4 : 2.5)

            let insetX = outer + side * size.width * 0.075
            let ventWidth = size.width * 0.085
            let ventHeight = max(8, depth * 0.13)
            let vent = CGRect(x: isLeft ? insetX : insetX - ventWidth,
                              y: top + depth * 0.43,
                              width: ventWidth,
                              height: ventHeight)
            drawVent(context, rect: vent)

            for row in [0.17, 0.72] as [CGFloat] {
                let y = top + depth * row
                let progress = (y - top) / max(1, depth)
                let x = innerTop + (innerBottom - innerTop) * progress
                lightBar(context,
                         center: CGPoint(x: x - side * size.width * 0.055, y: y),
                         length: size.width * 0.065,
                         thickness: isPad ? 4 : 2.5,
                         color: row < 0.5 ? orange : cyan)
            }
        }

        // A raised central runway frames the holographic character seal and
        // adds a second depth layer beneath the windscreen sill.
        var runway = Path()
        runway.move(to: CGPoint(x: size.width * 0.42, y: top))
        runway.addLine(to: CGPoint(x: size.width * 0.58, y: top))
        runway.addLine(to: CGPoint(x: size.width * 0.67, y: bottom))
        runway.addLine(to: CGPoint(x: size.width * 0.33, y: bottom))
        runway.closeSubpath()
        context.fill(runway,
                     with: .linearGradient(
                        Gradient(colors: [Color(red: 0.19, green: 0.29, blue: 0.53),
                                          Color(red: 0.055, green: 0.09, blue: 0.22),
                                          Color(red: 0.02, green: 0.035, blue: 0.10)]),
                        startPoint: CGPoint(x: size.width / 2, y: top),
                        endPoint: CGPoint(x: size.width / 2, y: bottom)
                     ))
        context.stroke(runway, with: .color(.black.opacity(0.82)), lineWidth: isPad ? 5 : 3)
        var runwayGlow = context
        runwayGlow.blendMode = .plusLighter
        runwayGlow.stroke(runway, with: .color(cyan.opacity(0.20)), lineWidth: isPad ? 9 : 6)

        let vanishing = CGPoint(x: size.width / 2, y: top - depth * 2.4)
        let topFraction = (top - vanishing.y) / (bottom - vanishing.y)
        for step in -7...7 {
            let x = size.width / 2 + CGFloat(step) * size.width * 0.11
            seam(context,
                 from: CGPoint(x: vanishing.x + (x - vanishing.x) * topFraction, y: top),
                 to: CGPoint(x: x, y: bottom))
        }
        for fraction in [0.12, 0.32, 0.62] as [CGFloat] {
            let y = top + depth * fraction
            seam(context, from: CGPoint(x: 0, y: y), to: CGPoint(x: size.width, y: y))
        }

        let lightRow = top + depth * 0.22
        let rowFraction = (lightRow - vanishing.y) / (bottom - vanishing.y)
        for step in [-3, -2, 2, 3] {
            let x = vanishing.x + (CGFloat(step) - 0.5 * CGFloat(step.signum())) * size.width * 0.11 * rowFraction
            lightBar(context,
                     center: CGPoint(x: x, y: lightRow),
                     length: size.width * 0.045 * rowFraction,
                     thickness: isPad ? 3 : 2,
                     color: cyan)
        }

        drawPlatform(in: context, size: size, floorDepth: depth, time: time)
    }

    private func drawPlatform(in context: GraphicsContext, size: CGSize, floorDepth: CGFloat, time: TimeInterval) {
        let width = min(size.width * 0.40, layout.windowRect.width * 0.62)
        let height = min(width * 0.30, floorDepth * 1.5)
        let pad = CGRect(x: size.width / 2 - width / 2,
                         y: size.height - height * 0.76,
                         width: width,
                         height: height)
        let centre = CGPoint(x: pad.midX, y: pad.midY)
        let pulse = 0.75 + 0.25 * sin(time * 1.6)

        context.fill(Path(ellipseIn: pad.insetBy(dx: -width * 0.04, dy: -height * 0.06)),
                     with: .color(.black.opacity(0.45)))
        context.fill(Path(ellipseIn: pad),
                     with: .linearGradient(Gradient(colors: [metalLight, metal, metalDark]),
                                           startPoint: CGPoint(x: 0, y: pad.minY),
                                           endPoint: CGPoint(x: 0, y: pad.maxY)))
        context.stroke(Path(ellipseIn: pad), with: .color(.black.opacity(0.7)), lineWidth: 2)

        for bolt in 0..<18 {
            let angle = Double(bolt) / 18 * 2 * .pi
            let point = CGPoint(x: centre.x + cos(angle) * width * 0.47,
                                y: centre.y + sin(angle) * height * 0.47)
            guard point.y < size.height - 2 else { continue }
            let radius = max(1.2, width * 0.006)
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(.white.opacity(0.35)))
        }

        let inner = pad.insetBy(dx: width * 0.09, dy: height * 0.09)
        context.fill(Path(ellipseIn: inner), with: .color(metalDark))

        var glow = context
        glow.blendMode = .plusLighter
        let ring = pad.insetBy(dx: width * 0.13, dy: height * 0.13)
        glow.stroke(Path(ellipseIn: ring), with: .color(cyan.opacity(0.35 * pulse)), lineWidth: isPad ? 12 : 8)
        context.stroke(Path(ellipseIn: ring), with: .color(cyan), lineWidth: isPad ? 2.5 : 1.8)

        let core = pad.insetBy(dx: width * 0.19, dy: height * 0.19)
        context.fill(Path(ellipseIn: core),
                     with: .radialGradient(Gradient(colors: [cyan.opacity(0.85 * pulse),
                                                             blue.opacity(0.75),
                                                             Color(red: 0.02, green: 0.05, blue: 0.20)]),
                                           center: centre,
                                           startRadius: 0,
                                           endRadius: core.width * 0.5))
        context.stroke(Path(ellipseIn: pad.insetBy(dx: width * 0.27, dy: height * 0.27)),
                       with: .color(cyan.opacity(0.55)), lineWidth: isPad ? 2 : 1.4)
        context.stroke(Path(ellipseIn: pad.insetBy(dx: width * 0.34, dy: height * 0.34)),
                       with: .color(.white.opacity(0.35)), lineWidth: 1)
        drawCharacterMark(in: context,
                          centre: CGPoint(x: centre.x, y: centre.y - height * 0.02),
                          radius: min(width, height) * 0.20,
                          alpha: 0.92)
    }

    // MARK: Windshield

    private func drawSpace(in context: GraphicsContext, window: CGRect, cut: CGFloat, time: TimeInterval) {
        let glass = chamfered(window, cut: cut)
        context.drawLayer { space in
            space.clip(to: glass)
            space.fill(Path(window),
                       with: .linearGradient(Gradient(colors: [Color(red: 0.01, green: 0.01, blue: 0.07),
                                                               Color(red: 0.02, green: 0.03, blue: 0.16),
                                                               Color(red: 0.03, green: 0.08, blue: 0.28),
                                                               Color(red: 0.01, green: 0.04, blue: 0.14)]),
                                             startPoint: CGPoint(x: window.minX, y: window.minY),
                                             endPoint: CGPoint(x: window.maxX, y: window.maxY)))
            drawNebula(in: space, window: window)
            drawPlanet(in: space, window: window, time: time)
            drawMoon(in: space, window: window)

            for (width, opacity) in [(3.0, 0.16), (2.0, 0.20), (1.4, 0.28)] as [(CGFloat, Double)] {
                space.stroke(glass, with: .color(.black.opacity(opacity)), lineWidth: frameWidth * width)
            }

            var glare = Path()
            glare.move(to: CGPoint(x: window.minX + window.width * 0.08, y: window.minY))
            glare.addLine(to: CGPoint(x: window.minX + window.width * 0.26, y: window.minY))
            glare.addLine(to: CGPoint(x: window.minX, y: window.minY + window.height * 0.58))
            glare.addLine(to: CGPoint(x: window.minX, y: window.minY + window.height * 0.28))
            glare.closeSubpath()
            space.fill(glare, with: .color(.white.opacity(0.055)))

            let sheen = CGRect(x: window.minX, y: window.minY,
                               width: window.width, height: window.height * 0.16)
            space.fill(Path(sheen),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.07), .white.opacity(0)]),
                                             startPoint: CGPoint(x: sheen.minX, y: sheen.minY),
                                             endPoint: CGPoint(x: sheen.minX, y: sheen.maxY)))
        }
    }

    private func drawNebula(in context: GraphicsContext, window: CGRect) {
        let violet = Color(red: 0.48, green: 0.20, blue: 0.98)
        let fuchsia = Color(red: 0.92, green: 0.24, blue: 0.78)
        let ice = Color(red: 0.70, green: 0.82, blue: 1.00)
        let origin = CGPoint(x: window.minX + window.width * 0.27,
                             y: window.minY + window.height * 0.37)

        // The nebula is built from long, blurred ribbons instead of a cloud of
        // circles. That gives it a recognisable current and keeps it from
        // reading as one undefined purple object behind the gameplay.
        var upperRibbon = Path()
        upperRibbon.move(to: CGPoint(x: window.minX - window.width * 0.08,
                                     y: window.minY + window.height * 0.61))
        upperRibbon.addCurve(to: CGPoint(x: window.minX + window.width * 0.42,
                                         y: window.minY + window.height * 0.28),
                             control1: CGPoint(x: window.minX + window.width * 0.08,
                                               y: window.minY + window.height * 0.60),
                             control2: CGPoint(x: window.minX + window.width * 0.19,
                                               y: window.minY + window.height * 0.22))
        upperRibbon.addCurve(to: CGPoint(x: window.minX + window.width * 0.78,
                                         y: window.minY + window.height * 0.16),
                             control1: CGPoint(x: window.minX + window.width * 0.56,
                                               y: window.minY + window.height * 0.34),
                             control2: CGPoint(x: window.minX + window.width * 0.66,
                                               y: window.minY + window.height * 0.12))

        var lowerRibbon = Path()
        lowerRibbon.move(to: CGPoint(x: window.minX - window.width * 0.10,
                                     y: window.minY + window.height * 0.78))
        lowerRibbon.addCurve(to: CGPoint(x: window.minX + window.width * 0.36,
                                         y: window.minY + window.height * 0.43),
                             control1: CGPoint(x: window.minX + window.width * 0.08,
                                               y: window.minY + window.height * 0.72),
                             control2: CGPoint(x: window.minX + window.width * 0.14,
                                               y: window.minY + window.height * 0.36))
        lowerRibbon.addCurve(to: CGPoint(x: window.minX + window.width * 0.72,
                                         y: window.minY + window.height * 0.34),
                             control1: CGPoint(x: window.minX + window.width * 0.50,
                                               y: window.minY + window.height * 0.55),
                             control2: CGPoint(x: window.minX + window.width * 0.61,
                                               y: window.minY + window.height * 0.27))

        context.drawLayer { haze in
            haze.blendMode = .plusLighter
            haze.addFilter(.blur(radius: window.height * 0.035))
            haze.stroke(upperRibbon,
                        with: .linearGradient(Gradient(colors: [violet.opacity(0),
                                                                 violet.opacity(0.34),
                                                                 fuchsia.opacity(0.25),
                                                                 ice.opacity(0)]),
                                              startPoint: CGPoint(x: window.minX, y: origin.y),
                                              endPoint: CGPoint(x: window.maxX, y: origin.y)),
                        style: StrokeStyle(lineWidth: window.height * 0.18,
                                           lineCap: .round,
                                           lineJoin: .round))
            haze.stroke(lowerRibbon,
                        with: .linearGradient(Gradient(colors: [fuchsia.opacity(0),
                                                                 fuchsia.opacity(0.24),
                                                                 violet.opacity(0.28),
                                                                 violet.opacity(0)]),
                                              startPoint: CGPoint(x: window.minX, y: origin.y),
                                              endPoint: CGPoint(x: window.maxX, y: origin.y)),
                        style: StrokeStyle(lineWidth: window.height * 0.13,
                                           lineCap: .round,
                                           lineJoin: .round))
        }

        context.drawLayer { filaments in
            filaments.blendMode = .plusLighter
            filaments.addFilter(.blur(radius: window.height * 0.010))
            filaments.stroke(upperRibbon,
                             with: .linearGradient(Gradient(colors: [violet.opacity(0),
                                                                      ice.opacity(0.22),
                                                                      fuchsia.opacity(0.34),
                                                                      violet.opacity(0)]),
                                                   startPoint: CGPoint(x: window.minX, y: origin.y),
                                                   endPoint: CGPoint(x: window.maxX, y: origin.y)),
                             style: StrokeStyle(lineWidth: window.height * 0.032,
                                                lineCap: .round,
                                                lineJoin: .round))
            filaments.stroke(lowerRibbon,
                             with: .color(violet.opacity(0.23)),
                             style: StrokeStyle(lineWidth: window.height * 0.022,
                                                lineCap: .round,
                                                lineJoin: .round))
        }

        // A dark seam provides contrast and makes the coloured gas feel
        // layered instead of uniformly luminous.
        var dustLane = context
        dustLane.blendMode = .multiply
        dustLane.stroke(upperRibbon,
                        with: .color(Color(red: 0.02, green: 0.01, blue: 0.10).opacity(0.46)),
                        style: StrokeStyle(lineWidth: window.height * 0.018,
                                           lineCap: .round,
                                           lineJoin: .round))

        var core = context
        core.blendMode = .plusLighter
        let coreRadius = window.height * 0.15
        core.fill(Path(ellipseIn: CGRect(x: origin.x - coreRadius,
                                         y: origin.y - coreRadius * 0.62,
                                         width: coreRadius * 2,
                                         height: coreRadius * 1.24)),
                  with: .radialGradient(Gradient(stops: [
                    .init(color: .white.opacity(0.62), location: 0),
                    .init(color: ice.opacity(0.26), location: 0.20),
                    .init(color: fuchsia.opacity(0.20), location: 0.48),
                    .init(color: violet.opacity(0), location: 1)
                  ]),
                  center: origin,
                  startRadius: 0,
                  endRadius: coreRadius))

        // Dust follows the same two currents, with dense grains near the core
        // and sparse blue-violet grains at the tips.
        let dust = Color(red: 0.91, green: 0.92, blue: 1.00)
        for index in 0..<190 {
            let t = random(index, 11)
            let branch = index.isMultiple(of: 2) ? -1.0 : 1.0
            let x = window.minX + window.width * (-0.04 + t * 0.80)
            let wave = sin(Double(t) * .pi * 2.15 + branch * 0.55)
            let centreY = window.minY + window.height * (0.50 - t * 0.34 + CGFloat(wave) * 0.10)
            let spread = (random(index, 12) - 0.5) * window.height * (0.05 + t * 0.08)
            let y = centreY + spread * CGFloat(branch)
            let dot = 0.35 + random(index, 14) * (isPad ? 1.45 : 1.05)
            let tint = index.isMultiple(of: 6) ? ice : dust
            core.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2,
                                             width: dot, height: dot)),
                      with: .color(tint.opacity(0.20 + Double(random(index, 15)) * 0.58)))
        }
    }

    private func drawStars(in context: GraphicsContext, window: CGRect, time: TimeInterval) {
        var glow = context
        glow.blendMode = .plusLighter
        let count = min(320, Int(window.width * window.height / 900))
        for index in 0..<count {
            let sample = Self.starSamples[index]
            let depth = sample.depth
            let speed = 0.002 + depth * 0.006
            let x = window.minX + wrap(sample.x - CGFloat(time) * speed) * window.width
            let y = window.minY + sample.y * window.height
            let radius = 0.35 + depth * depth * (isPad ? 1.9 : 1.4)
            let twinkle = 0.55 + 0.45 * sin(time * sample.twinkleRate + Double(index))
            let tint = index.isMultiple(of: 7) ? Color(red: 0.70, green: 0.85, blue: 1.00) : .white
            glow.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                             width: radius * 2, height: radius * 2)),
                      with: .color(tint.opacity(twinkle * (0.4 + Double(depth) * 0.6))))

            guard depth > 0.93 else { continue }
            let arm = radius * 4.5
            var sparkle = Path()
            sparkle.move(to: CGPoint(x: x - arm, y: y))
            sparkle.addLine(to: CGPoint(x: x + arm, y: y))
            sparkle.move(to: CGPoint(x: x, y: y - arm))
            sparkle.addLine(to: CGPoint(x: x, y: y + arm))
            glow.stroke(sparkle, with: .color(tint.opacity(0.55 * twinkle)), lineWidth: 0.7)
            glow.fill(Path(ellipseIn: CGRect(x: x - arm, y: y - arm, width: arm * 2, height: arm * 2)),
                      with: .radialGradient(Gradient(colors: [tint.opacity(0.30 * twinkle), tint.opacity(0)]),
                                            center: CGPoint(x: x, y: y),
                                            startRadius: 0,
                                            endRadius: arm))
        }
    }

    /// A handful of slow, depth-sorted rocks makes the glass feel like a real
    /// window instead of a painted backdrop, without competing with the sum or
    /// the answer controls.
    private func drawAsteroids(in context: GraphicsContext,
                               window: CGRect,
                               time: TimeInterval) {
        for index in 0..<9 {
            let depth = 0.28 + random(index, 71) * 0.72
            let direction: CGFloat = index.isMultiple(of: 4) ? -1 : 1
            let travel = CGFloat(time) * (0.0022 + depth * 0.0042) * direction
            let x = window.minX + wrap(random(index, 72) + travel) * window.width
            let baseY = window.minY + (0.10 + random(index, 73) * 0.73) * window.height
            let y = baseY + sin(time * (0.18 + Double(depth) * 0.15) + Double(index)) * window.height * 0.008
            let radius = window.height * (0.009 + pow(depth, 1.7) * 0.030)
            let rotationDirection: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let rotation = CGFloat(time) * (0.035 + random(index, 74) * 0.075) * rotationDirection
            let squash = 0.76 + random(index, 70) * 0.38

            var points: [CGPoint] = []
            for vertex in 0..<10 {
                let angle = CGFloat(vertex) / 10 * .pi * 2 + rotation
                let variance = 0.72 + random(index * 10 + vertex, 75) * 0.38
                points.append(CGPoint(x: x + cos(angle) * radius * variance,
                                      y: y + sin(angle) * radius * variance * squash))
            }

            var rock = Path()
            for (vertex, point) in points.enumerated() {
                vertex == 0 ? rock.move(to: point) : rock.addLine(to: point)
            }
            rock.closeSubpath()

            if depth > 0.72 {
                var halo = context
                halo.blendMode = .plusLighter
                halo.addFilter(.blur(radius: radius * 0.20))
                halo.stroke(rock, with: .color(cyan.opacity(0.08)), lineWidth: radius * 0.24)
            }

            context.fill(rock,
                         with: .linearGradient(Gradient(stops: [
                            .init(color: Color(red: 0.62, green: 0.64, blue: 0.70), location: 0),
                            .init(color: Color(red: 0.25, green: 0.25, blue: 0.31), location: 0.46),
                            .init(color: Color(red: 0.045, green: 0.04, blue: 0.075), location: 1)
                         ]),
                         startPoint: CGPoint(x: x - radius * 0.75, y: y - radius),
                         endPoint: CGPoint(x: x + radius, y: y + radius)))

            // Broad mineral facets break up the computer-perfect polygon and
            // stay legible even on the smaller iPhone playfield.
            for facet in 0..<4 {
                let first = (facet * 2 + index) % points.count
                let second = (first + 1 + facet % 2) % points.count
                var face = Path()
                face.move(to: CGPoint(x: x + (random(index + facet, 90) - 0.5) * radius * 0.20,
                                      y: y + (random(index + facet, 91) - 0.5) * radius * 0.16))
                face.addLine(to: points[first])
                face.addLine(to: points[second])
                face.closeSubpath()
                let facetColor = facet.isMultiple(of: 2)
                    ? Color.white.opacity(0.055 + Double(depth) * 0.04)
                    : Color(red: 0.18, green: 0.15, blue: 0.25).opacity(0.22)
                context.fill(face, with: .color(facetColor))
            }

            var litRim = Path()
            litRim.move(to: points[6])
            for vertex in 7..<10 { litRim.addLine(to: points[vertex]) }
            litRim.addLine(to: points[0])
            context.stroke(litRim,
                           with: .color(Color(red: 0.78, green: 0.82, blue: 0.92)
                            .opacity(0.22 + Double(depth) * 0.20)),
                           lineWidth: depth > 0.7 ? 1.35 : 0.75)
            context.stroke(rock, with: .color(.black.opacity(0.55)), lineWidth: depth > 0.7 ? 1.1 : 0.65)

            let craterCount = depth > 0.62 ? 3 : 2
            for crater in 0..<craterCount {
                let craterRadius = radius * (0.12 + random(index * 3 + crater, 77) * 0.13)
                let craterPoint = CGPoint(x: x + (random(index * 5 + crater, 78) - 0.54) * radius * 0.82,
                                          y: y + (random(index * 7 + crater, 79) - 0.52) * radius * 0.64)
                let craterRect = CGRect(x: craterPoint.x - craterRadius,
                                        y: craterPoint.y - craterRadius * 0.66,
                                        width: craterRadius * 2,
                                        height: craterRadius * 1.32)
                context.fill(Path(ellipseIn: craterRect),
                             with: .radialGradient(Gradient(colors: [Color.black.opacity(0.48),
                                                                      Color.black.opacity(0.12)]),
                                                   center: CGPoint(x: craterPoint.x + craterRadius * 0.18,
                                                                   y: craterPoint.y + craterRadius * 0.12),
                                                   startRadius: 0,
                                                   endRadius: craterRadius))
                context.stroke(Path(ellipseIn: craterRect.offsetBy(dx: -craterRadius * 0.08,
                                                                   dy: -craterRadius * 0.08)),
                               with: .color(.white.opacity(0.12 + Double(depth) * 0.06)),
                               lineWidth: max(0.45, radius * 0.035))
            }

            // Close foreground rocks shed a few tiny fragments in the opposite
            // direction of travel, reinforcing speed without adding streaks.
            if depth > 0.76 {
                for fragment in 0..<3 {
                    let gap = radius * (1.30 + CGFloat(fragment) * 0.42)
                    let fx = x - gap * direction
                    let fy = y + (random(index * 3 + fragment, 96) - 0.5) * radius
                    let dot = radius * (0.055 + random(fragment, 97) * 0.045)
                    context.fill(Path(ellipseIn: CGRect(x: fx - dot, y: fy - dot,
                                                        width: dot * 2, height: dot * 2)),
                                 with: .color(Color(red: 0.55, green: 0.57, blue: 0.66)
                                    .opacity(0.25 + Double(depth) * 0.25)))
                }
            }
        }
    }

    /// A very faint animated rim over the planet suggests slow atmospheric
    /// rotation while keeping the expensive planet texture on the static layer.
    private func drawAtmosphereShimmer(in context: GraphicsContext,
                                       window: CGRect,
                                       time: TimeInterval) {
        let radius = min(window.height * 0.80, window.width * 0.42)
        let centre = CGPoint(x: window.maxX - radius * 0.32,
                             y: window.maxY + radius * 0.40)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        var glow = context
        glow.blendMode = .plusLighter
        let start = Angle.radians(time * 0.05)
        let end = Angle.radians(time * 0.05 + 1.15)
        let arc = Path { path in
            path.addArc(center: centre,
                        radius: radius * 1.008,
                        startAngle: start,
                        endAngle: end,
                        clockwise: false)
        }
        glow.stroke(arc, with: .color(.white.opacity(0.32)), lineWidth: isPad ? 3 : 2)
        glow.stroke(Path(ellipseIn: disc.insetBy(dx: -radius * 0.025, dy: -radius * 0.025)),
                    with: .color(cyan.opacity(0.07 + 0.04 * sin(time * 1.3))),
                    lineWidth: isPad ? 10 : 7)

        // Warm lights are grouped around the visible land masses. A slow,
        // offset pulse makes them feel like living places rather than a dotted
        // decorative ring pasted over the planet.
        let hubs = [CGPoint(x: -0.42, y: -0.46),
                    CGPoint(x: -0.18, y: -0.57),
                    CGPoint(x: 0.02, y: -0.44),
                    CGPoint(x: -0.20, y: -0.18),
                    CGPoint(x: -0.53, y: 0.05)]
        context.drawLayer { lights in
            lights.clip(to: Path(ellipseIn: disc))
            lights.blendMode = .plusLighter
            for index in 0..<34 {
                let hub = hubs[index % hubs.count]
                let px = centre.x + (hub.x + (random(index, 101) - 0.5) * 0.20) * radius
                let py = centre.y + (hub.y + (random(index, 102) - 0.5) * 0.13) * radius
                let pulse = 0.38 + 0.34 * (0.5 + 0.5 * sin(time * (0.75 + Double(random(index, 103))) + Double(index)))
                let dot = (isPad ? 1.05 : 0.75) + random(index, 104) * (isPad ? 1.25 : 0.90)
                let lightColor = index.isMultiple(of: 5)
                    ? Color(red: 1.00, green: 0.93, blue: 0.72)
                    : Color(red: 1.00, green: 0.64, blue: 0.25)
                lights.fill(Path(ellipseIn: CGRect(x: px - dot / 2, y: py - dot / 2,
                                                   width: dot, height: dot)),
                            with: .color(lightColor.opacity(pulse)))
            }
        }
    }

    private func drawPlatformPulse(in context: GraphicsContext,
                                   size: CGSize,
                                   time: TimeInterval) {
        let floorDepth = max(1, size.height - layout.windowRect.maxY)
        let width = min(size.width * 0.40, layout.windowRect.width * 0.62)
        let height = min(width * 0.30, floorDepth * 1.5)
        let pad = CGRect(x: size.width / 2 - width / 2,
                         y: size.height - height * 0.76,
                         width: width,
                         height: height)
        let ring = pad.insetBy(dx: width * 0.13, dy: height * 0.13)
        let pulse = 0.45 + 0.35 * (0.5 + 0.5 * sin(time * 1.8))
        var glow = context
        glow.blendMode = .plusLighter
        glow.stroke(Path(ellipseIn: ring),
                    with: .color(cyan.opacity(pulse)),
                    lineWidth: isPad ? 8 : 6)
        let scanner = ring.insetBy(dx: width * CGFloat(cockpitWrap(time * 0.22)) * 0.14,
                                   dy: height * CGFloat(cockpitWrap(time * 0.22)) * 0.14)
        glow.stroke(Path(ellipseIn: scanner),
                    with: .color(.white.opacity(0.18 * (1 - cockpitWrap(time * 0.22)))),
                    lineWidth: isPad ? 2 : 1.2)
    }

    private func drawPlanet(in context: GraphicsContext, window: CGRect, time: TimeInterval) {
        let radius = min(window.height * 0.80, window.width * 0.42)
        let centre = CGPoint(x: window.maxX - radius * 0.32, y: window.maxY + radius * 0.40)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        let planet = Path(ellipseIn: disc)

        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: disc.insetBy(dx: -radius * 0.25, dy: -radius * 0.25)),
                  with: .radialGradient(Gradient(stops: [
                    .init(color: cyan.opacity(0), location: 0.70),
                    .init(color: cyan.opacity(0.45), location: 0.80),
                    .init(color: blue.opacity(0.18), location: 0.88),
                    .init(color: blue.opacity(0), location: 1)
                  ]),
                  center: centre,
                  startRadius: 0,
                  endRadius: radius * 1.25))

        context.fill(planet,
                     with: .radialGradient(Gradient(colors: [Color(red: 0.42, green: 0.66, blue: 1.00),
                                                             Color(red: 0.06, green: 0.36, blue: 0.73),
                                                             Color(red: 0.015, green: 0.15, blue: 0.38),
                                                             Color(red: 0.005, green: 0.025, blue: 0.10)]),
                                           center: CGPoint(x: centre.x - radius * 0.45,
                                                           y: centre.y - radius * 0.55),
                                           startRadius: 0,
                                           endRadius: radius * 1.7))

        context.drawLayer { surface in
            surface.clip(to: planet)

            func earthPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: centre.x + x * radius, y: centre.y + y * radius)
            }

            // Stylised but coherent coastlines. Large, joined masses read as a
            // planet at a glance; the old collection of random ellipses looked
            // like spots sitting on top of a blue ball.
            var north = Path()
            north.move(to: earthPoint(-0.93, -0.63))
            north.addCurve(to: earthPoint(-0.62, -0.83),
                           control1: earthPoint(-0.86, -0.79),
                           control2: earthPoint(-0.73, -0.88))
            north.addCurve(to: earthPoint(-0.33, -0.73),
                           control1: earthPoint(-0.52, -0.80),
                           control2: earthPoint(-0.43, -0.69))
            north.addLine(to: earthPoint(-0.17, -0.56))
            north.addLine(to: earthPoint(-0.26, -0.42))
            north.addLine(to: earthPoint(-0.45, -0.39))
            north.addLine(to: earthPoint(-0.52, -0.22))
            north.addLine(to: earthPoint(-0.72, -0.30))
            north.addLine(to: earthPoint(-0.82, -0.45))
            north.closeSubpath()

            var europeAfrica = Path()
            europeAfrica.move(to: earthPoint(-0.36, -0.64))
            europeAfrica.addCurve(to: earthPoint(0.02, -0.71),
                                  control1: earthPoint(-0.23, -0.76),
                                  control2: earthPoint(-0.08, -0.65))
            europeAfrica.addLine(to: earthPoint(0.25, -0.55))
            europeAfrica.addLine(to: earthPoint(0.18, -0.40))
            europeAfrica.addLine(to: earthPoint(0.05, -0.34))
            europeAfrica.addCurve(to: earthPoint(-0.03, 0.20),
                                  control1: earthPoint(0.16, -0.08),
                                  control2: earthPoint(0.10, 0.10))
            europeAfrica.addLine(to: earthPoint(-0.22, 0.47))
            europeAfrica.addLine(to: earthPoint(-0.35, 0.19))
            europeAfrica.addLine(to: earthPoint(-0.43, -0.10))
            europeAfrica.addLine(to: earthPoint(-0.56, -0.27))
            europeAfrica.addLine(to: earthPoint(-0.45, -0.43))
            europeAfrica.closeSubpath()

            var south = Path()
            south.move(to: earthPoint(-0.70, -0.20))
            south.addCurve(to: earthPoint(-0.46, -0.12),
                           control1: earthPoint(-0.62, -0.28),
                           control2: earthPoint(-0.52, -0.23))
            south.addLine(to: earthPoint(-0.38, 0.06))
            south.addLine(to: earthPoint(-0.47, 0.30))
            south.addLine(to: earthPoint(-0.54, 0.61))
            south.addLine(to: earthPoint(-0.68, 0.74))
            south.addLine(to: earthPoint(-0.72, 0.44))
            south.addLine(to: earthPoint(-0.81, 0.19))
            south.addLine(to: earthPoint(-0.84, -0.03))
            south.closeSubpath()

            var asia = Path()
            asia.move(to: earthPoint(0.02, -0.72))
            asia.addCurve(to: earthPoint(0.72, -0.58),
                          control1: earthPoint(0.26, -0.84),
                          control2: earthPoint(0.53, -0.72))
            asia.addLine(to: earthPoint(0.86, -0.39))
            asia.addLine(to: earthPoint(0.64, -0.25))
            asia.addLine(to: earthPoint(0.44, -0.34))
            asia.addLine(to: earthPoint(0.30, -0.18))
            asia.addLine(to: earthPoint(0.15, -0.38))
            asia.addLine(to: earthPoint(-0.02, -0.47))
            asia.closeSubpath()

            let landMasses = [north, europeAfrica, south, asia]
            let landLight = Color(red: 0.42, green: 0.63, blue: 0.53)
            let landMid = Color(red: 0.17, green: 0.38, blue: 0.31)
            let landDark = Color(red: 0.075, green: 0.18, blue: 0.20)
            for (index, land) in landMasses.enumerated() {
                surface.fill(land,
                             with: .linearGradient(Gradient(colors: [landLight.opacity(index == 0 ? 0.92 : 0.82),
                                                                      landMid.opacity(0.94),
                                                                      landDark.opacity(0.98)]),
                                                   startPoint: earthPoint(-0.65, -0.82),
                                                   endPoint: earthPoint(0.50, 0.55)))
                surface.stroke(land,
                               with: .color(Color(red: 0.72, green: 0.87, blue: 0.74).opacity(0.24)),
                               lineWidth: max(0.7, radius * 0.006))
            }

            // Mountain and desert colour variation remains clipped inside the
            // coastlines so it enriches the land without creating new blobs.
            surface.drawLayer { terrain in
                terrain.clip(to: europeAfrica)
                terrain.fill(Path(ellipseIn: CGRect(x: earthPoint(-0.27, -0.11).x - radius * 0.18,
                                                     y: earthPoint(-0.27, -0.11).y - radius * 0.09,
                                                     width: radius * 0.36,
                                                     height: radius * 0.18)),
                             with: .color(Color(red: 0.76, green: 0.56, blue: 0.28).opacity(0.44)))
                var ridge = Path()
                ridge.move(to: earthPoint(-0.40, -0.48))
                ridge.addCurve(to: earthPoint(-0.03, -0.40),
                               control1: earthPoint(-0.27, -0.57),
                               control2: earthPoint(-0.15, -0.35))
                terrain.stroke(ridge,
                               with: .color(Color(red: 0.79, green: 0.76, blue: 0.62).opacity(0.38)),
                               lineWidth: radius * 0.025)
            }

            surface.drawLayer { terrain in
                terrain.clip(to: south)
                var ridge = Path()
                ridge.move(to: earthPoint(-0.71, -0.05))
                ridge.addCurve(to: earthPoint(-0.61, 0.61),
                               control1: earthPoint(-0.64, 0.15),
                               control2: earthPoint(-0.67, 0.43))
                terrain.stroke(ridge,
                               with: .color(Color(red: 0.68, green: 0.62, blue: 0.44).opacity(0.42)),
                               lineWidth: radius * 0.022)
            }

            // A single directional terminator makes the sphere dimensional.
            // It is laid over the terrain but under clouds and city lights.
            surface.fill(planet,
                         with: .radialGradient(Gradient(stops: [
                            .init(color: .clear, location: 0.38),
                            .init(color: .black.opacity(0.18), location: 0.67),
                            .init(color: .black.opacity(0.72), location: 1)
                         ]),
                         center: CGPoint(x: centre.x - radius * 0.35, y: centre.y - radius * 0.45),
                         startRadius: 0,
                         endRadius: radius * 1.6))

            // Cloud bands follow curved weather systems rather than sitting on
            // the globe as identical horizontal capsules.
            surface.drawLayer { clouds in
                clouds.blendMode = .plusLighter
                clouds.addFilter(.blur(radius: max(0.8, radius * 0.009)))
                for index in 0..<9 {
                    let t = CGFloat(index) / 8
                    let bandY = -0.70 + t * 1.22
                    let startX = -0.86 + random(index, 31) * 0.20
                    let endX = 0.72 - random(index, 32) * 0.18
                    var band = Path()
                    band.move(to: earthPoint(startX, bandY))
                    band.addCurve(to: earthPoint(endX, bandY + (random(index, 33) - 0.5) * 0.16),
                                  control1: earthPoint(-0.38, bandY - 0.13 + random(index, 34) * 0.10),
                                  control2: earthPoint(0.18, bandY + 0.12 - random(index, 35) * 0.10))
                    clouds.stroke(band,
                                  with: .color(.white.opacity(0.085 + Double(random(index, 36)) * 0.10)),
                                  style: StrokeStyle(lineWidth: radius * (0.018 + random(index, 37) * 0.018),
                                                     lineCap: .round))
                }
            }

            let cityHubs = [CGPoint(x: -0.43, y: -0.47),
                            CGPoint(x: -0.17, y: -0.57),
                            CGPoint(x: 0.02, y: -0.45),
                            CGPoint(x: -0.20, y: -0.17),
                            CGPoint(x: -0.54, y: 0.04)]
            var cityGlow = surface
            cityGlow.blendMode = .plusLighter
            for index in 0..<74 {
                let hub = cityHubs[index % cityHubs.count]
                let x = centre.x + (hub.x + (random(index, 41) - 0.5) * 0.22) * radius
                let y = centre.y + (hub.y + (random(index, 42) - 0.5) * 0.14) * radius
                let dot = 0.55 + random(index, 43) * (isPad ? 1.45 : 1.05)
                let color = index.isMultiple(of: 6)
                    ? Color(red: 1.00, green: 0.94, blue: 0.76)
                    : Color(red: 1.00, green: 0.66, blue: 0.28)
                cityGlow.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2,
                                                     width: dot, height: dot)),
                              with: .color(color.opacity(0.30 + Double(random(index, 45)) * 0.46)))
            }
        }

        glow.stroke(Path(ellipseIn: disc), with: .color(cyan.opacity(0.23)), lineWidth: isPad ? 11 : 8)
        glow.stroke(Path(ellipseIn: disc.insetBy(dx: 1, dy: 1)),
                    with: .color(Color(red: 0.63, green: 0.93, blue: 1.00).opacity(0.82)),
                    lineWidth: isPad ? 3 : 2)
    }

    private func drawWindowFrame(in context: GraphicsContext, window: CGRect, cut: CGFloat) {
        let width = frameWidth
        let frame = chamfered(window, cut: cut)
        // Outer shadow well, so the glass reads as recessed into the cabinet.
        context.stroke(chamfered(window, cut: cut, outset: width * 1.15),
                       with: .color(.black.opacity(0.55)),
                       lineWidth: width * 0.9)
        context.stroke(frame, with: .color(.black.opacity(0.85)), lineWidth: width + 14)
        context.stroke(frame,
                       with: .linearGradient(Gradient(colors: [metalLight, metal, metalDark, Color(red: 0.10, green: 0.13, blue: 0.22)]),
                                             startPoint: CGPoint(x: 0, y: window.minY - width),
                                             endPoint: CGPoint(x: 0, y: window.maxY + width)),
                       lineWidth: width)
        context.stroke(chamfered(window, cut: cut, outset: width * 0.55),
                       with: .color(.white.opacity(0.28)), lineWidth: 1.2)
        context.stroke(chamfered(window, cut: cut, outset: -width * 0.45),
                       with: .color(.black.opacity(0.9)), lineWidth: width * 0.35)

        var glow = context
        glow.blendMode = .plusLighter
        let rail = chamfered(window, cut: cut, outset: width * 0.34)
        glow.stroke(rail, with: .color(orange.opacity(0.50)), lineWidth: isPad ? 12 : 8)
        context.stroke(rail, with: .color(orange), lineWidth: isPad ? 3.4 : 2.4)
        context.stroke(chamfered(window, cut: cut, outset: width * 0.34),
                       with: .color(.white.opacity(0.55)),
                       lineWidth: 1)

        let neon = chamfered(window, cut: cut, outset: -width * 0.18)
        glow.stroke(neon, with: .color(cyan.opacity(0.55)), lineWidth: isPad ? 12 : 8)
        context.stroke(neon, with: .color(Color(red: 0.70, green: 0.95, blue: 1.00)),
                       lineWidth: isPad ? 2.8 : 1.8)

        for fraction in [0.22, 0.50, 0.78] as [CGFloat] {
            lightBar(context,
                     center: CGPoint(x: window.minX + window.width * fraction,
                                     y: window.minY - width * 0.02),
                     length: window.width * 0.10,
                     thickness: isPad ? 3.5 : 2.5,
                     color: cyan)
        }

        let boltRadius = width * 0.14
        for corner in [CGPoint(x: window.minX + cut * 0.45, y: window.minY + cut * 0.45),
                       CGPoint(x: window.maxX - cut * 0.45, y: window.minY + cut * 0.45),
                       CGPoint(x: window.minX + cut * 0.45, y: window.maxY - cut * 0.45),
                       CGPoint(x: window.maxX - cut * 0.45, y: window.maxY - cut * 0.45)] {
            let bolt = Path(ellipseIn: CGRect(x: corner.x - boltRadius, y: corner.y - boltRadius,
                                              width: boltRadius * 2, height: boltRadius * 2))
            context.fill(bolt,
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.8), metalLight, metalDark]),
                                               center: CGPoint(x: corner.x - boltRadius * 0.3,
                                                               y: corner.y - boltRadius * 0.3),
                                               startRadius: 0,
                                               endRadius: boltRadius))
            context.stroke(bolt, with: .color(.black.opacity(0.7)), lineWidth: 1)
        }
    }

    private func drawMoon(in context: GraphicsContext, window: CGRect) {
        let radius = window.height * 0.055
        let centre = CGPoint(x: window.maxX - window.width * 0.20,
                             y: window.minY + window.height * 0.15)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: disc),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 0.80, blue: 0.90),
                                                             Color(red: 0.28, green: 0.32, blue: 0.46)]),
                                           center: CGPoint(x: centre.x - radius * 0.3,
                                                           y: centre.y - radius * 0.3),
                                           startRadius: 0,
                                           endRadius: radius))
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: disc.insetBy(dx: -radius * 0.45, dy: -radius * 0.45)),
                  with: .radialGradient(Gradient(colors: [.white.opacity(0.20), .clear]),
                                        center: centre,
                                        startRadius: radius * 0.6,
                                        endRadius: radius * 1.5))
    }

    private func drawSpaceDust(in context: GraphicsContext, window: CGRect, time: TimeInterval) {
        var glow = context
        glow.blendMode = .plusLighter
        for index in 0..<42 {
            let depth = random(index, 81)
            let speed: CGFloat = 0.008 + depth * 0.02
            let x = window.minX + wrap(random(index, 82) - CGFloat(time) * speed) * window.width
            let y = window.minY + wrap(random(index, 83) + CGFloat(time) * speed * 0.15) * window.height
            let radius: CGFloat = 0.4 + depth * (isPad ? 1.6 : 1.1)
            let tint = index.isMultiple(of: 5) ? cyan : Color.white
            glow.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                      with: .color(tint.opacity(0.25 + Double(depth) * 0.45)))
        }
    }

    private func drawGalaxyShimmer(in context: GraphicsContext, window: CGRect, time: TimeInterval) {
        var glow = context
        glow.blendMode = .plusLighter
        let origin = CGPoint(x: window.minX + window.width * 0.30,
                             y: window.minY + window.height * 0.40)
        let breathe = 0.08 + 0.05 * sin(time * 0.7)
        let radius = window.height * 0.22
        glow.fill(Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius * 0.65,
                                         width: radius * 2, height: radius * 1.3)),
                  with: .radialGradient(Gradient(colors: [Color(red: 0.85, green: 0.55, blue: 1).opacity(breathe),
                                                          .clear]),
                                        center: origin,
                                        startRadius: 0,
                                        endRadius: radius))
    }

    private func drawCabinetPulse(in context: GraphicsContext, window: CGRect, time: TimeInterval) {
        let pulse = 0.18 + 0.16 * (0.5 + 0.5 * sin(time * 1.4))
        var glow = context
        glow.blendMode = .plusLighter
        let rail = chamfered(window, cut: min(window.width, window.height) * 0.11,
                             outset: frameWidth * 0.34)
        glow.stroke(rail, with: .color(orange.opacity(pulse)), lineWidth: isPad ? 7 : 5)
        let neon = chamfered(window, cut: min(window.width, window.height) * 0.11,
                             outset: -frameWidth * 0.18)
        glow.stroke(neon, with: .color(cyan.opacity(pulse * 0.7)), lineWidth: isPad ? 6 : 4)
    }

    /// A bespoke vector hologram for every selectable character. Nothing here
    /// is an image asset: the seal is assembled from paths, ellipses and light
    /// strokes, so it remains crisp when the cockpit scales to another device.
    private func drawCharacterMark(in context: GraphicsContext,
                                   centre: CGPoint,
                                   radius: CGFloat,
                                   alpha: Double) {
        var glow = context
        glow.blendMode = .plusLighter
        let accent = character.color
        let line = max(1.0, radius * 0.085)

        // Character identity sits inside an orbital badge shared by the fleet.
        let orbitWide = CGRect(x: centre.x - radius * 1.22,
                               y: centre.y - radius * 0.58,
                               width: radius * 2.44,
                               height: radius * 1.16)
        let orbitTall = CGRect(x: centre.x - radius * 0.84,
                               y: centre.y - radius * 0.92,
                               width: radius * 1.68,
                               height: radius * 1.84)
        glow.stroke(Path(ellipseIn: orbitWide),
                    with: .color(cyan.opacity(0.42 * alpha)),
                    lineWidth: line * 0.45)
        glow.stroke(Path(ellipseIn: orbitTall),
                    with: .color(accent.opacity(0.35 * alpha)),
                    lineWidth: line * 0.36)
        for index in 0..<5 {
            let angle = Double(index) / 5 * .pi * 2 - .pi / 2
            let star = CGPoint(x: centre.x + cos(angle) * radius * 1.10,
                               y: centre.y + sin(angle) * radius * 0.52)
            let dot = max(1.2, radius * (index == 0 ? 0.075 : 0.045))
            glow.fill(Path(ellipseIn: CGRect(x: star.x - dot, y: star.y - dot,
                                             width: dot * 2, height: dot * 2)),
                      with: .color((index.isMultiple(of: 2) ? accent : cyan)
                        .opacity(0.88 * alpha)))
        }

        func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: centre.x + x * radius,
                                   y: centre.y + y * radius,
                                   width: width * radius,
                                   height: height * radius))
        }
        func stroke(_ path: Path, color: Color = cyan, width: CGFloat = 1) {
            glow.stroke(path,
                        with: .color(color.opacity(0.92 * alpha)),
                        style: StrokeStyle(lineWidth: line * width,
                                           lineCap: .round,
                                           lineJoin: .round))
        }
        func fill(_ path: Path, color: Color = cyan, opacity: Double = 0.30) {
            glow.fill(path, with: .color(color.opacity(opacity * alpha)))
        }

        var face = Path()
        switch character.id {
        case "flying_penguin":
            face = ellipse(-0.58, -0.63, 1.16, 1.30)
            stroke(face, color: accent, width: 1.05)
            var mask = Path()
            mask.move(to: CGPoint(x: centre.x, y: centre.y - radius * 0.34))
            mask.addCurve(to: CGPoint(x: centre.x - radius * 0.39, y: centre.y + radius * 0.20),
                          control1: CGPoint(x: centre.x - radius * 0.10, y: centre.y - radius * 0.62),
                          control2: CGPoint(x: centre.x - radius * 0.50, y: centre.y - radius * 0.13))
            mask.move(to: CGPoint(x: centre.x, y: centre.y - radius * 0.34))
            mask.addCurve(to: CGPoint(x: centre.x + radius * 0.39, y: centre.y + radius * 0.20),
                          control1: CGPoint(x: centre.x + radius * 0.10, y: centre.y - radius * 0.62),
                          control2: CGPoint(x: centre.x + radius * 0.50, y: centre.y - radius * 0.13))
            stroke(mask, width: 0.68)
            var beak = Path()
            beak.move(to: CGPoint(x: centre.x, y: centre.y + radius * 0.04))
            beak.addLine(to: CGPoint(x: centre.x + radius * 0.22, y: centre.y + radius * 0.17))
            beak.addLine(to: CGPoint(x: centre.x, y: centre.y + radius * 0.27))
            beak.addLine(to: CGPoint(x: centre.x - radius * 0.22, y: centre.y + radius * 0.17))
            beak.closeSubpath()
            fill(beak, color: accent, opacity: 0.72)
            stroke(beak, color: accent, width: 0.55)

        case "bunny":
            let leftEar = ellipse(-0.49, -1.10, 0.36, 0.92)
            let rightEar = ellipse(0.13, -1.10, 0.36, 0.92)
            fill(leftEar, color: accent, opacity: 0.20)
            fill(rightEar, color: accent, opacity: 0.20)
            stroke(leftEar, color: accent)
            stroke(rightEar, color: accent)
            face = ellipse(-0.62, -0.54, 1.24, 1.18)
            stroke(face, width: 1.05)

        case "dog":
            face = ellipse(-0.60, -0.58, 1.20, 1.18)
            stroke(face, color: accent, width: 1.05)
            var ears = Path()
            ears.move(to: CGPoint(x: centre.x - radius * 0.42, y: centre.y - radius * 0.45))
            ears.addQuadCurve(to: CGPoint(x: centre.x - radius * 0.82, y: centre.y + radius * 0.08),
                              control: CGPoint(x: centre.x - radius * 0.90, y: centre.y - radius * 0.50))
            ears.addQuadCurve(to: CGPoint(x: centre.x - radius * 0.50, y: centre.y + radius * 0.23),
                              control: CGPoint(x: centre.x - radius * 0.66, y: centre.y + radius * 0.31))
            ears.move(to: CGPoint(x: centre.x + radius * 0.42, y: centre.y - radius * 0.45))
            ears.addQuadCurve(to: CGPoint(x: centre.x + radius * 0.82, y: centre.y + radius * 0.08),
                              control: CGPoint(x: centre.x + radius * 0.90, y: centre.y - radius * 0.50))
            ears.addQuadCurve(to: CGPoint(x: centre.x + radius * 0.50, y: centre.y + radius * 0.23),
                              control: CGPoint(x: centre.x + radius * 0.66, y: centre.y + radius * 0.31))
            stroke(ears, color: accent, width: 1.08)
            stroke(ellipse(-0.34, 0.02, 0.68, 0.52), width: 0.55)

        case "lion":
            var mane = Path()
            let points = 18
            for index in 0...points {
                let angle = Double(index) / Double(points) * .pi * 2 - .pi / 2
                let spoke = index.isMultiple(of: 2) ? radius * 0.98 : radius * 0.76
                let point = CGPoint(x: centre.x + cos(angle) * spoke,
                                    y: centre.y + sin(angle) * spoke)
                if index == 0 {
                    mane.move(to: point)
                } else {
                    mane.addLine(to: point)
                }
            }
            mane.closeSubpath()
            fill(mane, color: accent, opacity: 0.20)
            stroke(mane, color: accent, width: 0.88)
            face = ellipse(-0.57, -0.54, 1.14, 1.20)
            fill(face, color: cyan, opacity: 0.10)
            stroke(face, width: 1.06)
            stroke(ellipse(-0.52, -0.66, 0.36, 0.34), color: accent, width: 0.65)
            stroke(ellipse(0.16, -0.66, 0.36, 0.34), color: accent, width: 0.65)

        case "octopus":
            var dome = Path()
            dome.move(to: CGPoint(x: centre.x - radius * 0.64, y: centre.y + radius * 0.05))
            dome.addQuadCurve(to: CGPoint(x: centre.x + radius * 0.64, y: centre.y + radius * 0.05),
                              control: CGPoint(x: centre.x, y: centre.y - radius * 0.98))
            stroke(dome, color: accent, width: 1.10)
            for index in 0..<5 {
                let x = (CGFloat(index) - 2) * radius * 0.27
                var tentacle = Path()
                tentacle.move(to: CGPoint(x: centre.x + x, y: centre.y + radius * 0.02))
                tentacle.addCurve(to: CGPoint(x: centre.x + x + (index.isMultiple(of: 2) ? -1 : 1) * radius * 0.13,
                                               y: centre.y + radius * 0.61),
                                  control1: CGPoint(x: centre.x + x - radius * 0.11, y: centre.y + radius * 0.24),
                                  control2: CGPoint(x: centre.x + x + radius * 0.14, y: centre.y + radius * 0.43))
                stroke(tentacle, color: index.isMultiple(of: 2) ? accent : cyan, width: 0.78)
            }

        case "crab":
            face = ellipse(-0.64, -0.38, 1.28, 0.86)
            stroke(face, color: accent, width: 1.08)
            for side in [-1.0, 1.0] as [CGFloat] {
                var claw = Path()
                claw.move(to: CGPoint(x: centre.x + side * radius * 0.55, y: centre.y - radius * 0.02))
                claw.addQuadCurve(to: CGPoint(x: centre.x + side * radius * 0.98, y: centre.y - radius * 0.35),
                                  control: CGPoint(x: centre.x + side * radius * 0.90, y: centre.y + radius * 0.10))
                claw.addQuadCurve(to: CGPoint(x: centre.x + side * radius * 0.72, y: centre.y - radius * 0.56),
                                  control: CGPoint(x: centre.x + side * radius * 1.02, y: centre.y - radius * 0.70))
                stroke(claw, color: accent, width: 0.95)
                stroke(ellipse(side < 0 ? -0.42 : 0.26, -0.64, 0.16, 0.30), width: 0.55)
            }

        case "elephant":
            face = ellipse(-0.52, -0.62, 1.04, 1.13)
            stroke(face, width: 1.05)
            let leftEar = ellipse(-0.91, -0.48, 0.70, 0.91)
            let rightEar = ellipse(0.21, -0.48, 0.70, 0.91)
            fill(leftEar, color: accent, opacity: 0.19)
            fill(rightEar, color: accent, opacity: 0.19)
            stroke(leftEar, color: accent, width: 0.86)
            stroke(rightEar, color: accent, width: 0.86)
            var trunk = Path()
            trunk.move(to: CGPoint(x: centre.x, y: centre.y + radius * 0.03))
            trunk.addCurve(to: CGPoint(x: centre.x + radius * 0.22, y: centre.y + radius * 0.70),
                           control1: CGPoint(x: centre.x - radius * 0.12, y: centre.y + radius * 0.34),
                           control2: CGPoint(x: centre.x - radius * 0.08, y: centre.y + radius * 0.66))
            stroke(trunk, color: accent, width: 1.0)

        case "bear":
            stroke(ellipse(-0.68, -0.76, 0.48, 0.48), color: accent, width: 0.85)
            stroke(ellipse(0.20, -0.76, 0.48, 0.48), color: accent, width: 0.85)
            face = ellipse(-0.64, -0.60, 1.28, 1.25)
            stroke(face, width: 1.08)
            stroke(ellipse(-0.34, 0.02, 0.68, 0.52), color: accent, width: 0.62)

        case "fox":
            var fox = Path()
            fox.move(to: CGPoint(x: centre.x - radius * 0.72, y: centre.y - radius * 0.82))
            fox.addLine(to: CGPoint(x: centre.x - radius * 0.52, y: centre.y + radius * 0.16))
            fox.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + radius * 0.65),
                             control: CGPoint(x: centre.x - radius * 0.34, y: centre.y + radius * 0.56))
            fox.addQuadCurve(to: CGPoint(x: centre.x + radius * 0.52, y: centre.y + radius * 0.16),
                             control: CGPoint(x: centre.x + radius * 0.34, y: centre.y + radius * 0.56))
            fox.addLine(to: CGPoint(x: centre.x + radius * 0.72, y: centre.y - radius * 0.82))
            fox.addLine(to: CGPoint(x: centre.x, y: centre.y - radius * 0.50))
            fox.closeSubpath()
            fill(fox, color: accent, opacity: 0.18)
            stroke(fox, color: accent, width: 1.03)

        default: // frog
            face = ellipse(-0.72, -0.46, 1.44, 1.02)
            stroke(face, color: accent, width: 1.05)
            stroke(ellipse(-0.62, -0.78, 0.52, 0.52), color: accent, width: 0.90)
            stroke(ellipse(0.10, -0.78, 0.52, 0.52), color: accent, width: 0.90)
            var smile = Path()
            smile.move(to: CGPoint(x: centre.x - radius * 0.40, y: centre.y + radius * 0.17))
            smile.addQuadCurve(to: CGPoint(x: centre.x + radius * 0.40, y: centre.y + radius * 0.17),
                               control: CGPoint(x: centre.x, y: centre.y + radius * 0.52))
            stroke(smile, width: 0.62)
        }

        // Consistent luminous facial anchors keep even the more abstract marks
        // friendly and legible at phone scale.
        if character.id != "crab" {
            for side in [-1.0, 1.0] as [CGFloat] {
                let eye = ellipse(side < 0 ? -0.31 : 0.19, -0.17, 0.12, 0.12)
                fill(eye, color: .white, opacity: 0.92)
            }
        }
        if !["flying_penguin", "octopus", "crab", "elephant", "frog"].contains(character.id) {
            var nose = Path()
            nose.move(to: CGPoint(x: centre.x, y: centre.y + radius * 0.05))
            nose.addLine(to: CGPoint(x: centre.x - radius * 0.10, y: centre.y + radius * 0.19))
            nose.addLine(to: CGPoint(x: centre.x + radius * 0.10, y: centre.y + radius * 0.19))
            nose.closeSubpath()
            fill(nose, color: accent, opacity: 0.88)
        }
    }

    // MARK: Helpers

    private func chamfered(_ rect: CGRect, cut: CGFloat, outset: CGFloat = 0) -> Path {
        let r = rect.insetBy(dx: -outset, dy: -outset)
        // Offsetting a 45° chamfer by d moves its axis cut by d · (2 − √2).
        let c = max(0, min(cut + outset * 0.586, min(r.width, r.height) * 0.5))
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.closeSubpath()
        return path
    }

    private func seam(_ context: GraphicsContext, from start: CGPoint, to end: CGPoint) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1.6)
        context.stroke(path.offsetBy(dx: 0.8, dy: 0.8), with: .color(.white.opacity(0.07)), lineWidth: 0.8)
    }

    private func lightBar(_ context: GraphicsContext,
                          center: CGPoint,
                          length: CGFloat,
                          thickness: CGFloat,
                          color: Color,
                          vertical: Bool = false) {
        let width = vertical ? thickness : length
        let height = vertical ? length : thickness
        let bar = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(roundedRect: bar.insetBy(dx: -thickness * 1.4, dy: -thickness * 1.4),
                       cornerRadius: thickness * 2),
                  with: .color(color.opacity(0.22)))
        context.fill(Path(roundedRect: bar, cornerRadius: thickness / 2), with: .color(color))
        context.fill(Path(roundedRect: bar.insetBy(dx: thickness * 0.3, dy: thickness * 0.3),
                          cornerRadius: thickness / 2),
                     with: .color(.white.opacity(0.55)))
    }

    /// A stable pseudo-random value in 0..<1, so the star field and planet
    /// surface are identical on every frame.
    private func random(_ index: Int, _ salt: Int) -> CGFloat {
        Self.seededValue(index, salt)
    }

    private static func seededValue(_ index: Int, _ salt: Int) -> CGFloat {
        var x = UInt64(truncatingIfNeeded: index &* 7919 &+ salt &* 104_729 &+ 1)
        x ^= x >> 33
        x &*= 0xff51afd7ed558ccd
        x ^= x >> 33
        x &*= 0xc4ceb9fe1a85ec53
        x ^= x >> 33
        return CGFloat(x % 10_000) / 10_000
    }

    private func wrap(_ value: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }
}
