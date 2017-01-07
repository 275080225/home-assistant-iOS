//
//  SecondViewController.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 3/25/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import UIKit
import Eureka
import PermissionScope
import PromiseKit
import Crashlytics
import SafariServices
import Alamofire

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
class SettingsViewController: FormViewController {

    let prefs = UserDefaults(suiteName: "group.io.robbie.homeassistant")!

    var showErrorConnectingMessage = false

    var baseURL: URL? = nil
    var password: String? = nil
    var configured: Bool = false
    var connectStep: Int = 0 // 0 = pre-configuration, 1 = hostname entry, 2 = password entry

    let discovery = Bonjour()

    override func viewWillDisappear(_ animated: Bool) {
        NSLog("Stopping Home Assistant discovery")
        self.discovery.stopDiscovery()
        self.discovery.stopPublish()
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        let aboutButton = UIBarButtonItem(title: "About",
                                          style: .plain,
                                          target: self,
                                          action: #selector(SettingsViewController.openAbout(_:)))

        self.navigationItem.setRightBarButton(aboutButton, animated: true)

        if let baseURL = prefs.string(forKey: "baseURL") {
            self.baseURL = URL(string: baseURL)!
        }

        if let apiPass = prefs.string(forKey: "apiPassword") {
            self.password = apiPass
        }

        self.configured = (self.baseURL != nil && self.password != nil)

        checkForEmail()

        if showErrorConnectingMessage {
            let alert = UIAlertController(title: "Connection error",
                                          // swiftlint:disable:next line_length
                message: "There was an error connecting to Home Assistant. Please confirm the settings are correct and save to attempt to reconnect.", preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }

        if self.configured == false {
            connectStep = 1
            let queue = DispatchQueue(label: "io.robbie.homeassistant", attributes: [])
            queue.async { () -> Void in
                // swiftlint:disable:next line_length
                NSLog("Attempting to discover Home Assistant instances, also publishing app to Bonjour/mDNS to hopefully have HA load the iOS/ZeroConf components.")
                self.discovery.stopDiscovery()
                self.discovery.stopPublish()

                self.discovery.startDiscovery()
                self.discovery.startPublish()
            }

            NotificationCenter.default.addObserver(self,
                                                   // swiftlint:disable:next line_length
                selector: #selector(SettingsViewController.HomeAssistantDiscovered(_:)),
                name:NSNotification.Name(rawValue: "homeassistant.discovered"),
                object: nil)

            NotificationCenter.default.addObserver(self,
                                                   // swiftlint:disable:next line_length
                selector: #selector(SettingsViewController.HomeAssistantUndiscovered(_:)),
                name:NSNotification.Name(rawValue: "homeassistant.undiscovered"),
                object: nil)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(SettingsViewController.SSEConnectionChange(_:)),
                                               name:NSNotification.Name(rawValue: "sse.opened"),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(SettingsViewController.SSEConnectionChange(_:)),
                                               name:NSNotification.Name(rawValue: "sse.error"),
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(SettingsViewController.Connected(_:)),
                                               name:NSNotification.Name(rawValue: "connected"),
                                               object: nil)

        form
            +++ Section(header: "Discovered Home Assistants", footer: "") {
                $0.tag = "discoveredInstances"
                $0.hidden = true
            }

            +++ Section(header: "Connection", footer: "")
            <<< URLRow("baseURL") {
                $0.title = "URL"
                $0.value = self.baseURL
                $0.placeholder = "https://homeassistant.myhouse.com"
                $0.disabled = Condition(booleanLiteral: (self.configured && showErrorConnectingMessage == false))
                }.onChange { row in
                    if row.value == URL(string: "https://") { return }
                    let apiPasswordRow: PasswordRow = self.form.rowBy(tag: "apiPassword")!
                    apiPasswordRow.value = ""
                    if let url = row.value {
                        let cleanUrl = HomeAssistantAPI.sharedInstance.CleanBaseURL(baseUrl: url)
                        if !cleanUrl.hasValidScheme {
                            let message = "The URL must begin with either http:// or https://."
                            let alert = UIAlertController(title: "Invalid URL",
                                                          message: message,
                                                          preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else {
                            self.baseURL = cleanUrl.cleanedURL
                        }
                    }
                }.cellUpdate { cell, row in
                    if row.isHighlighted {
                        row.value = URL(string: "https://")
                    } else {
                        if row.value == URL(string: "https://") {
                            row.value = nil
                            cell.update()
                        }
                    }
            }

            <<< PasswordRow("apiPassword") {
                $0.title = "Password"
                $0.value = self.password
                $0.disabled = Condition(booleanLiteral: self.configured && showErrorConnectingMessage == false)
                $0.hidden = Condition(booleanLiteral: self.connectStep == 1)
                $0.placeholder = "password"
                }.onChange { row in
                    self.password = row.value
            }

            <<< ButtonRow("connect") {
                $0.title = "Connect"
                $0.hidden = Condition(booleanLiteral: self.configured)
                }.onCellSelection { _, row in
                    if self.connectStep == 1 {
                        if let url = self.baseURL {
                            // swiftlint:disable:next line_length
                            HomeAssistantAPI.sharedInstance.GetDiscoveryInfo(baseUrl: url).then { discoveryInfo -> Void in
                                let urlRow: URLRow = self.form.rowBy(tag: "baseURL")!
                                urlRow.disabled = true
                                urlRow.evaluateDisabled()
                                let apiPasswordRow: PasswordRow = self.form.rowBy(tag: "apiPassword")!
                                apiPasswordRow.value = ""
                                apiPasswordRow.hidden = Condition(booleanLiteral: !discoveryInfo.RequiresPassword)
                                apiPasswordRow.evaluateHidden()
                                let discoverySection: Section = self.form.sectionBy(tag: "discoveredInstances")!
                                discoverySection.hidden = true
                                discoverySection.evaluateHidden()
                                self.connectStep = 2
                                }.catch { error in
                                    print("Hit error when attempting to get discovery information", error)
                                    let alert = UIAlertController(title: "Error during connection attempt",
                                                                  // swiftlint:disable:next line_length
                                        message: "\(error.localizedDescription)\r\n\r\nPlease try again.",
                                        preferredStyle: UIAlertControllerStyle.alert)
                                    alert.addAction(UIAlertAction(title: "OK",
                                                                  style: UIAlertActionStyle.default, handler: nil))
                                    self.present(alert, animated: true, completion: nil)
                            }
                        }
                    } else if self.connectStep == 2 {
                        firstly {
                            HomeAssistantAPI.sharedInstance.Setup(baseAPIUrl: self.baseURL!.absoluteString,
                                                                  APIPassword: self.password!)
                            }.then {_ in
                                HomeAssistantAPI.sharedInstance.Connect()
                            }.then { config -> Void in
                                print("Connected!")
                                let apiPasswordRow: PasswordRow = self.form.rowBy(tag: "apiPassword")!
                                apiPasswordRow.disabled = true
                                apiPasswordRow.evaluateDisabled()
                                self.connectStep = 1
                                row.hidden = true
                                row.evaluateHidden()
                                if let url = self.baseURL {
                                    self.prefs.setValue(url.absoluteString, forKey: "baseURL")
                                }
                                if let password = self.password {
                                    self.prefs.setValue(password, forKey: "apiPassword")
                                }
                                self.prefs.synchronize()
                                self.form.setValues(["locationName": config.LocationName, "version": config.Version])
                                let locationNameRow: LabelRow = self.form.rowBy(tag: "locationName")!
                                locationNameRow.updateCell()
                                let versionRow: LabelRow = self.form.rowBy(tag: "version")!
                                versionRow.updateCell()
                                let statusSection: Section = self.form.sectionBy(tag: "status")!
                                statusSection.hidden = false
                                statusSection.evaluateHidden()
                                let detailsSection: Section = self.form.sectionBy(tag: "details")!
                                detailsSection.hidden = false
                                detailsSection.evaluateHidden()
                                let resetSection: Section = self.form.sectionBy(tag: "reset")!
                                resetSection.hidden = false
                                resetSection.evaluateHidden()
                                let alert = UIAlertController(title: "Connected",
                                                              // swiftlint:disable:next line_length
                                    message: "Please force quit and re-open the app to continue.",
                                    preferredStyle: UIAlertControllerStyle.alert)
                                alert.addAction(UIAlertAction(title: "OK",
                                                              style: UIAlertActionStyle.default, handler: nil))
                                self.present(alert, animated: true, completion: nil)
                            }.catch { error in
                                print("Connection error!", error)
                                var errorMessage = error.localizedDescription
                                if let error = error as? AFError {
                                    if error.responseCode == 401 {
                                        errorMessage = "The password was incorrect."
                                    }
                                }
                                // swiftlint:disable:next line_length
                                let alert = UIAlertController(title: "Error during connection with authentication attempt",
                                                              message: "\(errorMessage)\r\n\r\nPlease try again.",
                                    preferredStyle: UIAlertControllerStyle.alert)
                                alert.addAction(UIAlertAction(title: "OK",
                                                              style: UIAlertActionStyle.default,
                                                              handler: nil))
                                self.present(alert, animated: true, completion: nil)
                        }
                    }
            }

            +++ Section(header: "Status", footer: "") {
                $0.tag = "status"
                $0.hidden = Condition(booleanLiteral: !self.configured)
            }
            <<< LabelRow("locationName") {
                $0.title = "Name"
                $0.value = "My Home Assistant"
                if let locationName = prefs.string(forKey: "location_name") {
                    $0.value = locationName
                }
            }
            <<< LabelRow("version") {
                $0.title = "Version"
                $0.value = "0.35.0"
                if let version = prefs.string(forKey: "version") {
                    $0.value = version
                }
            }
            <<< LabelRow("connectedToSSE") {
                $0.title = "Connected"
                $0.value = HomeAssistantAPI.sharedInstance.sseConnected ? "✔️" : "✖️"
            }
            <<< LabelRow("iosComponentLoaded") {
                $0.title = "iOS Component Loaded"
                $0.value = HomeAssistantAPI.sharedInstance.iosComponentLoaded ? "✔️" : "✖️"
            }
            <<< LabelRow("deviceTrackerComponentLoaded") {
                $0.title = "Device Tracker Component Loaded"
                $0.value = HomeAssistantAPI.sharedInstance.deviceTrackerComponentLoaded ? "✔️" : "✖️"
                $0.hidden = Condition(booleanLiteral: HomeAssistantAPI.sharedInstance.locationEnabled == false)
            }
            <<< LabelRow("notifyPlatformLoaded") {
                $0.title = "iOS Notify Platform Loaded"
                $0.value = HomeAssistantAPI.sharedInstance.iosNotifyPlatformLoaded ? "✔️" : "✖️"
                $0.hidden = Condition(booleanLiteral: HomeAssistantAPI.sharedInstance.notificationsEnabled == false)
            }

            // swiftlint:disable:next line_length
            +++ Section(header: "", footer: "Device ID is the identifier used when sending location updates to Home Assistant, as well as the target to send push notifications to.")
            <<< TextRow("deviceId") {
                $0.title = "Device ID"
                if let deviceId = prefs.string(forKey: "deviceId") {
                    $0.value = deviceId
                } else {
                    let cleanedString = removeSpecialCharsFromString(text: UIDevice.current.name)
                    $0.value = cleanedString.replacingOccurrences(of: " ", with: "_").lowercased()
                }
                $0.cell.textField.autocapitalizationType = .none
                }.cellUpdate { _, row in
                    if row.isHighlighted == false {
                        self.prefs.setValue(row.value, forKey: "deviceId")
                        self.prefs.synchronize()
                    }
            }
            +++ Section {
                $0.tag = "details"
                $0.hidden = Condition(booleanLiteral: !self.configured)
            }
            //            <<< ButtonRow("displaySettings") {
            //                $0.title = "Display Settings"
            //                $0.presentationMode = .show(controllerProvider: ControllerProvider.callback {
            //                    let view = SettingsDetailViewController()
            //                    view.detailGroup = "display"
            //                    return view
            //                }, onDismiss: { vc in
            //                    let _ = vc.navigationController?.popViewController(animated: true)
            //                })
            //            }

            <<< ButtonRow("enableLocation") {
                $0.title = "Enable location tracking"
                $0.hidden = Condition(booleanLiteral: HomeAssistantAPI.sharedInstance.locationEnabled)
                }.onCellSelection { _, row in
                    let pscope = PermissionScope()

                    pscope.addPermission(LocationAlwaysPermission(),
                                         // swiftlint:disable:next line_length
                        message: "We use this to inform\r\nHome Assistant of your device location and state.")
                    pscope.show({finished, results in
                        if finished {
                            print("Location Permissions finished!", finished, results)
                            if results[0].status == .authorized {
                                HomeAssistantAPI.sharedInstance.trackLocation()
                            }
                            row.hidden = true
                            row.evaluateHidden()
                            let locationSettingsRow: ButtonRow = self.form.rowBy(tag: "locationSettings")!
                            locationSettingsRow.hidden = false
                            locationSettingsRow.evaluateHidden()
                            let deviceTrackerComponentLoadedRow: LabelRow = self.form.rowBy(
                                tag: "deviceTrackerComponentLoaded")!
                            deviceTrackerComponentLoadedRow.hidden = false
                            deviceTrackerComponentLoadedRow.evaluateHidden()
                        }
                    }, cancelled: { (results) -> Void in
                        print("Permissions finished, resetting API!")
                    })
            }

            <<< ButtonRow("locationSettings") {
                $0.title = "Location Settings"
                $0.hidden = Condition(booleanLiteral: !HomeAssistantAPI.sharedInstance.locationEnabled)
                $0.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                    let view = SettingsDetailViewController()
                    view.detailGroup = "location"
                    return view
                    }, onDismiss: { vc in
                        let _ = vc.navigationController?.popViewController(animated: true)
                })
            }

            <<< ButtonRow("enableNotifications") {
                $0.title = "Enable notifications"
                $0.hidden = Condition(booleanLiteral: HomeAssistantAPI.sharedInstance.notificationsEnabled)
                }.onCellSelection { _, row in
                    let pscope = PermissionScope()

                    pscope.addPermission(NotificationsPermission(),
                                         message: "We use this to let you\r\nsend notifications to your device.")
                    pscope.show({finished, results in
                        if finished {
                            print("Notifications Permissions finished!", finished, results)
                            if results[0].status == .authorized {
                                HomeAssistantAPI.sharedInstance.setupPush()
                                row.hidden = true
                                row.evaluateHidden()
                                let notificationSettingsRow: ButtonRow = self.form.rowBy(tag: "notificationSettings")!
                                notificationSettingsRow.hidden = false
                                notificationSettingsRow.evaluateHidden()
                                let notifyPlatformLoadedRow: LabelRow = self.form.rowBy(tag: "notifyPlatformLoaded")!
                                notifyPlatformLoadedRow.hidden = false
                                notifyPlatformLoadedRow.evaluateHidden()
                            }
                        }
                    }, cancelled: { (results) -> Void in
                        print("Permissions finished, resetting API!")
                    })
            }

            <<< ButtonRow("notificationSettings") {
                $0.title = "Notification Settings"
                $0.hidden = Condition(booleanLiteral: !HomeAssistantAPI.sharedInstance.notificationsEnabled)
                $0.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                    print("HomeAssistantAPI.sharedInstance.notificationsEnabled",
                          HomeAssistantAPI.sharedInstance.notificationsEnabled)
                    let view = SettingsDetailViewController()
                    view.detailGroup = "notifications"
                    return view
                    }, onDismiss: { vc in
                        let _ = vc.navigationController?.popViewController(animated: true)
                })
            }

            +++ Section {
                $0.tag = "reset"
                $0.hidden = Condition(booleanLiteral: !self.configured)
            }
            <<< ButtonRow("resetApp") {
                $0.title = "Reset"
                }.cellUpdate { cell, _ in
                    cell.textLabel?.textColor = .red
                }.onCellSelection { _, _ in
                    let alert = UIAlertController(title: "Reset",
                                                  // swiftlint:disable:next line_length
                        message: "Your settings will be reset and this device will be unregistered from push notifications as well as removed from your Home Assistant configuration.",
                        preferredStyle: UIAlertControllerStyle.alert)

                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
                        print("Handle Cancel Logic here")
                    }))

                    alert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { (_) in
                        print("Handle Ok logic here")
                        self.ResetApp()
                    }))

                    self.present(alert, animated: true, completion: nil)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func HomeAssistantDiscovered(_ notification: Notification) {
        let discoverySection: Section = self.form.sectionBy(tag: "discoveredInstances")!
        discoverySection.hidden = false
        discoverySection.evaluateHidden()
        if let userInfo = (notification as Notification).userInfo as? [String:Any] {
            let discoveryInfo = DiscoveryInfoResponse(JSON: userInfo)!
            let needsPass = discoveryInfo.RequiresPassword ? " - Requires password" : ""
            // swiftlint:disable:next line_length
            let detailTextLabel = "\(discoveryInfo.BaseURL!.host!):\(discoveryInfo.BaseURL!.port!) - \(discoveryInfo.Version) - \(discoveryInfo.BaseURL!.scheme!.uppercased()) \(needsPass)"
            if self.form.rowBy(tag: discoveryInfo.LocationName) == nil {
                discoverySection
                    <<< ButtonRow(discoveryInfo.LocationName) {
                        $0.title = discoveryInfo.LocationName
                        $0.cellStyle = UITableViewCellStyle.subtitle
                        }.cellUpdate { cell, _ in
                            cell.textLabel?.textColor = .black
                            cell.detailTextLabel?.text = detailTextLabel
                        }.onCellSelection({ _, _ in
                            let urlRow: URLRow = self.form.rowBy(tag: "baseURL")!
                            urlRow.value = discoveryInfo.BaseURL
                            urlRow.disabled = true
                            urlRow.evaluateDisabled()
                            let apiPasswordRow: PasswordRow = self.form.rowBy(tag: "apiPassword")!
                            apiPasswordRow.value = ""
                            apiPasswordRow.hidden = Condition(booleanLiteral: !discoveryInfo.RequiresPassword)
                            apiPasswordRow.evaluateHidden()
                            self.connectStep = 2
                        })
                self.tableView?.reloadData()
            } else {
                if let readdedRow: ButtonRow = self.form.rowBy(tag: discoveryInfo.LocationName) {
                    readdedRow.hidden = false
                    readdedRow.updateCell()
                    readdedRow.evaluateHidden()
                }
            }
        }
    }

    func HomeAssistantUndiscovered(_ notification: Notification) {
        if let userInfo = (notification as Notification).userInfo {
            if let stringedName = userInfo["name"] as? String {
                if let removingRow: ButtonRow = self.form.rowBy(tag: stringedName) {
                    removingRow.hidden = true
                    removingRow.evaluateHidden()
                    removingRow.updateCell()
                }
            }
        }
        let discoverySection: Section = self.form.sectionBy(tag: "discoveredInstances")!
        discoverySection.hidden = Condition(booleanLiteral: (discoverySection.count < 1))
        discoverySection.evaluateHidden()
    }

    func SSEConnectionChange(_ notification: Notification) {
        let sseRow: LabelRow = self.form.rowBy(tag: "connectedToSSE")!
        if notification.name.rawValue == "sse.opened" {
            sseRow.value = "✔️"
        } else if notification.name.rawValue == "sse.error" {
            sseRow.value = "✖️"
        }
        sseRow.updateCell()
    }

    func Connected(_ notification: Notification) {
        let iosComponentLoadedRow: LabelRow = self.form.rowBy(tag: "iosComponentLoaded")!
        iosComponentLoadedRow.value = HomeAssistantAPI.sharedInstance.iosComponentLoaded ? "✔️" : "✖️"
        iosComponentLoadedRow.updateCell()
        let deviceTrackerComponentLoadedRow: LabelRow = self.form.rowBy(tag: "deviceTrackerComponentLoaded")!
        deviceTrackerComponentLoadedRow.value = HomeAssistantAPI.sharedInstance.deviceTrackerComponentLoaded ? "✔️" : "✖️"
        deviceTrackerComponentLoadedRow.updateCell()
        let notifyPlatformLoadedRow: LabelRow = self.form.rowBy(tag: "notifyPlatformLoaded")!
        notifyPlatformLoadedRow.value = HomeAssistantAPI.sharedInstance.iosNotifyPlatformLoaded ? "✔️" : "✖️"
        notifyPlatformLoadedRow.updateCell()
    }

    @IBOutlet var emailInput: UITextField!
    func emailEntered(_ sender: UIAlertAction) {
        if let email = emailInput.text {
            if emailInput.text != "" {
                print("Captured email", email)
                Crashlytics.sharedInstance().setUserEmail(email)
                print("First launch, setting NSUserDefault.")
                prefs.set(true, forKey: "emailSet")
                prefs.set(email, forKey: "userEmail")
            } else {
                checkForEmail()
            }
        } else {
            checkForEmail()
        }
    }

    func checkForEmail() {
        if prefs.bool(forKey: "emailSet") == false || prefs.string(forKey: "userEmail") == nil {
            print("This is first launch, let's prompt user for email.")
            let alert = UIAlertController(title: "Welcome",
                                          // swiftlint:disable:next line_length
                message: "Please enter the email address you used to sign up for the beta program with.",
                preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: emailEntered))
            alert.addTextField(configurationHandler: {(textField: UITextField!) in
                textField.placeholder = "myawesomeemail@gmail.com"
                textField.keyboardType = .emailAddress
                self.emailInput = textField
            })
            self.present(alert, animated: true, completion: nil)
        }
    }

    func ResetApp() {
        let bundleId = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
        UserDefaults.standard.synchronize()
        self.prefs.removePersistentDomain(forName: bundleId)
        self.prefs.synchronize()

        _ = HomeAssistantAPI.sharedInstance.removeDevice().then { _ in
            print("Done with reset!")
        }
    }

    func openAbout(_ sender: UIButton) {
        let aboutView = AboutViewController()

        let navController = UINavigationController(rootViewController: aboutView)
        self.show(navController, sender: nil)
        //        self.present(navController, animated: true, completion: nil)
    }
}
