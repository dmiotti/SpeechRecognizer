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

private let sentenceToken = "ok chef"

final class SpeechViewController: UIViewController {
    // MARK: Properties

    @IBOutlet weak var textView: UITextView!

    @IBOutlet weak var recordButton: UIButton!

    @IBOutlet weak var localeLabel: UILabel!

    @IBOutlet weak var currentStepLabel: UILabel!

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

    private var lastSpeechRecognitionResult: SFSpeechRecognitionResult?

    private var shouldRestart = false
    private var isStopping = false
    private var timeoutTimer: Timer?

    private var recipe = Recipe(title: "Nems aux fraises", description: "Dessert facile et bon marché. Végétarien", steps: [
        "Laver les fraises sous l'eau et les équeuter.",
        "Les couper en morceaux dans un saladier et les saupoudrer de sucre.",
        "Etaler vos feuilles de brick sur un plan de travail et couper les en deux.",
        "Beurrer les feuilles de brick à l'aide d'un pinceau et déposer au centre quelques morceaux de fraises au sucre.",
        "Poser dessus une cuillère à café de crème pâtissière et rouler les feuilles de brick comme un nem.",
        "Chaque convive trempera ses nems dans le coulis de fruits rouges froid."
    ])

    private var currentStep = 1 {
        didSet {
            currentStepLabel.text = "Step: \(currentStep)"
            appendToTextView("(Moving to step \(currentStep))")
            self.speak(at: currentStep)
        }
    }

    private lazy var speechSynthesizer: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        return synth
    }()

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        localeLabel.text = "Locale \(Locale.current.identifier)"

        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
            try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch let err {
            print("Error while configuring AVAudioSession: \(err)")
        }
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
            try? startRecording()
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

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let inputNode = audioEngine.inputNode else { fatalError("Audio engine has no input node") }
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }
        guard let speechRecognizer = speechRecognizer else { fatalError("Unable to get speechRecognizer") }

        // Configure request so that results are returned before audio recording is finished
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = [ "oups", sentenceToken ]

        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                let hasChanged = self.lastSpeechRecognitionResult?.bestTranscription.formattedString != result.bestTranscription.formattedString
                print("* Receiving: \(result.bestTranscription.formattedString)")
                self.lastSpeechRecognitionResult = result
                isFinal = result.isFinal

                if hasChanged {
                    self.invalidateTimeoutTimer()
                    self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false, block: { (timer) in
                        print("* Speaking timeout reached")
                        self.invalidateTimeoutTimer()
                        if let processed = try? self.processSentence(), processed {
                            self.shouldRestart = true
                            self.stopRecording()
                        } else {
                            self.appendToTextView("(Go ahead, I'm listening)\n")
                        }
                    })
                }
            }

            if error != nil || isFinal {

                self.invalidateTimeoutTimer()

                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
                self.recordButton.setTitle("Start Recording", for: .normal)

                self.isStopping = false

                if let err = error {
                    print("Error while recognizing: \(err)")
                }

                if self.shouldRestart || error != nil {
                    self.shouldRestart = false
                    try! self.startRecording()
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

    private func invalidateTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    fileprivate func appendToTextView(_ text: String) {
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
        }
        text += "\n"
        return text
    }

    private func processSentence() throws -> Bool {
        guard let result = lastSpeechRecognitionResult else {
            return false
        }

        let sentence = result.bestTranscription.formattedString.lowercased()

        /// If the sentence doesn't contains the expected token ignore the rest
        if !sentence.contains(sentenceToken) {
            print("Doesn't contains \(sentenceToken) - Don't process it")
            return false
        }

        let findStrings: (_ regexes: [String]) -> Bool = { regexes -> Bool in
            return regexes.first {
                sentence.range(
                    of: $0,
                    options: [.regularExpression, .caseInsensitive],
                    range: nil,
                    locale: nil) != nil
            } != nil
        }

        // Next using regex
        let nextRegexes = [ "(?:passer|aller)*.*(?:étape).*(?:suivant)" ]
        if findStrings(nextRegexes) {
            appendToTextView(buildText(result: result))
            goToStep(currentStep + 1)
            lastSpeechRecognitionResult = nil
            return true
        }

        // Prev using regex
        let prevRegexes = [ "(?:passer|aller)*.*(?:étape).*(?:précédent)" ]
        if findStrings(prevRegexes) {
            appendToTextView(buildText(result: result))
            goToStep(currentStep - 1)
            lastSpeechRecognitionResult = nil
            return true
        }

        // Step index
        let numberMatching = [
            "zéro": 0,
            "un": 1, "une": 1, "deux": 2, "trois": 3,
            "quatre": 4, "cinq": 5, "six": 6,
            "sept": 7, "huit": 8, "neuf": 9
        ]
        let allKeys = numberMatching.keys.joined(separator: "|")
        let stepIndexRegex = "(?:passer|aller)*.*(?:étape)*.*(\(allKeys))"
        let stepMatches = matchesInCapturingGroups(text: sentence, pattern: stepIndexRegex)
        if let nb = stepMatches.first, let val = numberMatching[nb] {
            appendToTextView(buildText(result: result))
            goToStep(val)
            lastSpeechRecognitionResult = nil
            return true
        }

        // Restart
        if findStrings([ "début", "commencer", "recommencer" ]) {
            appendToTextView(buildText(result: result))
            goToStep(1)
            lastSpeechRecognitionResult = nil
            return true
        }

        // Last
        if findStrings([ "dernière"]) {
            appendToTextView(buildText(result: result))
            goToStep(recipe.steps.count)
            lastSpeechRecognitionResult = nil
            return true
        }

        // Next
        if findStrings([ "prochain", "prochaine", "passer", "suite", "suivant", "après", "next" ]) {
            appendToTextView(buildText(result: result))
            goToStep(currentStep + 1)
            lastSpeechRecognitionResult = nil
            return true
        }

        // Previous
        if findStrings([ "back", "retour", "reviens", "oups", "revenir", "précédent", "avant", "previous" ]) {
            appendToTextView(buildText(result: result))
            goToStep(currentStep - 1)
            lastSpeechRecognitionResult = nil
            return true
        }

        return false
    }

    private func goToStep(_ step: Int) {
        guard step >= 1 && step <= recipe.steps.count else {
            speak(text: "Il n'y a pas d'étape \(step)")
            return
        }
        currentStep = step - 1
    }

    private func getUtterance(text: String) -> AVSpeechUtterance {
        return AVSpeechUtterance(string: text)
    }

    private func speak(at step: Int) {
        appendToTextView("* Start speaking for \(recipe.title) at step \(step + 1)\n")

        var utterances = [AVSpeechUtterance]()

        if step == 0 {
            let titleUtt = getUtterance(text: recipe.title)
            let descUtt = getUtterance(text: recipe.description)
            utterances.append(titleUtt)
            utterances.append(descUtt)
        }

        let stepExplanation = getUtterance(text: "Étape \(step + 1)")
        utterances.append(stepExplanation)

        let instruction = getUtterance(text: recipe.steps[step])
        utterances.append(instruction)

        utterances.forEach { $0.volume = 1 }
        utterances.forEach(speechSynthesizer.speak)
    }

    private func speak(text: String) {
        let utt = getUtterance(text: text)
        speechSynthesizer.speak(utt)
    }
}

extension SpeechViewController: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Start Recording", for: .normal)
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Recognition not available", for: .disabled)
        }
    }
}

extension SpeechViewController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        appendToTextView("('\(utterance.speechString)')\n")
    }
}

private func matchesInCapturingGroups(text: String, pattern: String) -> [String] {
    let textRange = NSRange(location: 0, length: text.characters.count)
    guard let matches = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return []
    }
    return matches.matches(in: text, options: .reportCompletion, range: textRange).map { res -> String in
        let latestRange = res.rangeAt(res.numberOfRanges - 1)
        return (text as NSString).substring(with: latestRange) as String
    }
}
