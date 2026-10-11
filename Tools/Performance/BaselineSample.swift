import Foundation
@main struct Audit {
 static func main() {
  var total = 0, invalid = 0, repeats = 0, orderMismatches = 0
  let started = ProcessInfo.processInfo.systemUptime
  for topic in MathTopic.allCases {
   for index in [1,2,3,4,6,12,13,50,99] {
    for mode in PracticeMode.allCases {
     let level = MathLevel(topic: topic, index: index)
     let factory = RoundFactory(level: level, mode: mode, seed: 42)
     factory.prepareSequence(startingAt: 1, count: 50)
     let expected = QuestionGenerator(level: level, mode: mode, random: RandomSource(seed: 42))
     var previous: String?
     for number in 1...50 {
      let r = factory.makeRound(number: number)
      total += 1
      if !r.question.isValid(requiredDistractors: 5) || Set(r.options.map { AnswerValue($0.text) }).count != 6 || r.options.filter(\.isCorrect).count != 1 { invalid += 1 }
      if r.question.prompt == previous { repeats += 1 }
      if mode == .order && [.addition,.subtraction,.tables].contains(topic) && r.question.prompt != expected.next(requiredDistractors: 5).prompt { orderMismatches += 1 }
      previous = r.question.prompt
     }
    }
   }
  }
  print("rounds=\(total) invalid=\(invalid) adjacentRepeats=\(repeats) orderMismatches=\(orderMismatches) elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
 }
}
