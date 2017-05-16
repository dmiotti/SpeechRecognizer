//
//  Recipe.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 16/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit

struct Recipe {
    private(set) var title: String
    private(set) var description: String
    private(set) var steps: [String]

    init(title: String, description: String, steps: [String]) {
        self.title = title
        self.description = description
        self.steps = steps
    }
}
