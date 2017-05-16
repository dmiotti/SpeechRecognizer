//
//  CSVImporter.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 16/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import Foundation
import CSV

private let spreadsheetURLString = "https://docs.google.com/spreadsheets/d/1ZF_G0QflsjcEMOp7E9bYmprFHcvU-zl0gFKNekioL6w/pub?output=csv"

final class CSVImporter {
    class func load(completion: @escaping (Void) -> Void) {
        guard let url = URL(string: spreadsheetURLString) else {
            completion()
            return
        }

        DispatchQueue.global().async {
            do {
                let data = try Data(contentsOf: url)
                let stream = InputStream(data: data)
                var csv = try CSV(stream: stream, codecType: UTF8.self, hasHeaderRow: true)

                var stepN = [String]()
                var start = [String]()
                var end = [String]()
                var next = [String]()
                var previous = [String]()

                while let _ = csv.next() {
                    if let val = csv["Step(N)"], !val.isEmpty {
                        stepN.append(val)
                    }
                    if let val = csv["Start"], !val.isEmpty {
                        start.append(val)
                    }
                    if let val = csv["End"], !val.isEmpty {
                        end.append(val)
                    }
                    if let val = csv["Next"], !val.isEmpty {
                        next.append(val)
                    }
                    if let val = csv["Previous"], !val.isEmpty {
                        previous.append(val)
                    }
                }

                StepProcessor.stepNRegex = stepN
                StepProcessor.startRegex = start
                StepProcessor.endRegex = end
                StepProcessor.nextRegex = next
                StepProcessor.previousRegex = previous

                DispatchQueue.main.async(execute: completion)
            } catch let err {
                print("Error while loading file: \(err)")
                DispatchQueue.main.async(execute: completion)
            }
        }
    }
}
