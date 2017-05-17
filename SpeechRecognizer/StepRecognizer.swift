//
//  StepSpeechRecognizer.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 17/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import Speech
import AVKit

private let SpeechSentenceToken = "ok chef"
private let SpeechSpeakingTimeout: TimeInterval = 3

typealias StepRecognizerAuthorizationStatus = SFSpeechRecognizerAuthorizationStatus

protocol StepRecognizerDelegate: class {
    func stepSpeech(recognizer: StepRecognizer, authorizationDidChange status: StepRecognizerAuthorizationStatus)
    func stepSpeech(recognizer: StepRecognizer, availabilityDidChanged available: Bool)
    func stepSpeech(recognizer: StepRecognizer, didRecognize move: StepMove, for sentence: String)
    func stepSpeechDidStartRecording(recognizer: StepRecognizer)
    func stepSpeechDidStopRecording(recognizer: StepRecognizer)
}

final class StepRecognizer: NSObject {
    // MARK: Recognizer Properties

    weak var delegate: StepRecognizerDelegate?

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

    /// True if the recognizer is currently stopping
    private var isStopping = false

    /// The timeout when the sentence spoken by the user should be processed
    /// It's reseted when the user continue speaking
    private var timeoutTimer: Timer?

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

    var isRunning: Bool {
        return audioEngine.isRunning
    }

    func stopRecording() {
        isStopping = true
        audioEngine.stop()
        recognitionRequest?.endAudio()
        finishStoppingRecording()
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
        recognitionTask = speechRecognizer.recognitionTask(with: request, resultHandler: recognize)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        try audioEngine.start()

        delegate?.stepSpeechDidStartRecording(recognizer: self)
    }

    private func recognize(result: SFSpeechRecognitionResult?, error: Error?) {
        guard audioEngine.isRunning else { return }
        if let result = result {
            let sentence = result.bestTranscription.formattedString
            print("🎤 \(sentence)")

            let hasChanged = lastSpeechRecognitionResult?.bestTranscription.formattedString != sentence
            lastSpeechRecognitionResult = result

            if hasChanged {
                restartTimer()
            }
        }
        if let error = error {
            print("Error while recognizing: \(error)")
            self.stopRecording()
        }
    }

    private func finishStoppingRecording() {
        invalidateTimer()
        audioEngine.stop()
        audioEngine.inputNode?.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isStopping = false
        lastSpeechRecognitionResult = nil
    }

    private func checkAuthorizationStatus() {
        SFSpeechRecognizer.requestAuthorization { status in
            OperationQueue.main.addOperation {
                self.delegate?.stepSpeech(recognizer: self, authorizationDidChange: status)
            }
        }
    }

    private func restartTimer() {
        invalidateTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: SpeechSpeakingTimeout, repeats: false) { _ in
            print("⚠️ Speaking timeout reached")
            self.invalidateTimer()
            if let sentence = self.lastSpeechRecognitionResult?.bestTranscription.formattedString {
                let stepMove = StepProcessor.nextStep(sentence: sentence)
                self.delegate?.stepSpeech(recognizer: self, didRecognize: stepMove, for: sentence)
                self.stopRecording()
            }
        }
    }

    private func invalidateTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
}

extension StepRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        delegate?.stepSpeech(recognizer: self, availabilityDidChanged: available)
    }
}
