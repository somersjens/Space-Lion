//
//  RoundFactory.swift
//  Elephant Challenge: Math Memory
//
//  Builds one complete round: the question and the six answer buttons.
//
//  The whole sequence is composed before the first sum is shown, in blocks of
//  six. Each block owns six different answers, laid out low-to-high across the
//  six buttons, and those labels stay put until every one of them has been the
//  right answer exactly once. The next block brings six new numbers, so a
//  button is never rewritten with the digit it already shows, and no answer
//  repeats inside any six questions in a row. Which button is correct is a
//  shuffle of the six, so every button is used equally often and the button
//  that changes is not the one that holds the current answer.
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
    /// Answers shown during the previous block. The next block is built
    /// entirely outside this set, so consecutive boards never share a number.
    private var previousBlockAnswers: Set<AnswerValue> = []

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
        previousBlockAnswers = []
    }

    /// Composes `count` rounds, starting at `first`, before play begins.
    /// Blocks are completed even when `count` stops in the middle of one, so
    /// the last prepared question still has its five companion answers.
    public func prepareSequence(startingAt first: Int, count: Int) {
        reset()
        let origin = max(1, first)
        sequenceOrigin = origin
        guard count > 0 else { return }
        ensurePlanned(through: origin + count - 1)
    }

    /// Builds the round for a given 1-based round number. The question and its
    /// button assignment were decided when the block was composed.
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
        var next = plans.keys.max().map { $0 + 1 } ?? origin
        if plans.isEmpty { next = origin }
        let width = GameConfig.answerBubbleCount
        while next <= last {
            planBlock(startingAt: next)
            next += width
        }
    }

    /// Six questions, six different answers, none of them still on screen from
    /// the block before. Play order is shuffled so the correct button jumps
    /// around instead of marching along the sorted row.
    private func planBlock(startingAt first: Int) {
        let width = GameConfig.answerBubbleCount
        var questions: [MathQuestion] = []
        var used = previousBlockAnswers
        var guardRail = 0
        while questions.count < width && guardRail < width * 12 {
            guardRail += 1
            let question = generator.next(requiredDistractors: GameConfig.distractorCount,
                                          avoiding: used)
            let answer = AnswerValue(question.correctAnswer)
            guard !used.contains(answer) else { continue }
            questions.append(question)
            used.insert(answer)
        }
        while questions.count < width {
            let question = syntheticQuestion(avoiding: used)
            let answer = AnswerValue(question.correctAnswer)
            guard !used.contains(answer) else { break }
            questions.append(question)
            used.insert(answer)
        }
        let played = random.shuffled(questions)
        let board = played.map(\.correctAnswer).sorted { AnswerValue($0) < AnswerValue($1) }
        for (offset, question) in played.enumerated() {
            let correct = AnswerValue(question.correctAnswer)
            let options = board.enumerated().map { index, text in
                AnswerOption(id: slotIDs[index],
                             text: text,
                             isCorrect: AnswerValue(text) == correct)
            }
            plans[first + offset] = PlannedRound(question: question, options: options)
        }
        previousBlockAnswers = Set(played.map { AnswerValue($0.correctAnswer) })
    }

    /// A plain sum whose result is still free. Used only when the practised
    /// route cannot supply another distinct answer for this block.
    private func syntheticQuestion(avoiding forbidden: Set<AnswerValue>) -> MathQuestion {
        var answer = 0
        while forbidden.contains(AnswerValue("\(answer)")) { answer += 1 }
        return MathQuestion(prompt: "0 + \(answer) = ?",
                            correctAnswer: "\(answer)",
                            distractors: (1...6).map { String(answer + $0) },
                            sourceLevel: 1,
                            kind: .addition)
    }

    /// Only reached when a block could not be filled. Keeps the session
    /// playable with the same six buttons rather than failing the round.
    private func planFallback(number: Int) -> PlannedRound {
        let question = generator.next(requiredDistractors: GameConfig.distractorCount,
                                      avoiding: previousBlockAnswers)
        let text = question.correctAnswer
        let options = slotIDs.enumerated().map { index, id in
            AnswerOption(id: id,
                         text: index == 0 ? text : "\(index)",
                         isCorrect: index == 0)
        }
        let planned = PlannedRound(question: question, options: options)
        plans[number] = planned
        return planned
    }
}
