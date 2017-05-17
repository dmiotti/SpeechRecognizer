//
//  StepProcessor.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 16/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit

enum StepMove {
    case beginning
    case next
    case previous
    case at(position: Int)
    case end
    case none
}

final class StepProcessor: NSObject {
    static var stepNRegex = [String]()
    static var startRegex = [String]()
    static var endRegex = [String]()
    static var nextRegex = [String]()
    static var previousRegex = [String]()

    static var numberFormatter: NumberFormatter = {
        let number = NumberFormatter()
        number.locale = Locale.current
        number.numberStyle = .spellOut
        return number
    }()

    class func nextStep(sentence: String) -> StepMove {
        let matches = stepNRegex.flatMap { matchesIn(sentence, with: $0) }
        let numberMatches = matches.flatMap { numberFormatter.number(from: $0.lowercased()) }
        if let firstMatch = numberMatches.first {
            return .at(position: firstMatch.intValue)
        }

        if let _ = startRegex.first(where: { !matchesIn(sentence, with: $0).isEmpty }) {
            return .beginning
        }

        if let _ = endRegex.first(where: { !matchesIn(sentence, with: $0).isEmpty }) {
            return .end
        }

        if let _ = nextRegex.first(where: { !matchesIn(sentence, with: $0).isEmpty }) {
            return .next
        }

        if let _ = previousRegex.first(where: { !matchesIn(sentence, with: $0).isEmpty }) {
            return .previous
        }

        return .none
    }
}

private func matchesIn(_ text: String, with pattern: String) -> [String] {
    let textRange = NSRange(location: 0, length: text.characters.count)
    guard let matches = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return []
    }
    return matches.matches(in: text, options: .reportCompletion, range: textRange).flatMap { res -> [String] in
        var matched = [String]()
        for i in 0..<res.numberOfRanges {
            let range = res.rangeAt(i)
            let str = (text as NSString).substring(with: range) as String
            matched.append(str)
        }
        return matched
    }
}
