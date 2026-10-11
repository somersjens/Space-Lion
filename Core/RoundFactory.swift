//
//  RoundFactory.swift
//  Elephant Challenge: Math Memory
//
//  Builds one complete round: the question and the six answer buttons.
//
//  Compose each ten-question stage in the selected practice route. The six
//  answer slots stay distinct and stable: only the used slot may change after
//  a correct answer, and its replacement is the first missing future answer.
//  Repeated results may keep that slot, so a narrow exercise never has to
//  invent an out-of-range question just to refresh a button.
//

import Foundation

// MARK: - Answer card

public struct AnswerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let isCorrect: Bool

    public init(id: UUID = UUID(), text: String, isCorrect: Bool) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
    }
}

// MARK: - Round

public struct GameRound: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 1-based position in the session.
    public let number: Int
    public let question: MathQuestion
    /// Exactly one option has `isCorrect == true`.
    public let options: [AnswerOption]
    public init(id: UUID = UUID(),
                number: Int,
                question: MathQuestion,
                options: [AnswerOption]) {
        self.id = id
        self.number = number
        self.question = question
        self.options = options
    }

    public var correctOption: AnswerOption? {
        options.first { $0.isCorrect }
    }
}

// MARK: - Factory

public final class RoundFactory {
    private struct PlannedRound {
        let question: MathQuestion
        let options: [AnswerOption]
    }

    private let generator: QuestionGenerator
    private let random: RandomSource
    /// One identity per button for the whole session. The label on a button
    /// changes; the button itself does not, so SwiftUI does not rebuild it
    /// after every answer.
    private let slotIDs: [UUID]
    private var plans: [Int: PlannedRound] = [:]
    private var sequenceOrigin: Int?
    private var nextUnplannedRound: Int?

    public init(level: MathLevel,
                mixedVariant: MixedVariant = .all,
                mode: PracticeMode = .mixed,
                seed: UInt64? = nil) {
        let random = RandomSource(seed: seed)
        self.random = random
        self.generator = QuestionGenerator(level: level,
                                           mode: mode,
                                           mixedVariant: mixedVariant,
                                           random: random)
        self.slotIDs = (0..<GameConfig.answerBubbleCount).map { _ in UUID() }
    }

    public func reset() {
        generator.reset()
        plans.removeAll(keepingCapacity: true)
        sequenceOrigin = nil
        nextUnplannedRound = nil
    }

    /// Composes `count` rounds, starting at `first`, before play begins.
    /// Stages are completed even when `count` stops in the middle of one, so
    /// lazy runway replenishment never creates a second answer sequence.
    public func prepareSequence(startingAt first: Int, count: Int) {
        reset()
        let origin = max(1, first)
        sequenceOrigin = origin
        guard count > 0 else { return }
        ensurePlanned(through: origin + count - 1)
    }

    /// Builds the round for a given 1-based round number. The question and its
    /// button assignment were decided when the stage was composed.
    public func makeRound(number: Int) -> GameRound {
        if sequenceOrigin == nil { sequenceOrigin = number }
        ensurePlanned(through: number)
        let planned = plans[number] ?? planFallback(number: number)
        return GameRound(number: number,
                         question: planned.question,
                         options: planned.options)
    }

    private func ensurePlanned(through last: Int) {
        let origin = sequenceOrigin ?? last
        if sequenceOrigin == nil { sequenceOrigin = origin }
        var next = nextUnplannedRound ?? origin
        while next <= last {
            let stageEnd = ((next - 1) / GameConfig.questionsPerStage + 1)
                * GameConfig.questionsPerStage
            planStage(startingAt: next, endingAt: stageEnd)
            next = stageEnd + 1
            nextUnplannedRound = next
        }
    }

    /// Keep the same physical slots while playing the generator's exact
    /// practice route. The first missing future answer takes the spent slot;
    /// a repeated answer can keep it instead of inventing a harder question.
    private func planStage(startingAt first: Int, endingAt last: Int) {
        let count = max(0, last - first + 1)
        guard count > 0 else { return }
        let questions = (0..<count).map { _ in
            generator.next(requiredDistractors: GameConfig.distractorCount)
        }
        var board: [String] = []
        for question in questions where board.count < slotIDs.count {
            if !board.contains(where: { AnswerValue($0) == AnswerValue(question.correctAnswer) }) {
                board.append(question.correctAnswer)
            }
        }
        while board.count < slotIDs.count {
            board.append(freshFiller(avoiding: Set(board.map(AnswerValue.init)),
                                     preferred: questions.flatMap(\.distractors)))
        }
        board.sort { AnswerValue($0) < AnswerValue($1) }
        for (offset, question) in questions.enumerated() {
            let correct = AnswerValue(question.correctAnswer)
            guard let slot = board.firstIndex(where: { AnswerValue($0) == correct }) else {
                assertionFailure("Upcoming answer must already be on the board")
                plans[first + offset] = planFallback(number: first + offset)
                continue
            }
            plans[first + offset] = PlannedRound(question: question, options: board.enumerated().map {
                AnswerOption(id: slotIDs[$0.offset], text: $0.element, isCorrect: $0.offset == slot)
            })
            let remaining = questions.dropFirst(offset + 1)
            guard !remaining.isEmpty else { continue }
            let occupied = Set(board.enumerated().filter { $0.offset != slot }
                .map { AnswerValue($0.element) })
            if let needed = remaining.first(where: { !occupied.contains(AnswerValue($0.correctAnswer)) }) {
                board[slot] = needed.correctAnswer
            } else {
                board[slot] = freshFiller(avoiding: Set(board.map(AnswerValue.init)),
                                         preferred: question.distractors)
            }
        }
    }

    /// Gives an already-spent slot a visibly new value when no later question
    /// needs that slot. Prefer a believable near-miss from the question; the
    /// numeric walk is only a defensive fallback for an exhausted list.
    private func freshFiller(avoiding forbidden: Set<AnswerValue>,
                             preferred: [String]) -> String {
        if let candidate = preferred.first(where: { !forbidden.contains(AnswerValue($0)) }) {
            return candidate
        }
        var value = 0
        while forbidden.contains(AnswerValue("\(value)")) { value += 1 }
        return "\(value)"
    }

    /// Only reached when a stage could not be filled. Keeps the session
    /// playable with the same six buttons rather than failing the round.
    private func planFallback(number: Int) -> PlannedRound {
        let question = generator.next(requiredDistractors: GameConfig.distractorCount,
                                      avoiding: [])
        var texts = [question.correctAnswer]
        for distractor in question.distractors where texts.count < slotIDs.count {
            let values = Set(texts.map(AnswerValue.init))
            if !values.contains(AnswerValue(distractor)) { texts.append(distractor) }
        }
        while texts.count < slotIDs.count {
            texts.append(freshFiller(avoiding: Set(texts.map(AnswerValue.init)),
                                     preferred: []))
        }
        let shuffled = random.shuffled(texts)
        let correct = AnswerValue(question.correctAnswer)
        let options = slotIDs.enumerated().map { index, id in
            AnswerOption(id: id,
                         text: shuffled[index],
                         isCorrect: AnswerValue(shuffled[index]) == correct)
        }
        let planned = PlannedRound(question: question, options: options)
        plans[number] = planned
        return planned
    }
}
