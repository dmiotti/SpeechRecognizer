//
//  SpeechViewController.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 15/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

/*

 Abstract:
 The primary view controller. The speach-to-text engine is managed an configured here.

 */

import UIKit
import Speech
import AVKit

enum RecipeStepActions {
    case forward
    case backward
    case restart
}

final class SpeechViewController: UIViewController {
    // MARK: Properties

    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        if let recognizer = SFSpeechRecognizer(locale: Locale.current) {
            recognizer.delegate = self
            return recognizer
        }
        else { return nil }
    }()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    private var recognitionTask: SFSpeechRecognitionTask?

    let taggerOptions: NSLinguisticTagger.Options = [.joinNames, .omitWhitespace]

    lazy var linguisticTagger: NSLinguisticTagger = {
        let lang = Locale.current.languageCode ?? "fr"
        let tagSchemes = NSLinguisticTagger.availableTagSchemes(forLanguage: lang)
        return NSLinguisticTagger(tagSchemes: tagSchemes, options: Int(self.taggerOptions.rawValue))
    }()

    private lazy var audioEngine: AVAudioEngine = {
        return AVAudioEngine()
    }()

    @IBOutlet weak var textView: UITextView!

    @IBOutlet weak var recordButton: UIButton!

    @IBOutlet weak var localeLabel: UILabel!

    @IBOutlet weak var currentStepLabel: UILabel!

    private var lastSpeechRecognitionResult: SFSpeechRecognitionResult?

    private var shouldRestart = false
    private var isStopping = false

    private var currentStep = 0 {
        didSet {
            currentStepLabel.text = "Step: \(currentStep)"
        }
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        localeLabel.text = "Locale \(Locale.current.identifier)"

        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false
    }

    override public func viewDidAppear(_ animated: Bool) {
        speechRecognizer?.delegate = self

        SFSpeechRecognizer.requestAuthorization { authStatus in
            /*
             The callback may not be called on the main thread. Add an
             operation to the main queue to update the record button's state.
             */
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.recordButton.isEnabled = true

                case .denied:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("User denied access to speech recognition", for: .disabled)

                case .restricted:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition restricted on this device", for: .disabled)

                case .notDetermined:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition not yet authorized", for: .disabled)
                }
            }
        }
    }

    // MARK: Interface Builder actions

    @IBAction func recordButtonTapped() {
        if audioEngine.isRunning {
            stopRecording()
        } else {
            try! startRecording()
        }
    }

    // MARK: Private methods

    private func startRecording() throws {
        recordButton.setTitle("Stop recording", for: .normal)

        // Cancel the previous task if it's running.
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(AVAudioSessionCategoryRecord)
        try audioSession.setMode(AVAudioSessionModeMeasurement)
        try audioSession.setActive(true, with: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let inputNode = audioEngine.inputNode else { fatalError("Audio engine has no input node") }
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }
        guard let speechRecognizer = speechRecognizer else { fatalError("Unable to get speechRecognizer") }

        // Configure request so that results are returned before audio recording is finished
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = [ "oups" ]

        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                self.lastSpeechRecognitionResult = result
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                if let err = error {
                    print("Error while recognizing: \(err)")
                }
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
                self.recordButton.setTitle("Start Recording", for: .normal)

                self.isStopping = false

//                if try! self.processSentence() {
//                    self.shouldRestart = true
//                    try! self.startRecording()
//                }

                if self.shouldRestart {
                    self.shouldRestart = false
                    try! self.startRecording()
                }
            }
            else if !self.isStopping {
                if try! self.processSentence() {
                    self.shouldRestart = true
                    self.stopRecording()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        try audioEngine.start()

        appendToTextView("(Go ahead, I'm listening)\n")
    }

    private func appendToTextView(_ text: String) {
        textView.text = text + "\n" + (textView.text ?? "")
    }

    private func stopRecording() {
        isStopping = true
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recordButton.isEnabled = false
        recordButton.setTitle("Stopping", for: .disabled)
    }

    private func buildText(result: SFSpeechRecognitionResult) -> String {
        let sentence = result.bestTranscription.formattedString
        var text = "Best: \(sentence)\n"
        for (index, transcription) in result.transcriptions.enumerated() {
            text += "[\(index)] \(transcription.formattedString)\n"
            for segment in transcription.segments {
                text += "\t\(segment.substring)\n"
                text += "\t\tConfidence: \(segment.confidence)\n"
                text += "\t\tAlternates: \(segment.alternativeSubstrings.joined(separator: ","))\n"
                text += "\t\tTimestamp: \(segment.timestamp)"
            }
            text += "\n"
        }

        /// LinguisticTagger is not working -_-, at least in french
//        text += "\tTagging\n"
//        self.linguisticTagger.string = sentence
//        self.linguisticTagger.enumerateTags(
//            in: NSRange(location: 0, length: sentence.characters.count),
//            scheme: NSLinguisticTagSchemeNameTypeOrLexicalClass, options: taggerOptions) { (tag, tokenRange, _, _) in
//                let token = (sentence as NSString).substring(with: tokenRange)
//                text += "\t\t\(token) -> \(tag)\n"
//        }

        return text
    }

    private func processSentence() throws -> Bool {
        guard let result = lastSpeechRecognitionResult else {
            return false
        }

        let sentence = result.bestTranscription.formattedString

        let findStrings: (_ regexes: [String]) -> Bool = { regexes -> Bool in
            return regexes.first {
                sentence.range(
                    of: $0,
                    options: [.regularExpression, .caseInsensitive],
                    range: nil,
                    locale: nil) != nil
            } != nil
        }

//        // Next using regex
//        let nextRegexes = [ "(?:passer|aller).*(?:étape).*(suivant)" ]
//        if findStrings(nextRegexes) {
//            currentStep += 1
//            appendToTextView(buildText(result: result))
//            lastSpeechRecognitionResult = nil
//            return true
//        }
//
//        let prevRegexes = [ "(?:passer|aller).*(?:étape).*(précédent)" ]
//        if findStrings(prevRegexes) {
//            currentStep -= 1
//            appendToTextView(buildText(result: result))
//            lastSpeechRecognitionResult = nil
//            return true
//        }

        // Next
        if findStrings([ "prochain", "prochaine", "passer", "suite", "suivant", "après", "next" ]) {
            currentStep += 1
            appendToTextView(buildText(result: result))
            lastSpeechRecognitionResult = nil
            return true
        }

        // Previous
        if findStrings([ "back", "reviens", "oups", "revenir", "précédent", "avant", "previous" ]) {
            currentStep -= 1
            appendToTextView(buildText(result: result))
            lastSpeechRecognitionResult = nil
            return true
        }

        // Restart
        if findStrings([ "début" ]) {
            currentStep = 0
            appendToTextView(buildText(result: result))
            lastSpeechRecognitionResult = nil
        }

        // Last
        if findStrings([ "dernière"]) {
            currentStep = 99
            appendToTextView(buildText(result: result))
            lastSpeechRecognitionResult = nil
        }

        return false
    }
}

extension SpeechViewController: SFSpeechRecognizerDelegate {
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Start Recording", for: [])
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Recognition not available", for: .disabled)
        }
    }
}
