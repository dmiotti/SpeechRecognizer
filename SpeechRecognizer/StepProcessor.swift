//
//  StepProcessor.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 16/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import ApiAI
import SwiftyJSON

enum StepMove {
    case beginning
    case next
    case previous
    case at(position: Int)
    case end
    case `repeat`
    case none(recovery: String?)
}

final class StepProcessor {
    private lazy var apiAI: ApiAI = {
        let api = ApiAI()
        var configuration = AIDefaultConfiguration()
        configuration.clientAccessToken = ApiAIAccessToken
        api.configuration = configuration
        return api
    }()

    func process(sentence: String, completion: @escaping (StepMove) -> Void) {
        guard let request = self.apiAI.textRequest() else {
            completion(.none(recovery: nil))
            return
        }

        request.query = sentence
        request.setCompletionBlockSuccess({ (request, response) in
            let data = JSON(response ?? [:])["result"]
            print("*** ApiAI ***\n\(data)\n\n")

            var move: StepMove = .none(recovery: data["fullfillment"]["speech"].string)
            if let action = data["action"].string {
                switch action {
                case "next-step":
                    move = .next
                case "previous-step":
                    move = .previous
                case "step-n":
                    var step = data["parameters"]["step"].int
                    if step == nil, let stepStr = data["parameters"]["step"].string {
                        step = Int(stepStr)
                    }
                    if let step = step {
                        move = .at(position: step)
                    }
                case "last-step":
                    move = .end
                case "reset":
                    move = .beginning
                case "repeat":
                    move = .repeat
                default:
                    break
                }
            }

            completion(move)
        }, failure: { (request, error) in
            print("Error: \(String(describing: error))")
            completion(.none(recovery: nil))
        })

        apiAI.enqueue(request)
    }
}
