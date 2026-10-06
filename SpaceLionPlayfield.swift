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
                $0.options.prefix(8).map(feedback(for:))
            } ?? []
            ZStack {
                SpaceshipCockpit(layout: metrics.cockpit,
                                 isPad: isPad,
                                 isRunning: isRunning && !reduceMotion,
                                 feedbacks: cockpitFeedbacks)

                if let round {
                    ForEach(Array(round.options.prefix(8).enumerated()), id: \.element.id) { index, option in
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
        .position(point)
        .disabled(!isLive || isMoving || tutorial.isRunning || playsLevelCompletion)
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        .accessibilityLabel(Text(verbatim: option.text))
        .accessibilityHint(Text(verbatim: "Answer \(index + 1)"))
        .accessibilityIdentifier("space-lion-answer-\(option.text)")
    }

    private func feedback(for option: AnswerOption) -> HoopFeedback {
        guard selectedOptionID == option.id, buttonHasContact else { return .none }
        return selectedWasCorrect ? .correct : .wrong
    }

    private func lion(metrics: Metrics) -> some View {
        // The large sprite's idle drift and slow tumble do not benefit from
        // 60 body evaluations per second. Explicit travel animations remain
        // display-synchronised by SwiftUI, while the time-driven pose stays
        // smooth at half the CPU invalidation rate.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
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
                                target: target,
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
                                     target: CGPoint,
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
                        target: target,
                        pressedDestination: pressedDestination,
                        token: token)
        }
    }

    private func reachButton(_ option: AnswerOption,
                             target: CGPoint,
                             pressedDestination: CGSize,
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
        }

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

        private var columnTop: CGFloat { topReserve + (isPad ? 12 : 6) }
        private var columnBottom: CGFloat {
            size.height - max(bottomReserve, isPad ? 16 : 8) - (isPad ? 6 : 2)
        }
        private var slotHeight: CGFloat { max(1, (columnBottom - columnTop) / 4) }

        var answerSize: CGFloat {
            min(slotHeight * 0.90, isPad ? 150 : 112, size.width * 0.16)
        }
        private var columnPadding: CGFloat { answerSize * 0.17 }
        private var leftX: CGFloat {
            max(leftReserve, isPad ? 16 : 8) + columnPadding + answerSize / 2
        }
        private var rightX: CGFloat {
            size.width - max(rightReserve, isPad ? 16 : 8) - columnPadding - answerSize / 2
        }

        /// Four controls in each side column, read top to bottom: the lowest
        /// values on the left wall, the highest on the right wall.
        var answerPoints: [CGPoint] {
            let rows = (0..<4).map { columnTop + slotHeight * (CGFloat($0) + 0.5) }
            return rows.map { CGPoint(x: leftX, y: $0) } + rows.map { CGPoint(x: rightX, y: $0) }
        }

        var cockpit: CockpitLayout {
            let leftEdge = leftX + answerSize / 2 + columnPadding
            let rightEdge = rightX - answerSize / 2 - columnPadding
            let gap: CGFloat = isPad ? 30 : 18
            let top = topReserve + (isPad ? 16 : 10)
            let bottom = max(top + 60, size.height * (isPad ? 0.76 : 0.78))
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

/// A soft pulse used by the wall plate around each control so the socket
/// breathes in time with the travelling lamps on top of it.
private func cockpitLampFlash(time: TimeInterval, phase: Double, lamp: Int) -> Double {
    let wave = sin(time * 4.2 + phase * 1.7 + Double(lamp) * .pi)
    return pow(max(0, wave), 3)
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
            return Palette(glow: Color(red: 1.00, green: 0.30, blue: 0.38),
                           highlight: Color(red: 1.00, green: 0.87, blue: 0.87),
                           deep: Color(red: 0.62, green: 0.02, blue: 0.12),
                           ink: Color(red: 0.32, green: 0.00, blue: 0.06))
        case .none, .inactive, .bypassed:
            return Palette(glow: Color(red: 0.16, green: 0.76, blue: 1.00),
                           highlight: Color(red: 0.84, green: 0.97, blue: 1.00),
                           deep: Color(red: 0.03, green: 0.24, blue: 0.78),
                           ink: Color(red: 0.00, green: 0.08, blue: 0.32))
        }
    }

    var body: some View {
        let colors = palette
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.10),
                                              Color(red: 0.16, green: 0.22, blue: 0.36)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .overlay(Circle().stroke(.black.opacity(0.8), lineWidth: size * 0.018))
                .padding(size * 0.19)

            Circle()
                .stroke(colors.glow, lineWidth: size * 0.05)
                .blur(radius: size * 0.032)
                .padding(size * 0.225)
            Circle()
                .stroke(colors.glow, lineWidth: size * 0.016)
                .padding(size * 0.22)

            cap(colors, diameter: size * 0.50)
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
                .fill(RadialGradient(colors: [colors.highlight, colors.glow, colors.deep],
                                     center: UnitPoint(x: 0.40, y: 0.30),
                                     startRadius: 0,
                                     endRadius: diameter * 0.66))
            Circle()
                .strokeBorder(colors.deep.opacity(0.9), lineWidth: diameter * 0.03)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.60), .white.opacity(0)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .frame(width: diameter * 0.68, height: diameter * 0.36)
                .offset(y: -diameter * 0.25)

            // White numerals with a hard ink edge and soft halo stay legible
            // on the bright cap in every feedback colour.
            Text(verbatim: text)
                .font(.system(size: diameter * 0.46, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.38)
                .frame(width: diameter * 0.80)
                .shadow(color: colors.ink, radius: 0, y: diameter * 0.025)
                .shadow(color: colors.ink.opacity(0.85), radius: diameter * 0.03)
                .shadow(color: colors.ink.opacity(0.55), radius: diameter * 0.09)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressed ? 0.92 : 1)
        .brightness(isPressed ? 0.10 : 0)
        .shadow(color: colors.glow.opacity(isPressed ? 1 : 0.65),
                radius: size * (isPressed ? 0.13 : 0.07))
    }
}

/// Gives every answer an immediate, tactile response while the lion begins its
/// longer flight toward the chosen control.
private struct SpaceAnswerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.17, dampingFraction: 0.60),
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
    let isPad: Bool
    let isRunning: Bool
    let feedbacks: [HoopFeedback]

    private let cyan = Color(red: 0.10, green: 0.72, blue: 1.00)
    private let blue = Color(red: 0.06, green: 0.30, blue: 0.86)
    private let orange = Color(red: 1.00, green: 0.56, blue: 0.10)
    private let metalLight = Color(red: 0.30, green: 0.37, blue: 0.54)
    private let metal = Color(red: 0.14, green: 0.19, blue: 0.33)
    private let metalDark = Color(red: 0.04, green: 0.06, blue: 0.14)

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
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isRunning)) { timeline in
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
        }

        drawAnimatedControls(in: context, window: window, time: time)
        drawPlatformPulse(in: context, size: size, time: time)
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
            let innerX = isLeft ? layout.leftEdge : layout.rightEdge
            let frameX = isLeft
                ? window.minX - frameWidth * 0.5
                : window.maxX + frameWidth * 0.5

            if point.y > window.minY + frameWidth, point.y < window.maxY - frameWidth {
                drawConduitPulses(in: context,
                                  from: innerX,
                                  to: frameX,
                                  y: point.y,
                                  phase: phase,
                                  time: time)
            }

            let feedback = index < feedbacks.count ? feedbacks[index] : .none
            drawControlLights(in: context,
                              at: point,
                              index: index,
                              feedback: feedback,
                              time: time)
        }
    }

    private func drawConduitPulses(in context: GraphicsContext,
                                   from startX: CGFloat,
                                   to endX: CGFloat,
                                   y: CGFloat,
                                   phase: Double,
                                   time: TimeInterval) {
        var glow = context
        glow.blendMode = .plusLighter
        let spacing = layout.buttonSize * 0.12
        for cable in 0..<2 {
            let cableY = y + (cable == 0 ? -spacing : spacing)
            let progress = CGFloat(cockpitWrap(time * 0.9 + phase * 0.23 + Double(cable) * 0.5))
            let pulse = CGPoint(x: startX + (endX - startX) * progress, y: cableY)
            let radius: CGFloat = isPad ? 9 : 6
            glow.fill(Path(ellipseIn: CGRect(x: pulse.x - radius,
                                             y: pulse.y - radius,
                                             width: radius * 2,
                                             height: radius * 2)),
                      with: .radialGradient(Gradient(colors: [.white.opacity(0.9),
                                                              cyan.opacity(0.7),
                                                              cyan.opacity(0)]),
                                            center: pulse,
                                            startRadius: 0,
                                            endRadius: radius))
        }
    }

    /// All eight lamp rings share the cockpit's single animation canvas.
    private func drawControlLights(in context: GraphicsContext,
                                   at centre: CGPoint,
                                   index controlIndex: Int,
                                   feedback: HoopFeedback,
                                   time: TimeInterval) {
        var glow = context
        glow.blendMode = .plusLighter
        let buttonSize = layout.buttonSize
        let phase = Double(controlIndex)
        let excited = feedback != .none && feedback != .inactive && feedback != .bypassed
        let lampColor = controlLampColor(for: feedback)
        let direction: Double = controlIndex < 4 ? 1 : -1
        let spin = time * (excited ? 1.35 : 0.55) * direction + phase * 0.12
        let chase = cockpitWrap(time * (excited ? 2.4 : 1.15) * direction + phase * 0.31)
        let orbit = buttonSize * 0.385
        let radius = buttonSize * 0.032

        let plate = CGRect(x: centre.x - buttonSize * 0.5,
                           y: centre.y - buttonSize * 0.5,
                           width: buttonSize,
                           height: buttonSize)
        let platePulse = 0.55 + 0.45 * cockpitLampFlash(time: time, phase: phase, lamp: 0)
        glow.stroke(chamfered(plate, cut: buttonSize * 0.24),
                    with: .color(lampColor.opacity(0.18 * platePulse)),
                    lineWidth: isPad ? 8 : 5)

        for lampIndex in 0..<8 {
            let fraction = Double(lampIndex) / 8
            let angle = (fraction + spin) * 2 * .pi - .pi / 2
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * orbit,
                                y: centre.y + CGFloat(sin(angle)) * orbit)
            let behind = cockpitWrap(chase - fraction)
            let head = pow(max(0, 1 - behind / 0.42), 1.8)
            let pulse = 0.40 + 0.60 * max(0, sin(time * 6.4 + Double(lampIndex) * 0.9 + phase))
            let intensity = min(1, 0.22 + pulse * 0.45 + head * 0.70)

            let core = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            glow.fill(Path(ellipseIn: core),
                      with: .color(lampColor.opacity(0.35 + 0.65 * intensity)))
            glow.fill(Path(ellipseIn: core.insetBy(dx: radius * 0.35, dy: radius * 0.35)),
                      with: .color(Color.white.opacity(0.25 + 0.55 * intensity)))
            let halo = core.insetBy(dx: -radius * 2.4, dy: -radius * 2.4)
            glow.fill(Path(ellipseIn: halo),
                      with: .radialGradient(Gradient(colors: [lampColor.opacity(0.55 * intensity),
                                                              lampColor.opacity(0)]),
                                            center: point,
                                            startRadius: 0,
                                            endRadius: halo.width / 2))
        }
    }

    private func controlLampColor(for feedback: HoopFeedback) -> Color {
        switch feedback {
        case .correct, .revealedCorrect, .bonus:
            return Color(red: 0.20, green: 0.95, blue: 0.50)
        case .wrong:
            return Color(red: 1.00, green: 0.30, blue: 0.38)
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
    }

    private func drawColumn(in context: GraphicsContext,
                            size: CGSize,
                            minX: CGFloat,
                            maxX: CGFloat,
                            innerIsTrailing: Bool,
                            window: CGRect) {
        guard maxX > minX else { return }
        let rect = CGRect(x: minX, y: 0, width: maxX - minX, height: size.height)
        let innerX = innerIsTrailing ? maxX : minX
        let outerX = innerIsTrailing ? minX : maxX
        let inward: CGFloat = innerIsTrailing ? -1 : 1
        let buttonSize = layout.buttonSize

        context.fill(Path(rect),
                     with: .linearGradient(Gradient(colors: [metalDark, metal, metalLight]),
                                           startPoint: CGPoint(x: outerX, y: 0),
                                           endPoint: CGPoint(x: innerX, y: 0)))
        seam(context,
             from: CGPoint(x: outerX - inward * rect.width * 0.18, y: 0),
             to: CGPoint(x: outerX - inward * rect.width * 0.18, y: size.height))

        var edge = Path()
        edge.move(to: CGPoint(x: innerX, y: 0))
        edge.addLine(to: CGPoint(x: innerX, y: size.height))
        context.stroke(edge, with: .color(.black.opacity(0.8)), lineWidth: 4)
        context.stroke(edge.offsetBy(dx: inward * 2.5, dy: 0),
                       with: .color(.white.opacity(0.18)), lineWidth: 1)

        let mounts = layout.buttonPoints.enumerated().filter { $0.element.x > minX && $0.element.x < maxX }
        let points = mounts.map(\.element)
        let frameX = innerIsTrailing
            ? window.minX - frameWidth * 0.5
            : window.maxX + frameWidth * 0.5

        for (index, mount) in mounts.enumerated() {
            let point = mount.element

            if point.y > window.minY + frameWidth, point.y < window.maxY - frameWidth {
                drawConduits(in: context, from: innerX, to: frameX,
                             y: point.y)
            }

            drawButtonMount(in: context, at: point, size: buttonSize)

            guard index + 1 < points.count else { continue }
            let between = (point.y + points[index + 1].y) / 2
            seam(context,
                 from: CGPoint(x: minX, y: between),
                 to: CGPoint(x: maxX, y: between))
            lightBar(context,
                     center: CGPoint(x: innerX + inward * 7, y: between),
                     length: buttonSize * 0.16,
                     thickness: isPad ? 3.5 : 2.5,
                     color: cyan,
                     vertical: true)
        }
    }

    /// The octagonal plate, lamp groove and recessed well are part of the
    /// wall. The live cap and travelling lamps are laid over this socket.
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
                    with: .color(orange.opacity(0.20)),
                    lineWidth: buttonSize * 0.02)

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
                         y: size.height - height * 0.62,
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
                       with: .color(cyan.opacity(0.45)), lineWidth: 1)
    }

    // MARK: Windshield

    private func drawSpace(in context: GraphicsContext, window: CGRect, cut: CGFloat, time: TimeInterval) {
        let glass = chamfered(window, cut: cut)
        context.drawLayer { space in
            space.clip(to: glass)
            space.fill(Path(window),
                       with: .linearGradient(Gradient(colors: [Color(red: 0.01, green: 0.01, blue: 0.08),
                                                               Color(red: 0.03, green: 0.04, blue: 0.20),
                                                               Color(red: 0.04, green: 0.09, blue: 0.30)]),
                                             startPoint: CGPoint(x: window.minX, y: window.minY),
                                             endPoint: CGPoint(x: window.maxX, y: window.maxY)))
            drawNebula(in: space, window: window)
            drawPlanet(in: space, window: window, time: time)

            for (width, opacity) in [(3.0, 0.16), (2.0, 0.20), (1.4, 0.28)] as [(CGFloat, Double)] {
                space.stroke(glass, with: .color(.black.opacity(opacity)), lineWidth: frameWidth * width)
            }

            var glare = Path()
            glare.move(to: CGPoint(x: window.minX + window.width * 0.10, y: window.minY))
            glare.addLine(to: CGPoint(x: window.minX + window.width * 0.22, y: window.minY))
            glare.addLine(to: CGPoint(x: window.minX, y: window.minY + window.height * 0.62))
            glare.addLine(to: CGPoint(x: window.minX, y: window.minY + window.height * 0.36))
            glare.closeSubpath()
            space.fill(glare, with: .color(.white.opacity(0.035)))
        }
    }

    private func drawNebula(in context: GraphicsContext, window: CGRect) {
        var glow = context
        glow.blendMode = .plusLighter
        let start = CGPoint(x: window.minX + window.width * 0.42, y: window.minY - window.height * 0.05)
        let end = CGPoint(x: window.minX - window.width * 0.04, y: window.minY + window.height * 0.74)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let violet = Color(red: 0.50, green: 0.30, blue: 0.95)
        let magenta = Color(red: 0.75, green: 0.35, blue: 0.95)

        for index in 0..<18 {
            let t = CGFloat(index) / 17
            let wobble = sin(t * 7 + 1.3) * window.height * 0.05
            let centre = CGPoint(x: start.x + dx * t + normal.x * wobble,
                                 y: start.y + dy * t + normal.y * wobble)
            let radius = window.height * (0.08 + 0.10 * sin(t * .pi)) * (0.7 + random(index, 3) * 0.6)
            let color = index.isMultiple(of: 3) ? magenta : violet
            glow.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                             width: radius * 2, height: radius * 2)),
                      with: .radialGradient(Gradient(colors: [color.opacity(0.20), color.opacity(0)]),
                                            center: centre,
                                            startRadius: 0,
                                            endRadius: radius))
        }

        let dust = Color(red: 0.86, green: 0.80, blue: 1.00)
        for index in 0..<160 {
            let t = random(index, 11)
            let spread = (random(index, 12) + random(index, 13) - 1)
                * window.height * 0.13 * (0.4 + sin(t * .pi))
            let point = CGPoint(x: start.x + dx * t + normal.x * spread,
                                y: start.y + dy * t + normal.y * spread)
            let radius = 0.3 + random(index, 14) * 0.8
            glow.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                             width: radius * 2, height: radius * 2)),
                      with: .color(dust.opacity(0.25 + Double(random(index, 15)) * 0.5)))
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
        for index in 0..<7 {
            let depth = 0.35 + random(index, 71) * 0.65
            let travel = CGFloat(time) * (0.0025 + depth * 0.0035)
            let x = window.minX + wrap(random(index, 72) + travel) * window.width
            let y = window.minY + (0.12 + random(index, 73) * 0.70) * window.height
            let radius = window.height * (0.010 + depth * 0.022)
            let rotation = CGFloat(time) * (0.05 + random(index, 74) * 0.09)

            var rock = Path()
            for vertex in 0..<9 {
                let angle = CGFloat(vertex) / 9 * .pi * 2 + rotation
                let variance = 0.76 + random(index * 9 + vertex, 75) * 0.30
                let point = CGPoint(x: x + cos(angle) * radius * variance,
                                    y: y + sin(angle) * radius * variance)
                if vertex == 0 {
                    rock.move(to: point)
                } else {
                    rock.addLine(to: point)
                }
            }
            rock.closeSubpath()

            context.fill(rock,
                         with: .linearGradient(Gradient(colors: [Color(red: 0.30, green: 0.34, blue: 0.48),
                                                                  Color(red: 0.10, green: 0.11, blue: 0.20),
                                                                  .black]),
                                               startPoint: CGPoint(x: x - radius, y: y - radius),
                                               endPoint: CGPoint(x: x + radius, y: y + radius)))
            context.stroke(rock, with: .color(cyan.opacity(0.22 * Double(depth))), lineWidth: 0.8)

            for crater in 0..<2 {
                let craterRadius = radius * (0.13 + random(index * 3 + crater, 77) * 0.12)
                let craterPoint = CGPoint(x: x + (random(index * 4 + crater, 78) - 0.5) * radius,
                                          y: y + (random(index * 5 + crater, 79) - 0.5) * radius)
                context.fill(Path(ellipseIn: CGRect(x: craterPoint.x - craterRadius,
                                                     y: craterPoint.y - craterRadius,
                                                     width: craterRadius * 2,
                                                     height: craterRadius * 2)),
                             with: .color(.black.opacity(0.30)))
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
    }

    private func drawPlatformPulse(in context: GraphicsContext,
                                   size: CGSize,
                                   time: TimeInterval) {
        let floorDepth = max(1, size.height - layout.windowRect.maxY)
        let width = min(size.width * 0.40, layout.windowRect.width * 0.62)
        let height = min(width * 0.30, floorDepth * 1.5)
        let pad = CGRect(x: size.width / 2 - width / 2,
                         y: size.height - height * 0.62,
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
                                                             Color(red: 0.10, green: 0.36, blue: 0.86),
                                                             Color(red: 0.03, green: 0.14, blue: 0.46),
                                                             Color(red: 0.01, green: 0.04, blue: 0.16)]),
                                           center: CGPoint(x: centre.x - radius * 0.45,
                                                           y: centre.y - radius * 0.55),
                                           startRadius: 0,
                                           endRadius: radius * 1.7))

        context.drawLayer { surface in
            surface.clip(to: planet)
            let spin = CGFloat(time) * 0.0035
            let land = Color(red: 0.70, green: 0.76, blue: 0.90)
            for index in 0..<46 {
                let x = disc.minX + (wrap(random(index, 21) + spin) * 1.3 - 0.15) * disc.width
                let y = disc.minY + random(index, 22) * disc.height
                let width = radius * (0.10 + random(index, 23) * 0.26)
                let height = width * (0.35 + random(index, 24) * 0.35)
                surface.fill(Path(ellipseIn: CGRect(x: x - width / 2, y: y - height / 2,
                                                    width: width, height: height)),
                             with: .color(land.opacity(0.10 + Double(random(index, 25)) * 0.22)))
            }
            for index in 0..<22 {
                let x = disc.minX + (wrap(random(index, 31) + spin * 1.4) * 1.6 - 0.3) * disc.width
                let y = disc.minY + random(index, 32) * disc.height
                let width = radius * (0.30 + random(index, 33) * 0.30)
                let height = radius * (0.03 + random(index, 34) * 0.03)
                surface.fill(Path(roundedRect: CGRect(x: x - width / 2, y: y - height / 2,
                                                      width: width, height: height),
                                  cornerRadius: height / 2),
                             with: .color(.white.opacity(0.12 + Double(random(index, 35)) * 0.16)))
            }
            surface.fill(planet,
                         with: .radialGradient(Gradient(stops: [
                            .init(color: .clear, location: 0.45),
                            .init(color: .black.opacity(0.55), location: 1)
                         ]),
                         center: CGPoint(x: centre.x - radius * 0.35, y: centre.y - radius * 0.45),
                         startRadius: 0,
                         endRadius: radius * 1.6))
        }

        glow.stroke(Path(ellipseIn: disc), with: .color(cyan.opacity(0.25)), lineWidth: isPad ? 10 : 7)
        glow.stroke(Path(ellipseIn: disc.insetBy(dx: 1, dy: 1)),
                    with: .color(cyan.opacity(0.85)), lineWidth: isPad ? 3 : 2)
    }

    private func drawWindowFrame(in context: GraphicsContext, window: CGRect, cut: CGFloat) {
        let width = frameWidth
        let frame = chamfered(window, cut: cut)
        context.stroke(frame, with: .color(.black.opacity(0.7)), lineWidth: width + 10)
        context.stroke(frame,
                       with: .linearGradient(Gradient(colors: [metalLight, metal, metalDark, metal]),
                                             startPoint: CGPoint(x: 0, y: window.minY - width),
                                             endPoint: CGPoint(x: 0, y: window.maxY + width)),
                       lineWidth: width)
        context.stroke(chamfered(window, cut: cut, outset: width * 0.5),
                       with: .color(.white.opacity(0.18)), lineWidth: 1)
        context.stroke(chamfered(window, cut: cut, outset: -width * 0.5),
                       with: .color(.black.opacity(0.8)), lineWidth: 2)

        var glow = context
        glow.blendMode = .plusLighter
        let rail = chamfered(window, cut: cut, outset: width * 0.30)
        glow.stroke(rail, with: .color(orange.opacity(0.35)), lineWidth: isPad ? 9 : 6)
        context.stroke(rail, with: .color(orange), lineWidth: isPad ? 3.2 : 2.2)

        let neon = chamfered(window, cut: cut, outset: -width * 0.22)
        glow.stroke(neon, with: .color(cyan.opacity(0.45)), lineWidth: isPad ? 10 : 7)
        context.stroke(neon, with: .color(Color(red: 0.55, green: 0.90, blue: 1.00)),
                       lineWidth: isPad ? 2.6 : 1.8)

        for fraction in [0.24, 0.76] as [CGFloat] {
            lightBar(context,
                     center: CGPoint(x: window.minX + window.width * fraction,
                                     y: window.minY - width * 0.04),
                     length: window.width * 0.16,
                     thickness: isPad ? 3.5 : 2.5,
                     color: cyan)
        }

        let boltRadius = width * 0.13
        for corner in [CGPoint(x: window.minX + cut / 2, y: window.minY + cut / 2),
                       CGPoint(x: window.maxX - cut / 2, y: window.minY + cut / 2),
                       CGPoint(x: window.minX + cut / 2, y: window.maxY - cut / 2),
                       CGPoint(x: window.maxX - cut / 2, y: window.maxY - cut / 2)] {
            let bolt = Path(ellipseIn: CGRect(x: corner.x - boltRadius, y: corner.y - boltRadius,
                                              width: boltRadius * 2, height: boltRadius * 2))
            context.fill(bolt, with: .color(metalLight))
            context.stroke(bolt, with: .color(.black.opacity(0.7)), lineWidth: 1)
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
