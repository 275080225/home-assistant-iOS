//
//  ExtensionDelegate.swift
//  WatchApp Extension
//
//  Created by Robert Trencheny on 9/24/18.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import WatchKit
import ClockKit
import RealmSwift
import Communicator
import UserNotifications
import CleanroomLogger

// swiftlint:disable file_length
class ExtensionDelegate: NSObject, WKExtensionDelegate {
    // MARK: - Properties -

    var pendingBackgroundURLTask: WKRefreshBackgroundTask?
    var backgroundSession: URLSession?
    var downloadTask: URLSessionDownloadTask?
    var sessionError: Error?
    var sessionStartTime: Date?
    var userInfoAccess: NSSecureCoding?

    // MARK: Fileprivate

    fileprivate var watchConnectivityTask: WKWatchConnectivityRefreshBackgroundTask? {
        didSet {
            oldValue?.setTaskCompleted()
        }
    }

    override init() {
        let fileManager = FileManager.default
        let storeDirectoryURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Constants.AppGroupID)?
            .appendingPathComponent("logs", isDirectory: true)

        guard let directoryURL = storeDirectoryURL else {
            fatalError("Unable to get datastoreURL for logger.")
        }

        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                fatalError("Error while attempting to create data store URL: \(error)")
            }
        }

        var configs = [LogConfiguration]()

        let stderr = StandardStreamsLogRecorder(formatters: [XcodeLogFormatter()])
        configs.append(BasicLogConfiguration(recorders: [stderr]))

        if let osLog = OSLogRecorder(formatters: [ReadableLogFormatter()]) {
            configs.append(BasicLogConfiguration(recorders: [osLog]))
        }

        let fileCfg = RotatingLogFileConfiguration(minimumSeverity: .verbose, daysToKeep: 15,
                                                   directoryPath: directoryURL.path,
                                                   formatters: [ReadableLogFormatter()])

        configs.append(fileCfg)

        Log.enable(configuration: configs)
    }

    // MARK: - WKExtensionDelegate -

    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.

        Log.verbose?.message("didFinishLaunching")

        setupWatchCommunicator()

        // schedule the next background refresh
        BackgroundRefreshScheduler.shared.schedule()
    }

    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive.
        // If the application was previously in the background, optionally refresh the user interface.

        Log.verbose?.message("didBecomeActive")
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state.
        // This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message)
        // or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
        Log.verbose?.message("willResignActive")
        BackgroundRefreshScheduler.shared.schedule()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks.
        // Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // crash solving trick: acces the task user info to avoid a rare, but weird crash..
            // (https://forums.developer.apple.com/thread/96504 and
            // https://stackoverflow.com/q/46464660/486182

            userInfoAccess = task.userInfo

            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                // Be sure to complete the background task once you’re done.
                Log.verbose?.message("WKWatchConnectivityRefreshBackgroundTask received")
                scheduleURLSessionIfNeeded()
                BackgroundRefreshScheduler.shared.schedule()
                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Snapshot tasks have a unique completion call, make sure to set your expiration date
                snapshotTask.setTaskCompleted(restoredDefaultState: true,
                                              estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Be sure to complete the connectivity task once you’re done.
                watchConnectivityTask = connectivityTask
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                // Be sure to complete the URL session task once you’re done.
                let identifier = urlSessionTask.sessionIdentifier
                let backgroundConfigObject = URLSessionConfiguration.background(withIdentifier: identifier)
                let backgroundSession = URLSession(configuration: backgroundConfigObject, delegate: self,
                                                   delegateQueue: nil)
                Log.verbose?.message("Rejoining session: \(backgroundSession)")

                // keep the session background task, it will be ended later...
                // https://stackoverflow.com/q/41156386/486182
                self.pendingBackgroundURLTask = urlSessionTask
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
                // Be sure to complete the relevant-shortcut task once you're done.
                relevantShortcutTask.setTaskCompletedWithSnapshot(false)
            case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
                // Be sure to complete the intent-did-run task once you're done.
                intentDidRunTask.setTaskCompletedWithSnapshot(false)
            default:
                // make sure to complete unhandled task types
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    // Triggered when a complication is tapped
    func handleUserActivity(_ userInfo: [AnyHashable: Any]?) {

        if let date = userInfo?[CLKLaunchedTimelineEntryDateKey] as? Date {

            if let family = date.complicationFamilyFromEncodedDate {
                Log.verbose?.message("\(family.description) complication opened app")
            }
        }
    }

    func updateApplicationContext() {
        Log.verbose?.message("active families \(self.activeFamilies)")

        let context = Context(content: ["activeComplications": self.activeFamilies, "model": getModelName()])

        do {
            try Communicator.shared.sync(context: context)
        } catch let error as NSError {
            Log.error?.message("Updating the context failed: \(error)")
        }

        Log.verbose?.message("Set the context")
    }

    func setupWatchCommunicator() {
        Communicator.shared.activationStateChangedObservers.add { state in
            Log.verbose?.message("Activation state changed: \(state)")

            // self.updateApplicationContext()
        }

        Communicator.shared.reachabilityChangedObservers.add { reachability in
            Log.verbose?.message("Reachability changed: \(reachability)")

            // self.updateApplicationContext()
        }

        Communicator.shared.immediateMessageReceivedObservers.add { message in
            Log.verbose?.message("Received message: \(message.identifier)")

            self.endWatchConnectivityBackgroundTaskIfNecessary()
        }

        Communicator.shared.guaranteedMessageReceivedObservers.add { message in
            let realm = Realm.live()

            if message.identifier == "actions" {
                let content = message.content

                if let actionJSONs = content["data"]! as? [[String: Any]] {
                    // swiftlint:disable:next force_try
                    try! realm.write {
                        for actionJSON in actionJSONs {
                            if let action = Action(JSON: actionJSON) {
                                Log.verbose?.message("ACTION \(action)")
                                realm.add(action, update: true)
                            }
                        }
                    }
                }
            }
        }

        Communicator.shared.blobReceivedObservers.add { blob in
            Log.verbose?.message("Received blob: \(blob.identifier)")

            self.endWatchConnectivityBackgroundTaskIfNecessary()
        }

        Communicator.shared.contextUpdatedObservers.add { context in
            Log.verbose?.message("Received context: \(context)")
            self.endWatchConnectivityBackgroundTaskIfNecessary()
        }

        Communicator.shared.complicationInfoReceivedObservers.add { complicationInfo in
            Log.verbose?.message("Received complication info: \(complicationInfo)")

            // self.updateApplicationContext()

            let realm = Realm.live()

            for (family, data) in complicationInfo.content {
                Log.verbose?.message("Family \(family)")
                Log.verbose?.message("Data \(data)")

                if let dataDict = data as? [String: Any], let complicationConfig = WatchComplication(JSON: dataDict) {
                    // swiftlint:disable:next force_try
                    try! realm.write {
                        Log.verbose?.message("Writing \(complicationConfig.Family)")
                        realm.add(complicationConfig, update: true)
                    }
                }
            }

            CLKComplicationServer.sharedInstance().activeComplications?.forEach {
                CLKComplicationServer.sharedInstance().reloadTimeline(for: $0)
            }
            self.endWatchConnectivityBackgroundTaskIfNecessary()
        }
    }

    private func endWatchConnectivityBackgroundTaskIfNecessary() {
        // First check we're not expecting more data
        guard !Communicator.shared.hasPendingDataToBeReceived else { return }
        // And then end the task (if there is one!)
        self.watchConnectivityTask?.setTaskCompleted()
    }

    func scheduleURLSessionIfNeeded() {

        if self.backgroundSession != nil {

            if let sessionStartTime = self.sessionStartTime, Calendar.current.date(byAdding: .minute, value: 10,
                                                                                   to: sessionStartTime)! > Date() {

                // URL session running.. we'll let it do its work!
                Log.warning?.message("URL session already exists, cannot start a new one!")
                return
            } else {

                // timeout reached for URL session, we'll start a new one!
                Log.warning?.message("URL session timeout exceeded, finishing current and starting a new one!")
                completePendingURLSessionTask()
            }
        }

        guard let (backgroundSession, downloadTask) = scheduleURLSession() else {
            Log.warning?.message("URL session cannot be created, probably base uri is not configured!")
            return
        }

        self.sessionStartTime = Date()
        self.backgroundSession = backgroundSession
        self.downloadTask = downloadTask
        Log.verbose?.message("URL session started")
    }

    var activeFamilies: [String] {
        guard let activeComplications = CLKComplicationServer.sharedInstance().activeComplications else { return [] }
        return activeComplications.map { ComplicationGroupMember(family: $0.family).rawValue }
    }

    func makeHTTPPayload() -> Data? {
        var json: [String: Any] = [:]

        json["type"] = "render_complications"
        var templates = [String: [String: String]]()

        let realm = Realm.live()

        let complications = realm.objects(WatchComplication.self)

        // Log.verbose?.message("complications", complications)

        // Log.verbose?.message("activeComplications", self.activeComplications)

        for complication in complications {
            if self.activeFamilies.contains(complication.Family.rawValue) {
                // Log.verbose?.message("ACTIVE COMPLICATION!", complication, complication.Data)
                if let textAreas = complication.Data["textAreas"] as? [String: [String: Any]] {
                    for (key, textArea) in textAreas {
                        // Log.verbose?.message("Got textArea", key, textArea)
                        if let needsRender = textArea["textNeedsRender"] as? Bool, needsRender {
                            // Log.verbose?.message("TEXT NEEDS RENDER!", key)
                            if templates[complication.Template.rawValue] == nil {
                                templates[complication.Template.rawValue] = [String: String]()
                            }
                            templates[complication.Template.rawValue]![key] = textArea["text"] as? String
                        }
                    }
                }
            }
        }

        json["templates"] = templates

        Log.verbose?.message("JSON payload to send \(json)")

        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

func getModelName() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
    return identifier
}

extension ExtensionDelegate: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Log.verbose?.message("Background download was finished, location is \(location)")

        // reset the session error
        self.sessionError = nil

        // extract data on main thead
        //DispatchQueue.main.async { [unowned self] in

            Log.verbose?.message("extracting downloaded data")
            do {
                let data = try Data(contentsOf: location)
                let json = try JSONSerialization.jsonObject(with: data)
                Log.verbose?.message("Got JSON \(json)")
                if let jsonDict = json as? [String: [String: String]] {
                    Log.verbose?.message("JSON Dict1 \(jsonDict)")

                    for (templateName, textAreas) in jsonDict {
                        let pred = NSPredicate(format: "rawTemplate == %@", templateName)
                        let realm = Realm.live()
                        guard let complication = realm.objects(WatchComplication.self).filter(pred).first else {
                            Log.error?.message("Couldn't get complication from DB for \(templateName)")
                            continue
                        }

                        guard var storedAreas = complication.Data["textAreas"] as? [String: [String: Any]] else {
                            Log.error?.message("Couldn't cast stored areas")
                            continue
                        }
                        for (textAreaKey, renderedText) in textAreas {
                            storedAreas[textAreaKey]!["renderedText"] = renderedText
                        }

                        // swiftlint:disable:next force_try
                        try! realm.write {
                            complication.Data["textAreas"] = storedAreas
                        }

                        Log.verbose?.message("complication \(complication.Data)")
                    }
                }

                self.completePendingURLSessionTask()

                // Success
                self.sessionError = nil
            } catch {
                Log.error?.message("Error when parsing JSON \(error)")
                self.sessionError = error
            }

        //}
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Log.error?.message("URL session did complete with error: \(error)")
            completePendingURLSessionTask()
        }

        // keep the session error (if any!)
        self.sessionError = error
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Log.verbose?.message("URL session did finish events")
    }

    fileprivate func completePendingURLSessionTask() {

        self.backgroundSession?.invalidateAndCancel()
        self.backgroundSession = nil
        self.downloadTask = nil
        self.sessionStartTime = nil
        self.pendingBackgroundURLTask?.setTaskCompleted()
        self.pendingBackgroundURLTask = nil

        Log.verbose?.message("URL session COMPLETED")
    }

    func scheduleURLSession() -> (URLSession, URLSessionDownloadTask)? {

        guard let webhookURL = Communicator.shared.mostRecentlyReceievedContext.content["webhook_url"] as? String else {
            // swiftlint:disable:next line_length
            Log.warning?.message("Didn't find webhook URL in context \(Communicator.shared.mostRecentlyReceievedContext)")
            return nil
        }

        let backgroundConfigObject = URLSessionConfiguration.background(withIdentifier: NSUUID().uuidString)
        backgroundConfigObject.sessionSendsLaunchEvents = true
        // 15 seconds timeout for request (after 15 seconds, the task is finished and a crash occurs, so...
        // we have to stop it somehow!)
        // backgroundConfigObject.timeoutIntervalForRequest = 15
        // backgroundConfigObject.timeoutIntervalForResource = 15 // the same for retry interval (no retries!)
        let backgroundSession = URLSession(configuration: backgroundConfigObject, delegate: self, delegateQueue: nil)

        let downloadURL = URL(string: webhookURL)!

        Log.verbose?.message("Render template URL \(downloadURL)")

        var request = URLRequest(url: downloadURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        guard let payload = self.makeHTTPPayload() else {
            Log.warning?.message("Unable to get HTTP payload")
            return nil
        }

        request.httpBody = payload

        let downloadTask = backgroundSession.downloadTask(with: request)
        downloadTask.resume()

        return (backgroundSession, downloadTask)
    }
}
