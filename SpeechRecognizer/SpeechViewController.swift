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
private let SpeechSpeakingTimeout: TimeInterval = 2

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
            if let recipe = recipe {
                recipeButton.setTitle(recipe.title, for: .normal)
                speak(text: "Vous avez choisi \(recipe.title) !")
                currentStep = -1
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: launchTestSuite)
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

        loadRemoteCSV()
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

    @IBAction func refreshButtonTapped(_ sender: Any) {
        loadRemoteCSV()
    }

    private func loadRemoteCSV() {
        let pending = UIAlertController(title: "Refreshing regular expressions", message: "Fetching over network it can be slow", preferredStyle: .alert)
        present(pending, animated: true)

        CSVImporter.load {
            self.dismiss(animated: true)
        }
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

                        if !sentence.lowercased().contains(SpeechSentenceToken) {
                            self.appendToTextView("👩🏼‍🚀 (Missing 'OK chef' token, skipping)")
                        } else {
                            self.appendToTextView("🎤 \(sentence)")
                            let stepMove = StepProcessor.nextStep(sentence: sentence)
                            self.applyStep(move: stepMove)
                        }
                    }
                }
            }

            if error != nil || isFinal {
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
                        self.shouldRestart = false
                        return
                    }
                }

                if self.shouldRestart || error != nil {
                    self.appendToTextView("👨🏼‍🚀 (Wait a sec, I'm restarting)")
                    self.shouldRestart = false
                    try? self.startRecording()
                } else {
                    self.appendToTextView("👨🏼‍🚀 (Nah, I'm stopping listening you)")
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

    private func applyStep(move: StepMove) {
        guard let recipe = recipe else {
            return
        }
        switch move {
        case .at(let position):
            goToStep(position - 1)
        case .beginning:
            goToStep(0)
        case .end:
            goToStep(recipe.steps.count - 1)
        case .next:
            goToStep(currentStep + 1)
        case .previous:
            goToStep(currentStep - 1)
        case .none:
            break
        }
    }

    private func goToStep(_ step: Int) {
        guard let recipe = recipe else { return }
        guard step >= 0 && step < recipe.steps.count else {
            speak(text: "Il n'y a pas d'étape \(step + 1)")
            return
        }
        currentStep = step
        shouldRestart = true
        stopRecording()
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
        let utt = AVSpeechUtterance(string: text)
        utt.postUtteranceDelay = 1
        speechSynthesizer.speak(utt)
    }

    private func launchTestSuite() {
        var latest: TimeInterval = 0
        let sendAsync: (String) -> Void = { sentence in
            DispatchQueue.main.asyncAfter(deadline: .now() + latest) {
                self.appendToTextView("🎤 \(sentence)")
                self.applyStep(move: StepProcessor.nextStep(sentence: sentence))
            }
            latest = latest + 20
        }

        sendAsync("OK chef, Commencer") // -> 1
        sendAsync("OK chef, Prochaine étape") // -> 2
        sendAsync("OK chef, Étape suivante") // -> 3
        sendAsync("OK chef, Étape précédente") // -> 2
        sendAsync("OK chef, Dernière étape") // -> 7
        sendAsync("OK chef, Cinquième étape") // -> 5
        sendAsync("OK chef, Étape une") // -> 1
        sendAsync("OK chef, Revenir au début") // -> 1
        sendAsync("OK chef, Étape huit") // -> Pas d'étape 7
        sendAsync("Troisième étape") // -> 3ème étape
        sendAsync("OK chef, Première étape") // -> Étape 1
        sendAsync("OK chef, Étape initiale") // -> Étape 1
        sendAsync("OK chef, Étape finale") // -> Étape 7
        sendAsync("Revenir au début. OK chef, Étape finale") // -> Étape 7
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

