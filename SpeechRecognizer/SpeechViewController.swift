//
//  SpeechViewController.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 15/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit
import CoreSpotlight
import Intents

final class SpeechViewController: UIViewController {
    // MARK: UI Properties

    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var localeLabel: UILabel!
    @IBOutlet weak var currentStepLabel: UILabel!
    @IBOutlet weak var recipeButton: UIButton!
    @IBOutlet weak var liveRecordingLabel: UILabel!

    fileprivate lazy var stepRecognizer: StepRecognizer = {
        return StepRecognizer()
    }()

    // MARK: Speaker Properties

    fileprivate lazy var speaker: Speaker = {
        let speaker = Speaker()
        speaker.delegate = self
        return speaker
    }()

    // MARK: Model Properties

    private lazy var recipes: [Recipe] = {
        return RecipeLibrary.shared.recipes
    }()

    /// The recipe we walk through
    private var recipe: Recipe? {
        didSet {        
            if let recipe = recipe {
                recipeButton.setTitle(recipe.title, for: .normal)
                applyStep(move: .beginning)
                startUserActivity(recipe: recipe)
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
    }

    // MARK: Interface Builder actions

    @IBAction func recordButtonTapped() {
        if stepRecognizer.isRunning {
            stepRecognizer.stopRecording()
        } else {
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

    // MARK: Private methods

    private func startUserActivity(recipe: Recipe) {
        userActivity?.invalidate()

        let activity = NSUserActivity(activityType: ActivityTypeView)
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = true
        activity.expirationDate = .distantFuture
        activity.title = recipe.title
        activity.keywords = Set(recipe.steps + [recipe.title, "recette", "recipe"])
        activity.webpageURL = URL(string: "https://tupperware/recipes/\(recipe.id)")
        activity.requiredUserInfoKeys = Set([ActivityRecipeKey])
        activity.userInfo = [
            ActivityRecipeKey: recipe.id,
            ActivityVersionKey: ActivityVersionValue
        ]

        activity.contentAttributeSet = RecipeLibrary.searchAttributes(for: recipe)

        activity.needsSave = true

        userActivity = activity
        userActivity?.becomeCurrent()
    }

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
            sentences.append(recipe.desc)
        } else {
            sentences.append("Étape \(step + 1)")
            sentences.append(recipe.steps[step])
        }
        sentences.forEach(speaker.speak)
    }

    fileprivate func refreshRecordButton() {
        switch stepRecognizer.authorizationStatus {
        case .authorized:
            if stepRecognizer.isAvailable {
                recordButton.isEnabled = true
                if stepRecognizer.isRunning {
                    recordButton.setTitle("Stop recording", for: .normal)
                } else {
                    recordButton.setTitle("Start recording", for: .normal)
                }
            } else {
                recordButton.isEnabled = false
                recordButton.setTitle("Voice recognizer unavailable", for: .disabled)
            }
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

    override func updateUserActivityState(_ activity: NSUserActivity) {
        if let recipe = recipe {
            activity.addUserInfoEntries(from: [ActivityRecipeKey: recipe.id])
        }
        super.updateUserActivityState(activity)
    }

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        if let userInfo = activity.userInfo {
            if  let recipeId = userInfo[ActivityRecipeKey] as? Int,
                let found = recipes.filter({ $0.id == recipeId.description }).first,
                activity.activityType == ActivityTypeView {

                recipe = found
            }
            else if
                let recipeId = userInfo[CSSearchableItemActivityIdentifier] as? String,
                let found = recipes.filter({ $0.id == recipeId }).first {

                recipe = found
            }
        }
        if  let userInfo = activity.userInfo,
            let recipeInfo = userInfo[ActivityRecipeKey] as? NSArray,
            let found = recipes.first(where: { recipeInfo.contains($0.title) }),
            activity.activityType == ActivityTypeView {

            recipe = found
        }
        super.restoreUserActivityState(activity)
    }
}

extension SpeechViewController: SpeakerDelegate {
    func speaker(speaker: Speaker,
                 didSpeak sentence: String) {
        appendToTextView("🔊 \(sentence)")
    }

    func speakerDidFinishSpeaking(speaker: Speaker) {
        try? stepRecognizer.startRecording()
    }
}

extension SpeechViewController: StepRecognizerDelegate {
    func stepSpeech(recognizer: StepRecognizer,
                    availabilityDidChanged available: Bool) {
        refreshRecordButton()
    }

    func stepSpeech(recognizer: StepRecognizer,
                    authorizationDidChange status: StepRecognizerAuthorizationStatus) {
        refreshRecordButton()
    }

    func stepSpeech(recognizer: StepRecognizer,
                    didRecognize move: StepMove,
                    for sentence: String) {
        appendToTextView("🎤 \(sentence.capitalized)")
        applyStep(move: move)
        switch move {
        case .none(let recovery):
            speaker.speak(text: recovery ?? "Désolé je ne vous ai pas compris")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? self.stepRecognizer.startRecording()
            }
        default:
            break
        }
    }

    func stepSpeechDidStartRecording(recognizer: StepRecognizer) {
        appendToTextView("👨🏼‍🚀 Go ahead, I'm listening")
        refreshRecordButton()
    }

    func stepSpeechDidStopRecording(recognizer: StepRecognizer) {
        refreshRecordButton()
        appendToTextView("👨🏼‍🚀 Nah, I'm stopping listening you")
    }

    func stepSpeech(recognizer: StepRecognizer, startRecognizing sentence: String) {
        appendToTextView("💿 Start recognizing...")
    }

    func stepSpeech(recognizer: StepRecognizer, hasListened sentence: String) {
        liveRecordingLabel.text = "🎤 \(sentence)"
    }

    func stepSpeech(recognizer: StepRecognizer, didFail error: Error) {
        appendToTextView("⚠️ \(error.localizedDescription)")
    }
}
