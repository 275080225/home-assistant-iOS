//
//  Utils.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/3/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import KeychainAccess
import Shared

// Thanks to http://stackoverflow.com/a/35624018/486182
// Must reboot device after installing new push sounds (http://stackoverflow.com/q/34998278/486182)

// swiftlint:disable:next function_body_length
func movePushNotificationSounds() -> Int {
    var movedFiles = 0

    let fileManager: FileManager = FileManager()

    let libraryPath: URL

    do {
        libraryPath = try fileManager.url(for: .libraryDirectory,
                                          in: FileManager.SearchPathDomainMask.userDomainMask,
                                          appropriateFor: nil, create: false)
    } catch let error as NSError {
        Current.Log.error("Error when building URL for library directory: \(error)")
        return 0
    }

    let librarySoundsPath = libraryPath.appendingPathComponent("Sounds")

    do {
        Current.Log.verbose("Creating sounds directory at \(librarySoundsPath)")
        try fileManager.createDirectory(at: librarySoundsPath, withIntermediateDirectories: true, attributes: nil)
    } catch let error as NSError {
        Current.Log.error("Error creating /Library/Sounds directory: \(error)")
        return 0
    }

    let documentsPath: URL

    do {
        documentsPath = try fileManager.url(for: .documentDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: false)
    } catch let error as NSError {
        Current.Log.error("Error building documents path URL: \(error)")
        return 0
    }

    let fileList: [URL]

    do {
        fileList = try fileManager.contentsOfDirectory(at: documentsPath,
                                                       includingPropertiesForKeys: nil,
                                                       options: FileManager.DirectoryEnumerationOptions())
    } catch let error as NSError {
        Current.Log.error("Error getting contents of documents directory: \(error)")
        return 0
    }

    for file in fileList {
        let finalUrl = librarySoundsPath.appendingPathComponent(file.lastPathComponent)
        Current.Log.verbose("Moving \(file) to \(finalUrl)")
        do {
            Current.Log.verbose("Checking for existence of file at \(finalUrl)")
            try fileManager.removeItem(at: finalUrl)
        } catch let rmError as NSError {
            Current.Log.error("Error removing existing file: \(rmError)")
        }
        do {
            try fileManager.moveItem(at: file, to: finalUrl)
            movedFiles += 1
        } catch let error as NSError {
            Current.Log.error("Error when attempting to move files: \(error)")
        }
    }
    return movedFiles
}

func resetStores() {
    do {
        try keychain.removeAll()
    } catch {
        Current.Log.error("Error when trying to delete everything from Keychain!")
    }

    if let groupDefaults = UserDefaults(suiteName: Constants.AppGroupID) {
        for key in groupDefaults.dictionaryRepresentation().keys {
            groupDefaults.removeObject(forKey: key)
        }
        groupDefaults.synchronize()
    }
}

func openURLInBrowser(urlToOpen: URL) {
    if OpenInChromeController.sharedInstance.isChromeInstalled() && prefs.bool(forKey: "openInChrome") {
        _ = OpenInChromeController.sharedInstance.openInChrome(urlToOpen, callbackURL: nil)
    } else {
        UIApplication.shared.open(urlToOpen, options: [:],
                                  completionHandler: nil)
    }
}

func convertToDictionary(text: String) -> [String: Any]? {
    if let data = text.data(using: .utf8) {
        do {
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            Current.Log.error("Error converting JSON string to dict: \(error)")
        }
    }
    return nil
}

func showAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message,
                                  preferredStyle: UIAlertController.Style.alert)
    alert.addAction(UIAlertAction(title: L10n.okLabel, style: UIAlertAction.Style.default, handler: nil))
    UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true,
                                                                completion: nil)
}

// swiftlint:disable:next cyclomatic_complexity
func setDefaults() {
    if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion"),
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"),
        let stringedShortVersion = shortVersion as? String,
        let stringedBundleVersion = bundleVersion as? String {
        let combined = "\(stringedShortVersion) (\(stringedBundleVersion))"
        prefs.set(stringedBundleVersion, forKey: "lastInstalledBundleVersion")
        prefs.set(stringedShortVersion, forKey: "lastInstalledShortVersion")
        prefs.set(combined, forKey: "lastInstalledVersion")
    }

    if prefs.object(forKey: "openInChrome") == nil && OpenInChromeController().isChromeInstalled() {
        prefs.setValue(true, forKey: "openInChrome")
    }

    if prefs.object(forKey: "confirmBeforeOpeningUrl") == nil {
        prefs.setValue(true, forKey: "confirmBeforeOpeningUrl")
    }

    if prefs.object(forKey: "locationUpdateOnZone") == nil {
        prefs.set(true, forKey: "locationUpdateOnZone")
    }

    if prefs.object(forKey: "locationUpdateOnBackgroundFetch") == nil {
        prefs.set(true, forKey: "locationUpdateOnBackgroundFetch")
    }

    if prefs.object(forKey: "locationUpdateOnSignificant") == nil {
        prefs.set(true, forKey: "locationUpdateOnSignificant")
    }

    if prefs.object(forKey: "locationUpdateOnNotification") == nil {
        prefs.set(true, forKey: "locationUpdateOnNotification")
    }

    if prefs.object(forKey: "autohideToolbar") == nil {
        prefs.setValue(true, forKey: "autohideToolbar")
    }

    if prefs.object(forKey: "analyticsEnabled") == nil {
        prefs.setValue(true, forKey: "analyticsEnabled")
    }

    if prefs.object(forKey: "crashlyticsEnabled") == nil {
        prefs.setValue(true, forKey: "crashlyticsEnabled")
    }

    if prefs.object(forKey: "messagingEnabled") == nil || Current.settingsStore.notificationsEnabled {
        prefs.setValue(true, forKey: "messagingEnabled")
    }

    prefs.synchronize()
}

extension UIImage {
    func scaledToSize(_ size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        self.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
}
