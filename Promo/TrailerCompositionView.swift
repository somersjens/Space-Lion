//
//  TrailerCompositionView.swift
//  Space Lion
//
//  Deterministic landscape App Store teaser. Every frame is a function of
//  time, rendered at the Hungry Frog master sizes (1920×886 and 1600×1200)
//  with no status bar and no Dynamic Island. Answer pacing leaves each sum
//  readable before the character moves, the same way Math Steps does.
//

import SwiftUI

enum TrailerRuntime {
    static let exportFlag = "--export-app-store-teaser"
    static let stillExportFlag = "--export-app-store-stills"
    static var isStillExporting: Bool {
#if TRAILER_EXPORT
        ProcessInfo.processInfo.arguments.contains(stillExportFlag)
#else
        false
#endif
    }
    static var isExporting: Bool {
#if TRAILER_EXPORT
        ProcessInfo.processInfo.arguments.contains(exportFlag) || isStillExporting
#else
        false
#endif
    }
}

// MARK: - Edit

enum SpaceTrailerScript {
    static let outward = 0.58
    static let press = 0.07
    static let retract = 0.12
    static let home = 0.52
    static let spinTail = 0.10
    static let settleCorrect = 0.24
    static let settleWrong = 0.22
    static let entranceDuration = 1.28
    static let openingRead = 1.08
    static let betweenRead = 0.42
    static let characterRead = 0.58
    static let beforeTravel = 0.14
    static let travelDuration = 1.90
    static let afterTravelRead = 0.50
    static let finaleDelay = 0.12
    static let flyDuration = 0.76
    static let duration = 30.0

    struct Answer {
        let prompt: String
        let options: [String]
        let correctIndex: Int
        let chosenIndex: Int
        let characterID: String
        var isCorrect: Bool { chosenIndex == correctIndex }
    }

    /// Lion solves one, misses one, then solves it. Octopus, fox and frog
    /// each take a turn, the lion returns for one more, then the ship warps
    /// to the red planet and the ringed planet.
    static let answers: [Answer] = [
        Answer(prompt: "6 + 3 = ?", options: ["8", "9", "10", "7", "12", "6"],
               correctIndex: 1, chosenIndex: 1, characterID: "lion"),
        Answer(prompt: "4 × 2 = ?", options: ["7", "10", "9", "8", "6", "12"],
               correctIndex: 3, chosenIndex: 4, characterID: "lion"),
        Answer(prompt: "4 × 2 = ?", options: ["7", "10", "9", "8", "6", "12"],
               correctIndex: 3, chosenIndex: 3, characterID: "lion"),
        Answer(prompt: "9 + 6 = ?", options: ["14", "16", "15", "13", "18", "12"],
               correctIndex: 2, chosenIndex: 2, characterID: "octopus"),
        Answer(prompt: "7 × 3 = ?", options: ["18", "24", "20", "22", "28", "21"],
               correctIndex: 5, chosenIndex: 5, characterID: "fox"),
        Answer(prompt: "12 − 4 = ?", options: ["8", "7", "9", "6", "10", "4"],
               correctIndex: 0, chosenIndex: 0, characterID: "frog"),
        Answer(prompt: "5 × 5 = ?", options: ["20", "24", "30", "26", "25", "15"],
               correctIndex: 4, chosenIndex: 4, characterID: "lion"),
        Answer(prompt: "8 × 2 = ?", options: ["14", "16", "18", "12", "20", "10"],
               correctIndex: 1, chosenIndex: 1, characterID: "lion"),
        Answer(prompt: "15 − 6 = ?", options: ["8", "10", "7", "9", "12", "6"],
               correctIndex: 3, chosenIndex: 3, characterID: "lion")
    ]

    /// The lion's return answer and the red-planet answer each launch a warp.
    static let travelAfter: Set<Int> = [6, 7]

    struct Mark {
        let index: Int
        let answer: Answer
        let start: Double
        let stage: Int
        let questionFrom: Double
        var end: Double { start + SpaceTrailerScript.length(correct: answer.isCorrect) }
        var contact: Double { start + SpaceTrailerScript.outward }
    }

    struct Travel {
        let start: Double
        let fromStage: Int
        let toStage: Int
        var end: Double { start + SpaceTrailerScript.travelDuration }
        func progress(at time: Double) -> CGFloat {
            CGFloat(min(1, max(0, (time - start) / SpaceTrailerScript.travelDuration)))
        }
        func contains(_ time: Double) -> Bool { time >= start && time < end }
    }

    struct SoundCue {
        let resource: String
        let ext: String
        let time: Double
        let volume: Float
    }

    static func length(correct: Bool) -> Double {
        correct
            ? outward + press + retract + home + spinTail + settleCorrect
            : outward + press + home + settleWrong
    }

    static let plan: (marks: [Mark], travels: [Travel]) = {
        var marks: [Mark] = []
        var travels: [Travel] = []
        var cursor = entranceDuration + openingRead
        var stage = 1
        var questionFrom = 0.0
        for (index, answer) in answers.enumerated() {
            let mark = Mark(index: index, answer: answer, start: cursor,
                            stage: stage, questionFrom: questionFrom)
            marks.append(mark)
            cursor = mark.end
            if travelAfter.contains(index) {
                let travel = Travel(start: cursor + beforeTravel,
                                    fromStage: stage, toStage: stage + 1)
                travels.append(travel)
                stage += 1
                // The new sum takes over in the tunnel, while the buttons are
                // fully hidden, so the numbers that fade back in already match.
                questionFrom = travel.start + travelDuration * 0.50
                cursor = travel.end + afterTravelRead
            } else if index + 1 < answers.count {
                let next = answers[index + 1]
                if answer.isCorrect, next.prompt != answer.prompt {
                    questionFrom = mark.contact + 0.28
                }
                cursor += next.characterID == answer.characterID ? betweenRead : characterRead
            }
        }
        return (marks, travels)
    }()

    static var marks: [Mark] { plan.marks }
    static var travels: [Travel] { plan.travels }
    static var finaleStart: Double { (marks.last?.end ?? 0) + finaleDelay }
    static var iconStart: Double { finaleStart + flyDuration + 0.06 }

    static var soundCues: [SoundCue] {
        var cues = [
            SoundCue(resource: "sfx_session_start", ext: "caf", time: 0.18, volume: 0.70),
            SoundCue(resource: "sfx_character_unlock", ext: "caf", time: 0.42, volume: 0.68)
        ]
        for mark in marks {
            cues.append(SoundCue(resource: "sfx_button_press", ext: "caf",
                                 time: mark.contact, volume: 0.58))
            if mark.answer.isCorrect {
                cues.append(SoundCue(resource: "sfx_good", ext: "m4a",
                                     time: mark.contact + 0.02, volume: 0.86))
            } else {
                cues.append(SoundCue(resource: "sfx_wrong", ext: "m4a",
                                     time: mark.contact + 0.02, volume: 0.82))
            }
        }
        for travel in travels {
            cues.append(SoundCue(resource: "sfx_turbo", ext: "m4a",
                                 time: travel.start, volume: 0.46))
        }
        cues.append(SoundCue(resource: "sfx_level_complete", ext: "caf",
                             time: finaleStart, volume: 0.76))
        cues.append(SoundCue(resource: "sfx_end_screen_celebration", ext: "m4a",
                             time: iconStart, volume: 0.62))
        return cues
    }

    static func question(at time: Double) -> Mark {
        var shown = marks[0]
        for mark in marks where mark.questionFrom <= time {
            shown = mark
        }
        return shown
    }

    static func stage(at time: Double) -> Int {
        var stage = 1
        for travel in travels where time >= travel.start {
            stage = travel.toStage
        }
        return stage
    }

    static func correctDots(at time: Double) -> Int {
        let stage = stage(at: time)
        return marks.filter {
            $0.stage == stage && $0.answer.isCorrect && time >= $0.contact
        }.count
    }

    static func travel(at time: Double) -> Travel? {
        travels.first { $0.contains(time) }
    }

    /// Stage clocks: 100s, then 80s, then 70s. The clock waits during a warp
    /// and starts fresh when the new planet's question appears.
    static func clock(at time: Double) -> (remaining: Int, perQuestion: Int, stage: Int) {
        let durations = [100, 80, 70]
        let allowances = [10, 8, 7]
        var stage = 1
        var remaining = Double(durations[0])
        var cursor = entranceDuration
        for travel in travels {
            if time < travel.start {
                remaining -= max(0, time - cursor)
                let index = min(stage, allowances.count) - 1
                return (max(0, Int(ceil(remaining))), allowances[index], stage)
            }
            remaining -= max(0, travel.start - cursor)
            stage = travel.toStage
            let index = min(stage, durations.count) - 1
            remaining = Double(durations[index])
            if time < travel.end {
                return (Int(remaining), allowances[index], stage)
            }
            cursor = travel.end
        }
        let frozen = min(time, finaleStart)
        remaining -= max(0, frozen - cursor)
        let index = min(stage, allowances.count) - 1
        return (max(0, Int(ceil(remaining))), allowances[index], stage)
    }
}

// MARK: - Frame

struct TrailerCompositionView: View {
    static var duration: Double { SpaceTrailerScript.duration }

    let time: Double
    let outputSize: CGSize
    let isPad: Bool

    private var topInset: CGFloat { isPad ? 18 : 12 }
    private var topReserve: CGFloat { topInset + (isPad ? 118 : 78) }
    private var metrics: SpaceLionPlayfield.Metrics {
        SpaceLionPlayfield.Metrics(size: outputSize,
                                   topReserve: topReserve,
                                   bottomReserve: 0,
                                   leftReserve: 0,
                                   rightReserve: 0,
                                   isPad: isPad)
    }

    var body: some View {
        let metrics = metrics
        let icon = smooth((time - SpaceTrailerScript.iconStart) / 0.88)
        ZStack {
            gameplay(metrics: metrics)
                .blur(radius: CGFloat(icon) * (isPad ? 5 : 3.2))
            Color(red: 0.02, green: 0.04, blue: 0.12)
                .opacity(icon * 0.46)
            iconFinale(amount: icon)
        }
        .frame(width: outputSize.width, height: outputSize.height)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .dark)
    }

    private func gameplay(metrics: SpaceLionPlayfield.Metrics) -> some View {
        let travel = SpaceTrailerScript.travel(at: time)
        let question = SpaceTrailerScript.question(at: time)
        let actor = characterFrame(metrics: metrics)
        let weights = characterWeights
        let shake = travel.map { warpShake($0.progress(at: time)) } ?? 0
        let stage = cockpitStage(travel)
        let accent = CharacterCatalog.character(id: weights.max(by: { $0.opacity < $1.opacity })?.id ?? "lion")

        return ZStack {
            SpaceshipCockpit(layout: metrics.cockpit,
                             character: accent,
                             isPad: isPad,
                             isRunning: true,
                             sceneClock: SpaceSceneClock(trailerTime: time),
                             destinationStage: stage,
                             isTravelling: travel != nil,
                             feedbacks: buttonFeedbacks(question: question),
                             artworkRevision: 0,
                             drawsSynchronously: true,
                             frozenTime: time)

            if let travel {
                SpaceForwardJourney(window: metrics.cockpit.windowRect,
                                    previousStage: travel.fromStage,
                                    stage: travel.toStage,
                                    characterID: accent.id,
                                    isPad: isPad,
                                    journeyID: travel.toStage,
                                    reduceMotion: false,
                                    previewProgress: travel.progress(at: time),
                                    previewSceneryTime: time,
                                    onArrival: {})
            }

            answers(metrics: metrics, question: question)
            burst(metrics: metrics)

            ForEach(weights, id: \.id) { weight in
                character(CharacterCatalog.character(id: weight.id),
                          actor: actor,
                          metrics: metrics)
                    .opacity(weight.opacity)
            }

            if time >= SpaceTrailerScript.finaleStart, time < SpaceTrailerScript.iconStart {
                victoryBloom(metrics: metrics)
            }

            SpaceViewportGlass(window: metrics.cockpit.windowRect,
                               cut: min(metrics.cockpit.windowRect.width,
                                        metrics.cockpit.windowRect.height) * 0.11,
                               isRunning: true,
                               sceneClock: SpaceSceneClock(trailerTime: time),
                               frozenTime: time)

            hud(metrics: metrics, accent: accent)
                .opacity(hudOpacity)
        }
        .offset(x: shake)
    }

    // MARK: Motion

    private struct Actor {
        var offset = CGSize.zero
        var rotation = 0.0
        var scale: CGFloat = 1
        var pose = TrailerPose.resting
        var drift = CGSize.zero
    }

    private func characterFrame(metrics: SpaceLionPlayfield.Metrics) -> Actor {
        let lionSize = metrics.lionSize
        let sprung = spring(min(time, SpaceTrailerScript.entranceDuration + 0.4),
                            response: 1.22, damping: 0.78)
        let rise = (outputSize.height - metrics.centre.y + lionSize * 0.62) * CGFloat(1 - sprung)
        var actor = Actor()
        actor.scale = 0.78 + 0.22 * CGFloat(sprung)
        actor.rotation = -10 * (1 - sprung)
        let driftAmount = idleDriftAmount()
        let driftX = sin(time * 0.62) * lionSize * 0.075 * driftAmount
        let driftY = cos(time * 0.78) * lionSize * 0.062 * driftAmount
        actor.drift = CGSize(width: driftX, height: driftY)

        if time < SpaceTrailerScript.entranceDuration {
            // Ease the last of the rise into the resting hover. Cutting the
            // spring off at a fixed time tilted and shifted the lion just
            // before the first answer.
            let blend = smooth((time - (SpaceTrailerScript.entranceDuration - 0.42)) / 0.42)
            actor.offset.height = rise * CGFloat(1 - blend)
            actor.rotation = -10 * (1 - sprung) * (1 - blend) + sway(time) * blend
            return actor
        }

        if time >= SpaceTrailerScript.finaleStart {
            return finaleActor(base: actor, metrics: metrics)
        }

        guard let mark = SpaceTrailerScript.marks.first(where: { time >= $0.start && time < $0.end }) else {
            actor.rotation = landingAngle(before: time, metrics: metrics) + sway(time) * Double(driftAmount)
            actor.pose = TrailerPose.resting
            return actor
        }

        return answerActor(actor, mark: mark, metrics: metrics)
    }

    private func finaleActor(base: Actor, metrics: SpaceLionPlayfield.Metrics) -> Actor {
        var actor = base
        let fly = easeIn(min(1, (time - SpaceTrailerScript.finaleStart) / SpaceTrailerScript.flyDuration))
        let flyAmount = CGFloat(fly)
        actor.offset = CGSize(width: outputSize.width * 0.74 * flyAmount,
                              height: -outputSize.width * 0.18 * flyAmount)
        let landed = landingAngle(before: SpaceTrailerScript.finaleStart, metrics: metrics)
        actor.rotation = landed + 220 * fly
        actor.scale = 1 + 0.12 * flyAmount
        actor.pose = TrailerPose.pointing
        actor.drift = CGSize.zero
        return actor
    }

    private func answerActor(_ base: Actor,
                             mark: SpaceTrailerScript.Mark,
                             metrics: SpaceLionPlayfield.Metrics) -> Actor {
        var actor = base
        let local = time - mark.start
        let from = landingAngle(before: mark.start, metrics: metrics) + sway(mark.start)
        let aim = nearest(approachAngle(mark.answer.chosenIndex, metrics: metrics), to: from)
        let rotEase = unitBezier(min(1, local / (SpaceTrailerScript.outward * 0.48)),
                                 0.16, 0, 0.32, 1)
        var rotation = from + (aim - from) * rotEase
        let contact = contactOffset(index: mark.answer.chosenIndex, metrics: metrics)
        var offset = CGSize.zero
        var pose = TrailerPose.pointing

        let pressEnd = SpaceTrailerScript.outward + SpaceTrailerScript.press
        let homeStart = mark.answer.isCorrect ? pressEnd + SpaceTrailerScript.retract : pressEnd
        let homeEnd = homeStart + SpaceTrailerScript.home
        let spinEnd = mark.answer.isCorrect ? homeEnd + SpaceTrailerScript.spinTail : homeEnd
        let settleEnd = mark.end - mark.start

        if local < homeStart {
            let travel = unitBezier(min(1, local / SpaceTrailerScript.outward), 0.30, 0, 0.50, 1)
            offset = CGSize(width: contact.width * CGFloat(travel),
                            height: contact.height * CGFloat(travel))
            if mark.answer.isCorrect, local >= pressEnd {
                let fold = (local - pressEnd) / SpaceTrailerScript.retract
                pose = fold < 0.55 ? TrailerPose.reaching : TrailerPose.tucked
            }
        } else if local < spinEnd {
            let homeTravel = unitBezier(min(1, (local - homeStart) / SpaceTrailerScript.home),
                                        0.18, 0.35, 0.36, 1)
            let remain = CGFloat(1 - homeTravel)
            offset = CGSize(width: contact.width * remain, height: contact.height * remain)
            if mark.answer.isCorrect {
                let spinWindow = SpaceTrailerScript.home + SpaceTrailerScript.spinTail
                let spin = unitBezier(min(1, (local - homeStart) / spinWindow),
                                      0.22, 0.30, 0.74, 0.9785)
                rotation = aim + 450 * spin
                pose = TrailerPose.tucked
            } else {
                rotation = aim
                pose = TrailerPose.pointing
            }
        } else {
            rotation = aim + (mark.answer.isCorrect ? 450 : 0)
            let settle = min(1, (local - spinEnd) / max(0.01, settleEnd - spinEnd))
            rotation += sway(time) * smooth(settle)
            pose = recoveryPose(settle: settle, correct: mark.answer.isCorrect)
        }

        var squash: CGFloat = 1
        if !mark.answer.isCorrect {
            let age = local - SpaceTrailerScript.outward
            if age >= 0, age < 0.40 {
                squash = 1 - 0.06 * CGFloat(sin(min(1, age / 0.40) * Double.pi))
            }
        }

        let driftGate: CGFloat = local >= spinEnd
            ? CGFloat(smooth(min(1, (local - spinEnd) / 0.24)))
            : 0
        actor.offset = offset
        actor.rotation = rotation
        actor.pose = pose
        actor.scale *= squash
        actor.drift = CGSize(width: actor.drift.width * driftGate,
                             height: actor.drift.height * driftGate)
        return actor
    }

    private func recoveryPose(settle: Double, correct: Bool) -> TrailerPose {
        if correct {
            if settle < 0.14 { return .tucked }
            if settle < 0.38 { return .recoveringEarly }
            if settle < 0.62 { return .recoveringMiddle }
            if settle < 0.84 { return .recoveringLate }
            return .resting
        }
        if settle < 0.42 { return .reaching }
        if settle < 0.72 { return .tucked }
        return .resting
    }

    private func idleDriftAmount() -> CGFloat {
        if time < SpaceTrailerScript.entranceDuration { return CGFloat(spring(time, response: 1.22, damping: 0.78)) }
        if time >= SpaceTrailerScript.finaleStart { return 0 }
        guard let mark = SpaceTrailerScript.marks.first(where: { time >= $0.start && time < $0.end }) else { return 1 }
        let spinEnd = mark.answer.isCorrect
            ? SpaceTrailerScript.outward + SpaceTrailerScript.press + SpaceTrailerScript.retract
                + SpaceTrailerScript.home + SpaceTrailerScript.spinTail
            : SpaceTrailerScript.outward + SpaceTrailerScript.press + SpaceTrailerScript.home
        let local = time - mark.start
        guard local >= spinEnd else { return 0 }
        return CGFloat(smooth(min(1, (local - spinEnd) / 0.24)))
    }

    private func landingAngle(before time: Double, metrics: SpaceLionPlayfield.Metrics) -> Double {
        var angle = 0.0
        for mark in SpaceTrailerScript.marks {
            if time <= mark.start { break }
            let aim = nearest(approachAngle(mark.answer.chosenIndex, metrics: metrics), to: angle)
            if time < mark.end { return aim }
            angle = aim + (mark.answer.isCorrect ? 450 : 0)
        }
        return angle
    }

    private func approachAngle(_ index: Int, metrics: SpaceLionPlayfield.Metrics) -> Double {
        let target = metrics.answerPoints[index]
        let dx = target.x - metrics.centre.x
        let dy = target.y - metrics.centre.y
        let fingerAngle = atan2(-0.043, 0.445) * 180 / .pi
        return atan2(dy, dx) * 180 / .pi - fingerAngle
    }

    private func contactOffset(index: Int, metrics: SpaceLionPlayfield.Metrics) -> CGSize {
        let target = metrics.answerPoints[index]
        let dx = target.x - metrics.centre.x
        let dy = target.y - metrics.centre.y
        let distance = max(1, hypot(dx, dy))
        let reach = hypot(metrics.lionSize * 0.445, metrics.lionSize * 0.043)
        return CGSize(width: dx - dx / distance * reach,
                      height: dy - dy / distance * reach)
    }

    private func nearest(_ angle: Double, to reference: Double) -> Double {
        var difference = (angle - reference).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return reference + difference
    }

    private func sway(_ time: Double) -> Double {
        sin(time * 0.42) * 10 + sin(time * 0.17) * 4
    }

    private var characterWeights: [(id: String, opacity: Double)] {
        if time >= SpaceTrailerScript.finaleStart { return [(id: "lion", opacity: 1)] }
        let current = SpaceTrailerScript.marks.last(where: { $0.start <= time })?.answer.characterID ?? "lion"
        guard let upcoming = SpaceTrailerScript.marks.first(where: { $0.start > time }),
              upcoming.answer.characterID != current else {
            return [(id: current, opacity: 1)]
        }
        let blendStart = upcoming.start - 0.50
        let blendEnd = upcoming.start - 0.10
        guard time >= blendStart else { return [(id: current, opacity: 1)] }
        let amount = smooth((time - blendStart) / (blendEnd - blendStart))
        return [(id: current, opacity: 1 - amount),
                (id: upcoming.answer.characterID, opacity: amount)]
    }

    private func cockpitStage(_ travel: SpaceTrailerScript.Travel?) -> Int {
        guard let travel else { return SpaceTrailerScript.stage(at: time) }
        return travel.progress(at: time) < 0.92 ? travel.fromStage : travel.toStage
    }

    private func warpShake(_ progress: CGFloat) -> CGFloat {
        let envelope = pow(sin(progress * .pi), 2)
        return sin(progress * .pi * 18) * envelope * (isPad ? 1.2 : 0.7)
    }

    private var hudOpacity: Double {
        if time >= SpaceTrailerScript.finaleStart {
            return 1 - smooth((time - SpaceTrailerScript.finaleStart) / 0.42)
        }
        return 1
    }

    // MARK: Pieces

    private func character(_ animal: AnimalCharacter,
                           actor: Actor,
                           metrics: SpaceLionPlayfield.Metrics) -> some View {
        let size = metrics.lionSize
        return ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 0.35, green: 0.75, blue: 1).opacity(0.38), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.36))
                .frame(width: size * 0.78, height: size * 0.30)
                .blur(radius: size * 0.035)
                .offset(y: size * 0.30)
            Image(animal.gameplayAsset(frame: actor.pose.frame))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(actor.pose.anchor(size: size))
                .rotationEffect(.degrees(actor.rotation))
        }
        .scaleEffect(actor.scale)
        .offset(x: actor.offset.width + actor.drift.width,
                y: actor.offset.height + actor.drift.height)
        .shadow(color: Color(red: 0.25, green: 0.70, blue: 1).opacity(0.45), radius: 16)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
        .position(metrics.centre)
    }

    @ViewBuilder
    private func answers(metrics: SpaceLionPlayfield.Metrics,
                         question: SpaceTrailerScript.Mark) -> some View {
        let live = pressedMark
        let options = question.answer.options
        ForEach(Array(options.enumerated()), id: \.offset) { index, text in
            let feedback = feedback(index: index, question: question, live: live)
            let pressed = live?.answer.chosenIndex == index
                && time < live!.contact + SpaceTrailerScript.press + 0.05
                && question.answer.prompt == live?.answer.prompt
            SpaceConsoleButton(text: text,
                               size: metrics.answerSize,
                               accentColor: CharacterCatalog.character(id: question.answer.characterID).color,
                               feedback: feedback,
                               isPressed: pressed)
                .offset(x: shake(index: index, live: live))
                .position(metrics.answerPoints[index])
                .opacity(buttonOpacity)
        }
    }

    private var pressedMark: SpaceTrailerScript.Mark? {
        SpaceTrailerScript.marks.first { time >= $0.start && time < $0.end }
    }

    private func feedback(index: Int,
                          question: SpaceTrailerScript.Mark,
                          live: SpaceTrailerScript.Mark?) -> HoopFeedback {
        guard let live, live.answer.chosenIndex == index,
              question.answer.prompt == live.answer.prompt,
              time >= live.contact else { return .none }
        if live.answer.isCorrect {
            return time < live.contact + 0.28 ? .correct : .none
        }
        return .wrong
    }

    private func buttonFeedbacks(question: SpaceTrailerScript.Mark) -> [HoopFeedback] {
        question.answer.options.indices.map {
            feedback(index: $0, question: question, live: pressedMark)
        }
    }

    private func shake(index: Int, live: SpaceTrailerScript.Mark?) -> CGFloat {
        guard let live, !live.answer.isCorrect, live.answer.chosenIndex == index else { return 0 }
        let age = time - live.contact
        guard age >= 0, age < 0.34 else { return 0 }
        return sin(age / 0.34 * .pi * 6) * metrics.answerSize * 0.045
    }

    private var buttonOpacity: Double {
        guard let travel = SpaceTrailerScript.travel(at: time) else { return 1 }
        let progress = Double(travel.progress(at: time))
        if progress < 0.16 { return 1 - progress / 0.16 }
        if progress > 0.86 { return (progress - 0.86) / 0.14 }
        return 0
    }

    @ViewBuilder
    private func burst(metrics: SpaceLionPlayfield.Metrics) -> some View {
        if let mark = SpaceTrailerScript.marks.first(where: {
            time >= $0.contact && time < $0.contact + 0.62
        }) {
            let amount = (time - mark.contact) / 0.62
            let point = metrics.answerPoints[mark.answer.chosenIndex]
            let tint = mark.answer.isCorrect
                ? Color(red: 0.28, green: 1, blue: 0.55)
                : Color(red: 1, green: 0.45, blue: 0.18)
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.85), lineWidth: 3)
                    .frame(width: metrics.answerSize * 0.45, height: metrics.answerSize * 0.45)
                    .scaleEffect(0.35 + CGFloat(amount) * 0.9)
                    .opacity(1 - amount)
                ForEach(0..<8, id: \.self) { index in
                    let angle = Double(index) / 8 * .pi * 2
                    Image(systemName: mark.answer.isCorrect && index.isMultiple(of: 2) ? "star.fill" : "sparkle")
                        .font(.system(size: metrics.answerSize * 0.09, weight: .black))
                        .foregroundStyle(index.isMultiple(of: 2) ? tint : .white)
                        .offset(x: CGFloat(cos(angle)) * metrics.answerSize * 0.55 * CGFloat(amount),
                                y: CGFloat(sin(angle)) * metrics.answerSize * 0.55 * CGFloat(amount))
                        .opacity(1 - amount)
                }
            }
            .position(point)
        }
    }

    private func victoryBloom(metrics: SpaceLionPlayfield.Metrics) -> some View {
        let amount = min(1, (time - SpaceTrailerScript.finaleStart) / 0.70)
        let size = metrics.cockpit.windowRect.width * 0.55
        return ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(Color(red: 0.45, green: 0.90, blue: 1).opacity(0.85),
                            lineWidth: max(2, size * 0.012))
                    .frame(width: size * 0.45, height: size * 0.45)
                    .scaleEffect(0.35 + CGFloat(amount) * (0.7 + CGFloat(ring) * 0.38))
                    .opacity(Double(1 - amount) * 0.9)
            }
        }
        .position(metrics.centre)
    }

    private func hud(metrics: SpaceLionPlayfield.Metrics,
                     accent: AnimalCharacter) -> some View {
        // The iPad master is 800 points wide, tighter than a real 13-inch iPad,
        // so the instrument rail scales down until the sum keeps a full line.
        let hudScale: CGFloat = isPad ? min(1, outputSize.width / 1180) : 1
        let height: CGFloat = (isPad ? 94 : 54) * hudScale
        let side = (isPad ? 94 : 54) * hudScale
        let insets = metrics.hudInsets(pauseWidth: side)
        let top = isPad
            ? max(topInset + 2, (metrics.ceilingBand - height) / 2)
            : topInset + 5
        let clock = SpaceTrailerScript.clock(at: time)
        let question = SpaceTrailerScript.question(at: time)
        let reveal = question.index == 0
            ? smooth((time - 0.18) / 0.42)
            : min(1, max(0, (time - question.questionFrom) / 0.16))
        let spacing: CGFloat = (isPad ? 12 : 7) * hudScale
        let row = outputSize.width - insets.leading - insets.trailing
        let questionWidth = max(120, row * (isPad ? 0.40 : 0.46))
        return HStack(spacing: spacing) {
            hudPanel(height: height, accent: accent.color, holographic: false) {
                Image(systemName: "pause.fill")
                    .font(.system(size: (isPad ? 32 : 20) * hudScale, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: height)

            hudPanel(height: height, accent: accent.color, holographic: true) {
                questionLabel(question.answer.prompt, accent: accent.color)
                    .opacity(reveal)
                    .scaleEffect(0.92 + 0.08 * reveal)
            }
            .frame(width: questionWidth, height: height)

            hudPanel(height: height, accent: accent.color, holographic: false) {
                timerLabel(clock)
            }
            .fixedSize(horizontal: true, vertical: false)

            hudPanel(height: height, accent: accent.color, holographic: false) {
                scoreLabel(stage: clock.stage, dots: SpaceTrailerScript.correctDots(at: time))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .padding(.top, top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func questionLabel(_ prompt: String, accent: Color) -> some View {
        let marker = prompt.range(of: "?")
        let leading = marker.map { String(prompt[..<$0.lowerBound]) } ?? prompt
        let trailing = marker.map { String(prompt[$0.upperBound...]) } ?? ""
        return HStack(spacing: 0) {
            Text(verbatim: leading).foregroundStyle(.white)
            if marker != nil {
                Text(verbatim: "?")
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.95), radius: isPad ? 8 : 5)
            }
            if !trailing.isEmpty {
                Text(verbatim: trailing).foregroundStyle(.white)
            }
        }
        .font(.system(size: (isPad ? 40 : 27) * (isPad ? min(1, outputSize.width / 1180) : 1),
                      weight: .black, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.35)
        .shadow(color: .black.opacity(0.55), radius: 0, y: 1)
    }

    private func timerLabel(_ clock: (remaining: Int, perQuestion: Int, stage: Int)) -> some View {
        let minutes = clock.remaining / 60
        let seconds = clock.remaining % 60
        let cyan = Color(red: 0, green: 0.75, blue: 1)
        return HStack(spacing: isPad ? 12 : 6) {
            let dial: CGFloat = (isPad ? 48 : 30) * (isPad ? min(1, outputSize.width / 1180) : 1)
            let timeSize: CGFloat = (isPad ? 34 : 20) * (isPad ? min(1, outputSize.width / 1180) : 1)
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: isPad ? 3 : 3)
                Circle()
                    .trim(from: 0, to: CGFloat(clock.remaining) / CGFloat(clock.stage == 1 ? 100 : clock.stage == 2 ? 80 : 70))
                    .stroke(cyan, style: StrokeStyle(lineWidth: isPad ? 3 : 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.system(size: dial * 0.42, weight: .bold))
                    .foregroundStyle(cyan)
            }
            .frame(width: dial, height: dial)
            VStack(spacing: 0) {
                Text(verbatim: String(format: "%d:%02d", minutes, seconds))
                    .font(.system(size: timeSize, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(verbatim: "\(clock.perQuestion)s")
                    .font(.system(size: timeSize * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, isPad ? 16 : 10)
    }

    private func scoreLabel(stage: Int, dots: Int) -> some View {
        let cyan = Color(red: 0, green: 0.75, blue: 1)
        return HStack(spacing: isPad ? 12 : 6) {
            let figure = (isPad ? 34 : 21) * (isPad ? min(1, outputSize.width / 1180) : 1)
            let dot = (isPad ? 24 : 12) * (isPad ? min(1, outputSize.width / 1180) : 1)
            Text(verbatim: "\(stage)/5")
                .font(.system(size: figure, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: cyan.opacity(0.38), radius: isPad ? 5 : 3)
            Capsule()
                .fill(cyan.opacity(0.36))
                .frame(width: isPad ? 2 : 1, height: isPad ? 40 : 28)
            VStack(spacing: isPad ? 7 : 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: isPad ? 7 : 3) {
                        ForEach(0..<5, id: \.self) { column in
                            let index = row * 5 + column
                            let filled = index < dots
                            Circle()
                                .fill(filled
                                      ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.62, green: 1, blue: 0.58),
                                                                              Color(red: 0.08, green: 0.82, blue: 0.38)],
                                                                     startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.26, green: 0.32, blue: 0.43),
                                                                              Color(red: 0.10, green: 0.14, blue: 0.23)],
                                                                     startPoint: .top, endPoint: .bottom)))
                                .overlay(Circle().stroke(filled ? Color.white.opacity(0.72) : cyan.opacity(0.34),
                                                         lineWidth: isPad ? 1.5 : 1))
                                .frame(width: dot, height: dot)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, isPad ? 16 : 10)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func hudPanel<Content: View>(height: CGFloat,
                                        accent: Color,
                                        holographic: Bool,
                                        @ViewBuilder content: () -> Content) -> some View {
        let cut: CGFloat = isPad ? 16 : 10
        let cyan = Color(red: 0, green: 0.75, blue: 1)
        let fill = holographic
            ? [Color(red: 0.10, green: 0.16, blue: 0.42),
               Color(red: 0.04, green: 0.05, blue: 0.18),
               Color(red: 0.07, green: 0.03, blue: 0.16)]
            : [Color(red: 0.14, green: 0.20, blue: 0.38),
               Color(red: 0.03, green: 0.05, blue: 0.12),
               Color(red: 0.012, green: 0.02, blue: 0.06)]
        return content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: height)
            .background {
                TrailerHUDShape(cut: cut)
                    .fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
                    .overlay {
                        TrailerHUDShape(cut: cut)
                            .stroke(cyan.opacity(0.95), lineWidth: isPad ? 2.6 : 1.8)
                            .padding(isPad ? 3.5 : 2.2)
                    }
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(holographic ? accent : cyan)
                            .frame(width: isPad ? 84 : 46, height: isPad ? 3 : 2)
                            .shadow(color: (holographic ? accent : cyan).opacity(0.9), radius: 4)
                            .padding(.bottom, isPad ? 5 : 3)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            }
    }

    private func iconFinale(amount: Double) -> some View {
        let iconSize = min(outputSize.height * 0.50, outputSize.width * 0.30)
        let corner = iconSize * 0.225
        return Image("trailer_icon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: .black.opacity(0.38), radius: iconSize * 0.08, y: iconSize * 0.04)
            .scaleEffect(0.72 + 0.28 * amount)
            .rotationEffect(.degrees(-8 * (1 - amount)))
            .opacity(amount)
            .position(x: outputSize.width / 2, y: outputSize.height / 2)
    }

    private func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func easeIn(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t
    }

    private func spring(_ time: Double, response: Double, damping: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = min(0.99, damping)
        let damped = omega * sqrt(1 - zeta * zeta)
        let envelope = exp(-zeta * omega * time)
        return 1 - envelope * (cos(damped * time) + (zeta * omega / damped) * sin(damped * time))
    }

    /// CSS-style cubic bezier with endpoints (0,0) and (1,1).
    private func unitBezier(_ amount: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let target = min(1, max(0, amount))
        var t = target
        for _ in 0..<8 {
            let x = cubic(t, 0, x1, x2, 1) - target
            let slope = cubicSlope(t, 0, x1, x2, 1)
            if abs(slope) < 0.0001 { break }
            t = min(1, max(0, t - x / slope))
        }
        return cubic(t, 0, y1, y2, 1)
    }

    private func cubic(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let u = 1 - t
        return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
    }

    private func cubicSlope(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
    }
}

private enum TrailerPose {
    case resting, tucked, reaching, pointing
    case recoveringEarly, recoveringMiddle, recoveringLate

    var frame: Int {
        switch self {
        case .resting: return 1
        case .tucked: return 2
        case .reaching: return 3
        case .pointing: return 5
        case .recoveringEarly: return 6
        case .recoveringMiddle: return 7
        case .recoveringLate: return 8
        }
    }

    func anchor(size: CGFloat) -> CGSize {
        let fraction: (CGFloat, CGFloat)
        switch self {
        case .resting: fraction = (0.063, -0.055)
        case .tucked: fraction = (0.101, -0.050)
        case .reaching: fraction = (0.146, -0.069)
        case .pointing: fraction = (0, 0)
        case .recoveringEarly: fraction = (-0.012, 0.001)
        case .recoveringMiddle: fraction = (0.039, -0.003)
        case .recoveringLate: fraction = (0.074, -0.007)
        }
        return CGSize(width: fraction.0 * size, height: fraction.1 * size)
    }
}

private struct TrailerHUDShape: Shape {
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
#if os(iOS) && TRAILER_EXPORT
import AVFoundation
import UIKit

/// The app shows only this inert host when the explicit export flag is present.
/// Rendering, encoding, audio assembly and representative-frame capture all
/// happen offscreen, so there is no status bar, cursor, simulator chrome or
/// real-time frame pacing in the deliverable.
struct TrailerExportHost: View {
    @State private var status = "Preparing deterministic trailer…"

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.16, blue: 0.38).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text(status)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .task {
            do {
                let exporter = TrailerExporter { status = $0 }
                try await exporter.exportAll()
                status = "Export complete"
            } catch {
                status = "Export failed: \(error.localizedDescription)"
                try? TrailerExporter.writeFailure(error)
            }
        }
    }
}

@MainActor
private final class TrailerExporter {
    struct OutputSpec {
        let width: Int
        let height: Int
        var name: String { "app-store-teaser-\(width)x\(height)" }
        var size: CGSize { CGSize(width: width, height: height) }
    }

    struct SoundCue {
        let resource: String
        let ext: String
        let time: Double
        let volume: Float
    }

    static let framesPerSecond: Int32 = 30
    static let videoOutputs = [OutputSpec(width: 1920, height: 886),
                               OutputSpec(width: 1600, height: 1200)]
    static let stillOutputs = [OutputSpec(width: 2048, height: 944),
                               OutputSpec(width: 2048, height: 1535)]
    static let previewFrames: [Int: String] = {
        var frames: [Int: String] = [:]
        for second in 0..<Int(TrailerCompositionView.duration) {
            frames[second * Int(framesPerSecond)] = String(format: "%02ds", second)
        }
        func add(_ time: Double, _ label: String) {
            frames[Int((time * Double(framesPerSecond)).rounded())] = label
        }
        add(0.35, "entrance")
        add(SpaceTrailerScript.entranceDuration, "ready")
        for mark in SpaceTrailerScript.marks {
            add(mark.start, "q\(mark.index + 1)")
            add(mark.contact, "hit\(mark.index + 1)")
        }
        for travel in SpaceTrailerScript.travels {
            add(travel.start + SpaceTrailerScript.travelDuration * 0.45, "warp\(travel.toStage)")
            add(travel.end, "land\(travel.toStage)")
        }
        add(SpaceTrailerScript.finaleStart + 0.45, "fly")
        add(SpaceTrailerScript.iconStart + 0.95, "icon")
        return frames
    }()

    let updateStatus: (String) -> Void

    init(updateStatus: @escaping (String) -> Void) {
        self.updateStatus = updateStatus
    }

    func exportAll() async throws {
        if TrailerRuntime.isStillExporting {
            try exportStills()
            return
        }

        let root = try Self.exportRoot()
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previews = root.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)

        for spec in Self.videoOutputs {
            updateStatus("Rendering \(spec.width) × \(spec.height)…")
            let silentURL = root.appendingPathComponent("\(spec.name)-silent.mp4")
            let finalURL = root.appendingPathComponent("\(spec.name).mp4")
            try await renderVideo(spec: spec, outputURL: silentURL, previewsURL: previews)
            updateStatus("Mixing real game audio for \(spec.width) × \(spec.height)…")
            try await mixAudio(videoURL: silentURL, outputURL: finalURL)
            try? FileManager.default.removeItem(at: silentURL)
        }

        let completion: [String: Any] = [
            "duration": TrailerCompositionView.duration,
            "fps": Int(Self.framesPerSecond),
            "outputs": Self.videoOutputs.map(\.name),
            "layout": "nativeLandscapeGameplay",
            "completedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: completion, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("export-complete.json"), options: .atomic)
    }

    private func exportStills() throws {
        let root = try Self.exportRoot()
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var filenames: [String] = []
        for spec in Self.stillOutputs {
            for kind in PromoStillKind.allCases {
                updateStatus("Rendering \(kind.headline) — \(spec.width) × \(spec.height)…")
                let filename = "\(kind.filenameStem)-\(spec.width)x\(spec.height).png"
                let image = try renderedStill(kind: kind, spec: spec)
                guard let data = image.pngData() else { throw ExportError.pngData(filename) }
                try data.write(to: root.appendingPathComponent(filename), options: .atomic)
                filenames.append(filename)
            }
        }

        let completion: [String: Any] = [
            "outputs": filenames,
            "layout": "nativeLandscapeStills",
            "completedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: completion, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("export-complete.json"), options: .atomic)
    }

    private func renderedStill(kind: PromoStillKind, spec: OutputSpec) throws -> UIImage {
        let content = PromoStillCompositionView(kind: kind, outputSize: spec.size)
            .frame(width: spec.size.width, height: spec.size.height)
            .transaction { transaction in transaction.disablesAnimations = true }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(spec.size)
        guard let image = renderer.uiImage else { throw ExportError.renderStill(kind.rawValue) }
        return image
    }

    private func renderVideo(spec: OutputSpec, outputURL: URL, previewsURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let bitRate = spec.height <= 944 ? 18_000_000 : 24_000_000
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: spec.width,
            AVVideoHeightKey: spec.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(Self.framesPerSecond),
                AVVideoMaxKeyFrameIntervalKey: Int(Self.framesPerSecond)
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: spec.width,
            kCVPixelBufferHeightKey as String: spec.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                            sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw ExportError.writerInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writerStart }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(TrailerCompositionView.duration * Double(Self.framesPerSecond))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let frameTime = Double(frame) / Double(Self.framesPerSecond)
            let image = try renderedImage(time: frameTime, spec: spec)
            let pixelBuffer = try makePixelBuffer(image: image,
                                                  pool: adaptor.pixelBufferPool,
                                                  width: spec.width,
                                                  height: spec.height)
            let presentationTime = CMTime(value: CMTimeValue(frame), timescale: Self.framesPerSecond)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? ExportError.appendFrame(frame)
            }

            if let label = Self.previewFrames[frame] {
                let name = "\(spec.name)-\(label).png"
                if let data = image.pngData() {
                    try data.write(to: previewsURL.appendingPathComponent(name), options: .atomic)
                }
            }

            if frame.isMultiple(of: Int(Self.framesPerSecond) * 2) {
                updateStatus("Rendering \(spec.width) × \(spec.height): \(Int(frameTime)) / \(Int(TrailerCompositionView.duration)) s")
                await Task.yield()
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? ExportError.writerFinish }
    }

    private func renderedImage(time: Double, spec: OutputSpec) throws -> UIImage {
        // Layout points match a large landscape phone or iPad. The bitmap is
        // 2× those points, which is the Hungry Frog App Store master
        // (1920×886 and 1600×1200) with no Dynamic Island inset.
        let layout = CGSize(width: spec.size.width / 2, height: spec.size.height / 2)
        let content = TrailerCompositionView(time: time,
                                             outputSize: layout,
                                             isPad: spec.size.height > 1000)
            .frame(width: layout.width, height: layout.height)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(layout)
        guard let image = renderer.uiImage else { throw ExportError.renderFrame(time) }
        return image
    }

    private func makePixelBuffer(image: UIImage,
                                 pool: CVPixelBufferPool?,
                                 width: Int,
                                 height: Int) throws -> CVPixelBuffer {
        guard let cgImage = image.cgImage else { throw ExportError.missingCGImage }
        var optionalBuffer: CVPixelBuffer?
        let result: CVReturn
        if let pool {
            result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
        } else {
            result = CVPixelBufferCreate(nil, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferCGImageCompatibilityKey: true,
                                          kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                                         &optionalBuffer)
        }
        guard result == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw ExportError.pixelBuffer(result)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                        | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw ExportError.bitmapContext
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func mixAudio(videoURL: URL, outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.videoTrack
        }
        let duration = CMTime(seconds: TrailerCompositionView.duration, preferredTimescale: 600)
        try destinationVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                             of: sourceVideo,
                                             at: .zero)

        var parameters: [AVMutableAudioMixInputParameters] = []
        if let musicURL = Bundle.main.url(forResource: "background_music", withExtension: "m4a") {
            let musicAsset = AVURLAsset(url: musicURL)
            if let musicSource = try await musicAsset.loadTracks(withMediaType: .audio).first,
               let musicTrack = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid) {
                let sourceDuration = try await musicAsset.load(.duration)
                var cursor = CMTime.zero
                while cursor < duration, sourceDuration.seconds > 0 {
                    let remaining = duration - cursor
                    let segment = min(sourceDuration, remaining)
                    try musicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: segment),
                                                   of: musicSource,
                                                   at: cursor)
                    cursor = cursor + segment
                }
                let p = AVMutableAudioMixInputParameters(track: musicTrack)
                p.setVolume(0.16, at: .zero)
                let fadeStart = max(0, SpaceTrailerScript.iconStart - 0.35)
                p.setVolumeRamp(fromStartVolume: 0.16, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: fadeStart, preferredTimescale: 600), duration: CMTime(seconds: max(0.4, SpaceTrailerScript.duration - fadeStart), preferredTimescale: 600)))
                parameters.append(p)
            }
        }

        let cues: [SoundCue] = SpaceTrailerScript.soundCues.map {
            SoundCue(resource: $0.resource, ext: $0.ext, time: $0.time, volume: $0.volume)
        }
        for cue in cues {
            guard let url = Bundle.main.url(forResource: cue.resource, withExtension: cue.ext) else { continue }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let cueDuration = try await asset.load(.duration)
            let start = CMTime(seconds: cue.time, preferredTimescale: 600)
            let available = duration - start
            guard available > .zero else { continue }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: min(cueDuration, available)),
                                      of: source,
                                      at: start)
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(cue.volume, at: start)
            parameters.append(p)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportSession
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.audioMix = audioMix
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else { throw session.error ?? ExportError.audioMix }
    }

    static func exportRoot() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ExportError.documentsDirectory
        }
        let folder = TrailerRuntime.isStillExporting ? "AppStoreStills" : "AppStoreTeaser"
        return documents.appendingPathComponent(folder, isDirectory: true)
    }

    static func writeFailure(_ error: Error) throws {
        let root = try exportRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(error.localizedDescription.utf8)
            .write(to: root.appendingPathComponent("export-failed.txt"), options: .atomic)
    }

    private enum ExportError: LocalizedError {
        case writerInput, writerStart, writerFinish, appendFrame(Int), renderFrame(Double)
        case renderStill(String), pngData(String)
        case missingCGImage, pixelBuffer(CVReturn), bitmapContext, videoTrack
        case exportSession, audioMix, documentsDirectory

        var errorDescription: String? {
            switch self {
            case .writerInput: return "The H.264 writer rejected its input."
            case .writerStart: return "The H.264 writer could not start."
            case .writerFinish: return "The H.264 writer could not finish."
            case .appendFrame(let frame): return "Could not append video frame \(frame)."
            case .renderFrame(let time): return "Could not render the frame at \(time) seconds."
            case .renderStill(let kind): return "Could not render the \(kind) App Store still."
            case .pngData(let filename): return "Could not encode \(filename) as PNG."
            case .missingCGImage: return "A rendered frame had no CGImage."
            case .pixelBuffer(let status): return "Could not allocate a pixel buffer (\(status))."
            case .bitmapContext: return "Could not create the pixel-buffer drawing context."
            case .videoTrack: return "The silent master did not contain a readable video track."
            case .exportSession: return "Could not create the final media export session."
            case .audioMix: return "Could not mux the game audio into the video."
            case .documentsDirectory: return "The export Documents directory was unavailable."
            }
        }
    }
}
#else
struct TrailerExportHost: View {
    var body: some View { Text("Trailer export is available on iOS.") }
}
#endif
