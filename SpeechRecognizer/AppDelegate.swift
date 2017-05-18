//
//  AppDelegate.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 15/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit
import Fabric
import Crashlytics
import CoreSpotlight

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?)
        -> Bool {

            Fabric.with([Crashlytics.self])
            return true
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([Any]?) -> Void)
        -> Bool {

            window?.rootViewController?.restoreUserActivityState(userActivity)
            return true
    }

    func application(_ application: UIApplication,
                     willContinueUserActivityWithType userActivityType: String)
        -> Bool {

            return true
    }

    func application(_ application: UIApplication,
                     didFailToContinueUserActivityWithType userActivityType: String,
                     error: Error) {

        if (error as NSError).code != NSUserCancelledError {
            let message = "The connection to your other device may have been interrupted. Please try again. \(error.localizedDescription)"
            let alert = UIAlertController(title: "Handoff Error", message: message, preferredStyle: .alert)
            let dismiss = UIAlertAction(title: "Dismiss", style: .cancel, handler: nil)
            alert.addAction(dismiss)
            self.window?.rootViewController?.present(alert, animated: true)
        }
    }

    func application(_ application: UIApplication,
                     didUpdate userActivity: NSUserActivity) {
        userActivity.addUserInfoEntries(from: [ ActivityVersionKey: ActivityVersionValue ])
    }
}
