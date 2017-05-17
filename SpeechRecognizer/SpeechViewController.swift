//
//  SpeechViewController.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 15/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit

final class SpeechViewController: UIViewController {
    // MARK: UI Properties

    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var localeLabel: UILabel!
    @IBOutlet weak var currentStepLabel: UILabel!
    @IBOutlet weak var recipeButton: UIButton!

    fileprivate lazy var stepRecognizer: StepRecognizer = {
        return StepRecognizer()
    }()
    fileprivate var shouldRecord = false

    // MARK: Speaker Properties

    private lazy var speaker: Speaker = {
        let speaker = Speaker()
        speaker.delegate = self
        return speaker
    }()

    // MARK: Model Properties

    private var recipes = RecipeLibrary.shared.recipies

    /// The recipe we walk through
    private var recipe: Recipe? {
        didSet {        
            if let recipe = recipe {
                recipeButton.setTitle(recipe.title, for: .normal)
                applyStep(move: .beginning)
            } else {
                recipeButton.setTitle("Pick a recipe", for: .normal)
            }
        }
    }

    // The current `recipe.steps[currentStep]`
    private var currentStep = -1

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        localeLabel.text = "(\(Locale.current.identifier))"

        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false

        stepRecognizer.delegate = self
        stepRecognizer.setup()

        loadRemoteCSV()
    }

    // MARK: Interface Builder actions

    @IBAction func recordButtonTapped() {
        if shouldRecord {
            shouldRecord = false
            stepRecognizer.stopRecording()
        } else {
            shouldRecord = true
            try? stepRecognizer.startRecording()
        }
    }

    @IBAction func recipesButtonTapped(_ sender: Any) {
        let actionSheet = UIAlertController(title: "Pick a recipe", message: nil, preferredStyle: .actionSheet)
        recipes.forEach { recipe in
            let action = UIAlertAction(title: recipe.title, style: .default) { _ in
                self.recipe = recipe
            }
            actionSheet.addAction(action)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .default, handler: nil)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true)
    }

    @IBAction func refreshButtonTapped(_ sender: Any) {
        loadRemoteCSV()
    }

    private func loadRemoteCSV() {
        let pending = UIAlertController(title: "Loading Regular Expressions", message: "Fetching over network it can be slow", preferredStyle: .alert)
        present(pending, animated: true)
        loadCSV { self.dismiss(animated: true) }
    }

    // MARK: Private methods

    fileprivate func appendToTextView(_ text: String) {
        textView.text = text + "\n\n" + (textView.text ?? "")
    }

    fileprivate func applyStep(move: StepMove) {
        guard let recipe = recipe else { return }
        let goToStep: (Int) -> Void = { step in
            guard step >= -1 && step < recipe.steps.count else {
                self.speaker.speak(text: "Il n'y a pas d'étape \(step + 1)")
                return
            }
            self.currentStep = step
            self.currentStepLabel.text = "Step: \(step + 1)"
            self.speak(at: step)
        }
        switch move {
        case .at(let position):
            goToStep(position - 1)
        case .beginning:
            goToStep(-1)
        case .end:
            goToStep(recipe.steps.count - 1)
        case .next:
            goToStep(currentStep + 1)
        case .previous:
            goToStep(currentStep - 1)
        case .repeat:
            goToStep(currentStep)
        case .none:
            break
        }
    }

    private func speak(at step: Int) {
        guard let recipe = recipe else { return }
        var sentences = [String]()
        if step == -1 {
            sentences.append(recipe.title)
            sentences.append(recipe.description)
        } else {
            sentences.append("Étape \(step + 1)")
            sentences.append(recipe.steps[step])
        }
        sentences.forEach(speaker.speak)
    }
}

extension SpeechViewController: SpeakerDelegate {
    func speaker(speaker: Speaker, didSpeak sentence: String) {
        appendToTextView("🔊 \(sentence)")
    }

    func speakerDidFinishSpeaking(speaker: Speaker) {
        if shouldRecord {
            try? stepRecognizer.startRecording()
        }
    }
}

extension SpeechViewController: StepRecognizerDelegate {
    func stepSpeech(recognizer: StepRecognizer, availabilityDidChanged available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Start recording", for: .normal)
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Voice recognizer unavailable", for: .disabled)
        }
    }

    func stepSpeech(recognizer: StepRecognizer, authorizationDidChange status: StepRecognizerAuthorizationStatus) {
        switch status {
        case .authorized:
            recordButton.setTitle("Start recording", for: .normal)
            recordButton.isEnabled = true
        case .denied:
            recordButton.isEnabled = false
            recordButton.setTitle("User denied access to speech recognition", for: .disabled)
        case .restricted:
            recordButton.isEnabled = false
            recordButton.setTitle("Speech recognition restricted on this device", for: .disabled)
        case .notDetermined:
            recordButton.isEnabled = false
            recordButton.setTitle("Speech recognition not yet authorized", for: .disabled)
        }
    }

    func stepSpeech(recognizer: StepRecognizer, didRecognize move: StepMove, for sentence: String) {
        appendToTextView("🎤 \(sentence)")
        applyStep(move: move)
        switch move {
        case .none:
            appendToTextView("👨🏼‍🚀 (Sorry I didn't understand you)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? self.stepRecognizer.startRecording()
            }
        default:
            break
        }
    }

    func stepSpeechDidStartRecording(recognizer: StepRecognizer) {
        appendToTextView("👨🏼‍🚀 (Go ahead, I'm listening)")
        recordButton.setTitle("Stop recording", for: .normal)
    }

    func stepSpeechDidStopRecording(recognizer: StepRecognizer) {
        recordButton.isEnabled = true
        recordButton.setTitle("Start recording", for: .normal)
        appendToTextView("👨🏼‍🚀 (Nah, I'm stopping listening you)")
    }
}

