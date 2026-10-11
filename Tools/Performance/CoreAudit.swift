import Foundation

/// Standalone regression audit; never reads the app's persisted progress.
@main struct CoreAudit {
    static func value(_ expression: String) -> Double? {
        let text = expression.trimmingCharacters(in: .whitespaces)
        for symbol in [" + ", " − ", " × "] {
            let parts = text.components(separatedBy: symbol)
            if parts.count == 2, let a = value(parts[0]), let b = value(parts[1]) {
                switch symbol {
                case " + ": return a + b
                case " − ": return a - b
                default: return a * b
                }
            }
        }
        if text.hasSuffix("%"), let number = value(String(text.dropLast())) { return number / 100 }
        let fraction = text.components(separatedBy: "/")
        if fraction.count == 2, let a = value(fraction[0]), let b = value(fraction[1]), b != 0 { return a / b }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    static func main() {
        DecimalAnswer.separatorProvider = { "," }
        precondition(AnswerValue("-0,5") == AnswerValue("-1/2"))
        precondition(AnswerValue("2,50") == AnswerValue("5/2"))
        precondition(AnswerValue("50%") != AnswerValue("50"))
        precondition(AnswerValue("1/2") == AnswerValue("2/4"))
        var total = 0, repeats = 0, timings: [Double] = []
        let start = ProcessInfo.processInfo.systemUptime
        for topic in MathTopic.allCases {
            for index in 1...99 {
                for mode in PracticeMode.allCases {
                    let variants: [MixedVariant] = topic == .mixed ? MixedVariant.allCases : [.all]
                    for variant in variants {
                        for seed: UInt64 in [1, 42, 999] {
                            let level = MathLevel(topic: topic, index: index)
                            let factory = RoundFactory(level: level, mixedVariant: variant, mode: mode, seed: seed)
                            let began = ProcessInfo.processInfo.systemUptime
                            factory.prepareSequence(startingAt: 1, count: 50)
                            timings.append((ProcessInfo.processInfo.systemUptime - began) * 1_000)
                            let ordered = QuestionGenerator(level: level, mode: mode, random: RandomSource(seed: seed))
                            var previous: GameRound?
                            for number in 1...50 {
                                let round = factory.makeRound(number: number)
                                let context = "\(topic.rawValue).\(index) \(mode) \(variant) seed=\(seed) round=\(number)"
                                precondition(round.question.isValid(requiredDistractors: 5), context)
                                precondition((1...level.index).contains(round.question.sourceLevel), context + " source outside lesson range")
                                if topic != .mixed && mode != .mixed {
                                    precondition(round.question.sourceLevel == level.index, context + " changed selected lesson")
                                }
                                precondition(round.options.count == 6, context)
                                precondition(Set(round.options.map { AnswerValue($0.text) }).count == 6, context)
                                precondition(round.options.filter(\.isCorrect).count == 1, context)
                                precondition(AnswerValue(round.correctOption!.text) == AnswerValue(round.question.correctAnswer), context)
                                let solved = round.question.solvedPrompt.components(separatedBy: " = ")
                                precondition(solved.count == 2, context)
                                guard let a = value(solved[0]), let b = value(solved[1]) else { fatalError(context + round.question.solvedPrompt) }
                                precondition(abs(a - b) < 0.000001, context + " " + round.question.solvedPrompt)
                                if round.question.kind == .multiplication {
                                    let factors = solved[0].components(separatedBy: " × ").compactMap(value)
                                    let table = Double(round.question.sourceLevel)
                                    precondition(factors.count == 2 && (
                                        (factors[0] == table && (0...12).contains(factors[1])) ||
                                        (factors[1] == table && (0...12).contains(factors[0]))
                                    ), context + " multiplier outside table route")
                                }
                                if topic != .mixed {
                                    precondition(round.question.kind.topic == topic, context)
                                } else {
                                    precondition(variant.topics.contains(round.question.kind.topic), context)
                                }
                                if mode == .order && [.addition, .subtraction, .tables].contains(topic) {
                                    precondition(round.question.prompt == ordered.next(requiredDistractors: 5).prompt, context)
                                }
                                if let previous {
                                    if previous.question.prompt == round.question.prompt { repeats += 1 }
                                    if (number - 1) % 10 != 0 {
                                        precondition(previous.options.map(\.id) == round.options.map(\.id), context)
                                        for (old, new) in zip(previous.options, round.options) where !old.isCorrect {
                                            precondition(old.text == new.text, context + " changed untouched slot")
                                        }
                                    }
                                }
                                total += 1
                                previous = round
                            }
                            if mode == .order && [.addition, .subtraction, .tables].contains(topic) {
                                for start in [7, 11, 17] {
                                    let resumed = RoundFactory(level: level, mixedVariant: variant, mode: mode, seed: seed)
                                    let continued = QuestionGenerator(level: level, mode: mode, random: RandomSource(seed: seed))
                                    resumed.prepareSequence(startingAt: start, count: 4)
                                    for _ in 1..<start { _ = continued.next(requiredDistractors: 5) }
                                    let again = resumed.makeRound(number: start)
                                    precondition(again.question.prompt == continued.next(requiredDistractors: 5).prompt,
                                                 "\(topic.rawValue).\(index) order resume at \(start) restarted")
                                }
                            }
                            // Partial resumed stages and plan extension must keep valid answers too.
                            factory.prepareSequence(startingAt: 7, count: 5)
                            for number in 7...25 {
                                let round = factory.makeRound(number: number)
                                precondition(round.options.filter(\.isCorrect).count == 1)
                                precondition(Set(round.options.map { AnswerValue($0.text) }).count == 6)
                            }
                        }
                    }
                }
            }
        }
        precondition(repeats == 0, "Adjacent repeats: \(repeats)")
        timings.sort()
        let p95 = timings[Int(Double(timings.count) * 0.95)]
        print(String(format: "PASS rounds=%d adjacent_repeats=%d plans=%d prepare50_p95_ms=%.3f prepare50_max_ms=%.3f total_s=%.3f", total, repeats, timings.count, p95, timings.last!, ProcessInfo.processInfo.systemUptime - start))
    }
}
