//
//  StepSpeechRecognizer.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 17/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import Speech
import AVKit
import ApiAI
import SwiftyJSON

private let SpeechSentenceToken = ".*ok chef\\s"
private let SpeechSpeakingTimeout: TimeInterval = 2

typealias SpeechRecognizerAuthorizationStatus = SFSpeechRecognizerAuthorizationStatus

protocol SpeechRecognizerDelegate: class {
    func stepSpeech(recognizer: SpeechRecognizer,
                    authorizationDidChange status: SpeechRecognizerAuthorizationStatus)
    func stepSpeech(recognizer: SpeechRecognizer,
                    availabilityDidChanged available: Bool)
    func stepSpeech(recognizer: SpeechRecognizer,
                    didRecognize move: StepMove, for sentence: String)
    func stepSpeech(recognizer: SpeechRecognizer,
                    startRecognizing sentence: String)
    func stepSpeech(recognizer: SpeechRecognizer,
                    hasListened sentence: String)
    func stepSpeechDidStartRecording(recognizer: SpeechRecognizer)
    func stepSpeechDidStopRecording(recognizer: SpeechRecognizer)
    func stepSpeech(recognizer: SpeechRecognizer, didFail error: Error)
}

final class SpeechRecognizer: NSObject {
    // MARK: Recognizer Properties

    weak var delegate: SpeechRecognizerDelegate?

    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        if let recognizer = SFSpeechRecognizer(locale: Locale.current) {
            recognizer.delegate = self
            return recognizer
        }
        else { return nil }
    }()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let taggerOptions: NSLinguisticTagger.Options = [.joinNames, .omitWhitespace]
    lazy var linguisticTagger: NSLinguisticTagger = {
        let lang = Locale.current.languageCode ?? "fr"
        let tagSchemes = NSLinguisticTagger.availableTagSchemes(forLanguage: lang)
        return NSLinguisticTagger(tagSchemes: tagSchemes, options: Int(self.taggerOptions.rawValue))
    }()

    private lazy var audioEngine: AVAudioEngine = {
        return AVAudioEngine()
    }()

    /// The latest voice recognition result
    private var lastSpeechRecognitionResult: SFSpeechRecognitionResult?

    private lazy var stepAnalyser: StepSpeechAnalyser = {
        return StepSpeechAnalyser()
    }()

    /// The timeout when the sentence spoken by the user should be processed
    /// It's reseted when the user continue speaking
    private var timeoutTimer: Timer?

    var isRunning: Bool {
        return audioEngine.isRunning
    }

    var isAvailable: Bool {
        if let available = speechRecognizer?.isAvailable {
            return available
        }
        return false
    }

    var authorizationStatus: SpeechRecognizerAuthorizationStatus {
        return SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Public functions

    func setup() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
            try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch let err {
            print("Error while configuring AVAudioSession: \(err)")
        }

        checkAuthorizationStatus()
    }

    func stopRecording() {
        invalidateTimer()
        audioEngine.stop()
        audioEngine.inputNode?.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        delegate?.stepSpeechDidStopRecording(recognizer: self)
    }

    func startRecording() throws {
        guard !isRunning else { return }
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let inputNode = audioEngine.inputNode else {
            fatalError("Audio engine has no input node")
        }
        guard let speechRecognizer = speechRecognizer else {
            fatalError("Unable to get speechRecognizer")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request

        // Configure request so that results are returned before audio recording is finished
        request.shouldReportPartialResults = true
        request.contextualStrings = [ "oups", SpeechSentenceToken ]

        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: request,
                                                           resultHandler: recognize)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0,
                             bufferSize: 1024,
                             format: recordingFormat)
        { (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        try audioEngine.start()

        delegate?.stepSpeechDidStartRecording(recognizer: self)
    }

    // MARK: - Private functions

    private func recognize(result: SFSpeechRecognitionResult?,
                           error: Error?) {
        guard audioEngine.isRunning else { return }

        guard let result = result else {
            if let error = error {
                stopRecording()
                delegate?.stepSpeech(recognizer: self, didFail: error)
            }
            return
        }

        let sentence = result.bestTranscription.formattedString

        /// If the result has changed, restart the timer
        if lastSpeechRecognitionResult?.bestTranscription.formattedString != sentence {
            delegate?.stepSpeech(recognizer: self, hasListened: sentence)
            lastSpeechRecognitionResult = result
            restartTimer()
        }
    }

    private func checkAuthorizationStatus() {
        SFSpeechRecognizer.requestAuthorization { status in
            OperationQueue.main.addOperation {
                self.delegate?.stepSpeech(recognizer: self,
                                          authorizationDidChange: status)
            }
        }
    }

    private func restartTimer() {
        invalidateTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: SpeechSpeakingTimeout,
                                            repeats: false,
                                            block: timerReachEnd(_:))
    }

    private func timerReachEnd(_ timer: Timer) {
        print("⚠️ Speaking timeout reached")
        invalidateTimer()
        stopRecording()

        guard let sentence = lastSpeechRecognitionResult?.bestTranscription.formattedString else {
            return
        }

        lastSpeechRecognitionResult = nil

        /// Search for OK, chef
        delegate?.stepSpeech(recognizer: self, startRecognizing: sentence)

        let tokenRange = sentence.range(of: SpeechSentenceToken,
                                        options: [.regularExpression, .caseInsensitive],
                                        range: nil, locale: nil)
        guard let range = tokenRange else {
            delegate?.stepSpeech(recognizer: self,
                                 didRecognize: .none(recovery: nil),
                                 for: sentence)
            return
        }

        let pattern = sentence
            .substring(with: range.upperBound..<sentence.endIndex)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        stepAnalyser.process(sentence: pattern) { move in
            self.delegate?.stepSpeech(recognizer: self,
                                 didRecognize: move,
                                 for: pattern)
        }

        /// Linguistic tagging doesn't seems to work
        linguisticTagger.string = sentence
        linguisticTagger.enumerateTags(in: NSRange(location: 0, length: sentence.characters.count),
                                       scheme: NSLinguisticTagSchemeNameTypeOrLexicalClass,
                                       options: taggerOptions,
                                       using: { (tag, tokenRange, _, _) in

                                        let token = (sentence as NSString).substring(with: tokenRange)
                                        print("\(token) -> \(tag)")
        })
    }

    private func invalidateTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
}

extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                          availabilityDidChange available: Bool) {
        delegate?.stepSpeech(recognizer: self, availabilityDidChanged: available)
    }
}
