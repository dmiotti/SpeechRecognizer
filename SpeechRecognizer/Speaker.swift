//
//  Speaker.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 17/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import Foundation
import Speech

protocol SpeakerDelegate: class {
    func speaker(speaker: Speaker, didSpeak sentence: String)
    func speakerDidFinishSpeaking(speaker: Speaker)
}

final class Speaker: NSObject, AVSpeechSynthesizerDelegate {

    weak var delegate: SpeakerDelegate?

    private var speakLeft = 0 {
        didSet {
            if speakLeft == 0 {
                delegate?.speakerDidFinishSpeaking(speaker: self)
            }
        }
    }

    private lazy var speechSynthesizer: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        return synth
    }()

    func speak(text: String) {
        speakLeft += 1
        let utt = AVSpeechUtterance(string: text)
        utt.postUtteranceDelay = 1
        speechSynthesizer.speak(utt)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        delegate?.speaker(speaker: self, didSpeak: utterance.speechString)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakLeft -= 1
    }
}
