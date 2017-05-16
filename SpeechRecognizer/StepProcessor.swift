//
//  StepProcessor.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 16/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit

final class StepProcessor: NSObject {
    class func nextStep(sentence: String, current: Int, in recipe: Recipe) -> Int? {
        /// Step (n)
        let numbersPrefix = [
            "un": 1, "une": 1, "deux": 2, "trois": 3,
            "quatre": 4, "cinq": 5, "six": 6,
            "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "onze": 11,
            "initial": 1, "final": recipe.steps.count
        ]
        let prefixKeys = numbersPrefix.keys.joined(separator: "|")
        let prefixRegex = "(?:étape).*(\(prefixKeys))"
        let prefixMatches = matchesInCapturingGroups(text: sentence, pattern: prefixRegex)
        if let nb = prefixMatches.flatMap({ numbersPrefix[$0] }).first {
            return nb - 1
        }

        let numbersSuffix = [
            "première": 1, "premier": 1, "deuxième": 2, "troisième": 3,
            "quatrième": 4, "cinquième": 5, "sixième": 6,
            "septième": 7, "huitième": 8, "neuvième": 9, "dixième": 10, "onzième": 11,
            "dernière": recipe.steps.count
        ]
        let suffixKeys = numbersSuffix.keys.joined(separator: "|")
        let numberSuffixRegex = "(\(suffixKeys).*(?:étape))"
        let numberSuffixMatches = matchesInCapturingGroups(text: sentence, pattern: numberSuffixRegex)
        if let nb = numberSuffixMatches.flatMap({ numbersSuffix[$0] }).first {
            return nb - 1
        }

        /// Restart
        let restartPatterns = [ "début", "commencer", "first" ]
        if hasMatchedRegexes(in: sentence, regexes: restartPatterns) {
            return 0
        }

        /// Ends
        let latestPatterns = [ "dernière", "last", "fin" ]
        if hasMatchedRegexes(in: sentence, regexes: latestPatterns) {
            return recipe.steps.count - 1
        }

        /// Next step
        let nextRegexes = [ "(?:étape).*(?:suivant)", "prochain", "suite", "suivant", "après", "next" ]
        if hasMatchedRegexes(in: sentence, regexes: nextRegexes) {
            return current + 1
        }

        /// Previous step
        let previousPatterns = [ "(?:étape).*(?:précédent)", "back", "retour", "reviens", "oups", "revenir", "précédent", "avant", "previous" ]
        if hasMatchedRegexes(in: sentence, regexes: previousPatterns) {
            return current - 1
        }
        
        return nil
    }
}

private func hasMatchedRegexes(in sentence: String, regexes: [String]) -> Bool {
    let preprendRegexes = regexes.map { "ok.*chef.*" + $0 }
    return preprendRegexes.first {
        sentence.range(
            of: $0,
            options: [.regularExpression, .caseInsensitive],
            range: nil,
            locale: nil) != nil
        } != nil
}

private func matchesInCapturingGroups(text: String, pattern: String) -> [String] {
    let regex = "ok.*chef.*" + pattern
    let textRange = NSRange(location: 0, length: text.characters.count)
    guard let matches = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else {
        return []
    }
    return matches.matches(in: text, options: .reportCompletion, range: textRange).map { res -> String in
        let latestRange = res.rangeAt(res.numberOfRanges - 1)
        return (text as NSString).substring(with: latestRange) as String
    }
}
