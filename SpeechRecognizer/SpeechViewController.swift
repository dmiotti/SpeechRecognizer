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

private let SpeechSentenceToken = "ok chef"
private let SpeechSpeakingTimeout: TimeInterval = 3

final class SpeechViewController: UIViewController {
    // MARK: UI Properties

    @IBOutlet weak var textView: UITextView!

    @IBOutlet weak var recordButton: UIButton!

    @IBOutlet weak var localeLabel: UILabel!

    @IBOutlet weak var currentStepLabel: UILabel!

    @IBOutlet weak var recipeButton: UIButton!

    // MARK: Recognizer Properties

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
    /// Should we restart the speech recognizer if it fails
    private var shouldRestart = false
    /// True if the recognizer is currently stopping
    private var isStopping = false
    /// The timeout when the sentence spoken by the user should be processed
    /// It's reseted when the user continue speaking
    private var timeoutTimer: Timer?

    // MARK: Speaker Properties

    /// Used to speak, mostly `recipe.steps[currentStep]` to the user
    private lazy var speechSynthesizer: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        return synth
    }()

    // MARK: Model Properties

    private var recipes = RecipeLibrary.shared.recipies

    /// The recipe we walk through
    private var recipe: Recipe? {
        didSet {
            currentStep = -1
            if let recipe = recipe {
                recipeButton.setTitle(recipe.title, for: .normal)
                speak(text: "Vous avez choisi \(recipe.title) !")
            } else {
                recipeButton.setTitle("Choisir une recette", for: .normal)
            }
        }
    }

    // The current `recipe.step`
    private var currentStep = 0 {
        didSet {
            if currentStep >= 0 {
                let str = "Étape: \(currentStep + 1)"
                currentStepLabel.text = str
                appendToTextView("➡️ \(str)")
                speak(at: currentStep)
            }
        }
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        localeLabel.text = "(\(Locale.current.identifier))"

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
            do {
                try startRecording()
            } catch let err {
                print("Error while starting recording: \(err)")
            }
        }
    }

    @IBAction func recipesButtonTapped(_ sender: Any) {
        let actionSheet = UIAlertController(title: "Choisir une recette", message: nil, preferredStyle: .actionSheet)
        recipes.forEach { recipe in
            let action = UIAlertAction(title: recipe.title, style: .default) { _ in
                self.recipe = recipe
            }
            actionSheet.addAction(action)
        }
        let cancelAction = UIAlertAction(title: "Annuler", style: .default, handler: nil)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true)
    }

    // MARK: Private methods

    private func startRecording() throws {
        recordButton.setTitle("Arrêter l'enregistrement", for: .normal)

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
        recognitionRequest.contextualStrings = [ "oups", SpeechSentenceToken ]

        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                let sentence = result.bestTranscription.formattedString
                print("🎤 \(sentence)")
                let hasChanged = self.lastSpeechRecognitionResult?.bestTranscription.formattedString != result.bestTranscription.formattedString
                self.lastSpeechRecognitionResult = result
                isFinal = result.isFinal
                if hasChanged {
                    self.invalidateTimeoutTimer()
                    self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: SpeechSpeakingTimeout, repeats: false) { timer in
                        print("⚠️ Speaking timeout reached")
                        self.invalidateTimeoutTimer()
                        if let step = self.nextStep(sentence: sentence, current: self.currentStep) {
                            self.goToStep(step)
                            self.shouldRestart = true
                            self.stopRecording()
                        } else {
                            self.appendToTextView("👨🏼‍🚀 (I didn't understand you, please try again)")
                        }
                    }
                }
            }

            if error != nil || isFinal {
                self.appendToTextView("👨🏼‍🚀 (Nah, I'm stopping listening you)")

                self.invalidateTimeoutTimer()

                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
                self.recordButton.setTitle("Commencer l'enregistrement", for: .normal)

                self.isStopping = false

                if let error = error {
                    print("\(Date()) Error while recognizing: \(error)")
                    if (error as NSError).code == 203 {
                        return
                    }
                }

                if self.shouldRestart || error != nil {
                    self.shouldRestart = false
                    try? self.startRecording()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        try audioEngine.start()

        appendToTextView("👨🏼‍🚀 (Go ahead, I'm listening)")
    }

    private func invalidateTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    fileprivate func appendToTextView(_ text: String) {
        textView.text = text + "\n\n" + (textView.text ?? "")
    }

    private func stopRecording() {
        isStopping = true
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recordButton.isEnabled = false
        recordButton.setTitle("Arrêt en cours", for: .disabled)
    }

    private func nextStep(sentence: String, current: Int) -> Int? {
        guard let recipe = recipe else { return nil }
        let sentence = sentence.lowercased()
        if !sentence.contains(SpeechSentenceToken) {
            appendToTextView("👩🏼‍🚀 (Missing 'OK chef' token, skipping)")
            return nil
        }

        let nextRegexes = [ "(?:étape).*(?:suivant)" ]
        if hasMatchedRegexes(in: sentence, regexes: nextRegexes) {
            return current + 1
        }

        let prevRegexes = [ "(?:étape).*(?:précédent)" ]
        if hasMatchedRegexes(in: sentence, regexes: prevRegexes) {
            return current - 1
        }

        let numbersPrefix = [
            "un": 1, "une": 1, "deux": 2, "trois": 3,
            "quatre": 4, "cinq": 5, "six": 6,
            "sept": 7, "huit": 8, "neuf": 9,
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
            "septième": 7, "huitième": 8, "neuvième": 9,
            "dernière": recipe.steps.count
        ]
        let suffixKeys = numbersSuffix.keys.joined(separator: "|")
        let numberSuffixRegex = "(\(suffixKeys).*(?:étape))"
        let numberSuffixMatches = matchesInCapturingGroups(text: sentence, pattern: numberSuffixRegex)
        if let nb = numberSuffixMatches.flatMap({ numbersSuffix[$0] }).first {
            return nb - 1
        }

        let restartPatterns = [ "début", "commencer", "recommencer", "first" ]
        if hasMatchedRegexes(in: sentence, regexes: restartPatterns) {
            return 0
        }

        let latestPatterns = [ "dernière", "final", "last", "fin" ]
        if hasMatchedRegexes(in: sentence, regexes: latestPatterns) {
            return recipe.steps.count - 1
        }

        let nextPatterns = [ "prochain", "prochaine", "passer", "suite", "suivant", "après", "next" ]
        if hasMatchedRegexes(in: sentence, regexes: nextPatterns) {
            return current + 1
        }

        let previousPatterns = [ "back", "retour", "reviens", "oups", "revenir", "précédent", "avant", "previous" ]
        if hasMatchedRegexes(in: sentence, regexes: previousPatterns) {
            return current - 1
        }

        return nil
    }

    private func goToStep(_ step: Int) {
        guard let recipe = recipe else { return }
        guard step >= 0 && step < recipe.steps.count else {
            speak(text: "Il n'y a pas d'étape \(step + 1)")
            return
        }
        currentStep = step
    }

    private func getUtterance(text: String) -> AVSpeechUtterance {
        return AVSpeechUtterance(string: text)
    }

    private func speak(at step: Int) {
        guard let recipe = recipe else { return }
        var sentences = [String]()
        if step == 0 {
            sentences.append(recipe.title)
            sentences.append(recipe.description)
        }
        sentences.append("Étape \(step + 1)")
        sentences.append(recipe.steps[step])
        sentences.forEach(speak)
    }

    private func speak(text: String) {
        let utt = getUtterance(text: text)
        utt.postUtteranceDelay = 1
        speechSynthesizer.speak(utt)
    }

    private func launchTestingSet() {
        var latest: TimeInterval = 0
        let sendAsync: (String) -> Void = { sentence in
            DispatchQueue.main.asyncAfter(deadline: .now() + latest) {
                self.appendToTextView("🎤 \(sentence)")
                if let step = self.nextStep(sentence: sentence, current: self.currentStep) {
                    self.goToStep(step)
                }
            }
            latest = latest + 20
        }

        sendAsync("OK chef, Commencer")
        sendAsync("OK chef, Prochaine étape")
        sendAsync("OK chef, Étape suivante")
        sendAsync("OK chef, Étape précédente")
        sendAsync("OK chef, Dernière étape")
        sendAsync("OK chef, Cinquième étape")
        sendAsync("OK chef, Étape une")
        sendAsync("OK chef, Revenir au début")
        sendAsync("OK chef, Étape huit")
        sendAsync("Troisième étape")
        sendAsync("OK chef, Première étape")
        sendAsync("OK chef, Étape initiale")
        sendAsync("OK chef, Étape finale")
        sendAsync("Revenir au début. OK chef, Étape finale")
    }
}

extension SpeechViewController: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Commencer l'enregistrement", for: .normal)
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Reconnaissance vocale indisponible", for: .disabled)
        }
    }
}

extension SpeechViewController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        appendToTextView("🔊 \(utterance.speechString)")
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
