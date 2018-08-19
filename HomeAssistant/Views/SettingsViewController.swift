//
//  SettingsViewController.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 3/25/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import UIKit
import Eureka
import PromiseKit
import Crashlytics
import SafariServices
import Alamofire
import KeychainAccess
import CoreLocation
import UserNotifications
import Shared
import SystemConfiguration.CaptiveNetwork

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
class SettingsViewController: FormViewController, CLLocationManagerDelegate, SFSafariViewControllerDelegate {
    enum SettingsError: Error {
        case configurationFailed
    }
    var authenticationController: AuthenticationController = AuthenticationController()
    func showAuthenticationViewController(_ viewController: SFSafariViewController) {
        viewController.delegate = self
        self.present(viewController, animated: true, completion: nil)
    }

    weak var delegate: ConnectionInfoChangedDelegate?

    var doneButton: Bool = false

    var showErrorConnectingMessage = false
    var showErrorConnectingMessageError: Error?

    var baseURL: URL?
    var password: String?
    var internalBaseURL: URL?
    var internalBaseURLSSID: String?
    var internalBaseURLEnabled: Bool = false
    var basicAuthUsername: String?
    var basicAuthPassword: String?
    var basicAuthEnabled: Bool = false
    var deviceID: String?
    var useLegacyAuth: Bool = false

    var configured = false
    var connectionInfo: ConnectionInfo?

    let discovery = Bonjour()
    var authLocationManager: CLLocationManager = CLLocationManager()

    override func viewWillDisappear(_ animated: Bool) {
        NSLog("Stopping Home Assistant discovery")
        self.discovery.stopDiscovery()
        self.discovery.stopPublish()
    }

    override func viewWillAppear(_ animated: Bool) {
        self.title = L10n.Settings.NavigationBar.title
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    override func viewDidLoad() {
        super.viewDidLoad()

        let api = HomeAssistantAPI.authenticatedAPI()

        // Initial state
        self.useLegacyAuth = Current.settingsStore.tokenInfo == nil
        self.connectionInfo = Current.settingsStore.connectionInfo

        // Authentication
        self.authLocationManager.delegate = self
        self.authenticationController.presentAuthenticationViewController = { controller in
            self.present(controller, animated: true, completion: nil)
        }

        let aboutButton = UIBarButtonItem(title: L10n.Settings.NavigationBar.AboutButton.title,
                                          style: .plain,
                                          target: self,
                                          action: #selector(SettingsViewController.openAbout(_:)))

        self.navigationItem.setLeftBarButton(aboutButton, animated: true)

        if doneButton {
            let closeSelector = #selector(SettingsViewController.closeSettings(_:))
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self,
                                             action: closeSelector)

            self.navigationItem.setRightBarButton(doneButton, animated: true)
        }

        let keychain = Keychain(service: "io.robbie.homeassistant")
        if let connectionInfo = self.connectionInfo {
            self.baseURL = connectionInfo.baseURL
            self.configured = true
            self.password = keychain["apiPassword"]
            if let url = connectionInfo.internalBaseURL, let ssid = connectionInfo.internalSSID {
                self.internalBaseURL = url
                self.internalBaseURLSSID = ssid
                self.internalBaseURLEnabled = true
            }
        }

        self.deviceID = Current.settingsStore.deviceID

        if showErrorConnectingMessage {
            var errDesc = ""
            if let err = showErrorConnectingMessageError?.localizedDescription {
                errDesc = err
            }
            let alert = UIAlertController(title: L10n.Settings.ConnectionErrorNotification.title,
                                          message: L10n.Settings.ConnectionErrorNotification.message(errDesc),
                                          preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: L10n.okLabel, style: UIAlertActionStyle.default,
                                          handler: nil))
            self.present(alert, animated: true, completion: nil)
        }

        self.configureDiscoveryObservers()

        form
            +++ Section(header: L10n.Settings.DiscoverySection.header, footer: "") {
                $0.tag = "discoveredInstances"
                $0.hidden = true
            }

            +++ Section(header: L10n.Settings.ConnectionSection.header, footer: "")
            <<< URLRow("baseURL") {
                $0.title = L10n.Settings.ConnectionSection.BaseUrl.title
                $0.value = self.baseURL
                $0.placeholder = "https://homeassistant.myhouse.com"
            }.onCellHighlightChanged({ (_, row) in
                if row.isHighlighted == false {
                    if let url = row.value {
                        let cleanUrl = self.cleanBaseURL(baseUrl: url)
                        if !cleanUrl.hasValidScheme {
                            let title = L10n.Settings.ConnectionSection.InvalidUrlSchemeNotification.title
                            let message = L10n.Settings.ConnectionSection.InvalidUrlSchemeNotification.message
                            let alert = UIAlertController(title: title, message: message,
                                                          preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: L10n.okLabel,
                                                          style: UIAlertActionStyle.default,
                                                          handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else {
                            self.baseURL = cleanUrl.cleanedURL
                        }
                    }
                }
            })
            <<< SwitchRow("useLegacyAuth") {
                $0.title = "Use legacy authentication"
                $0.value = self.password != nil
                }.onChange { switchRow in
                    guard let passwordRow = self.form.rowBy(tag: "apiPassword") else {
                        return
                    }

                    self.useLegacyAuth = switchRow.value ?? false
                    passwordRow.hidden = Condition(booleanLiteral: !(switchRow.value ?? false))
                    passwordRow.evaluateHidden()
                    self.tableView.reloadData()
            }
            <<< PasswordRow("apiPassword") {
                $0.title = L10n.Settings.ConnectionSection.ApiPasswordRow.title
                $0.value = self.password
                $0.placeholder = L10n.Settings.ConnectionSection.ApiPasswordRow.placeholder
                $0.hidden = Condition(booleanLiteral: !self.useLegacyAuth)
                }.onChange { row in
                    self.password = row.value
                }.cellUpdate { cell, row in
                    if !row.isValid {
                        cell.titleLabel?.textColor = .red
                    }
                }

            <<< SwitchRow("internalUrl") {
                $0.title = "Use internal URL"
                $0.value = self.internalBaseURLEnabled
            }.onChange { row in
                if let boolVal = row.value {
                    print("Setting rows to val", !boolVal)
                    let ssidRow: LabelRow = self.form.rowBy(tag: "ssid")!
                    ssidRow.hidden = Condition(booleanLiteral: !boolVal)
                    ssidRow.evaluateHidden()
                    let internalURLRow: URLRow = self.form.rowBy(tag: "internalBaseURL")!
                    internalURLRow.hidden = Condition(booleanLiteral: !boolVal)
                    internalURLRow.evaluateHidden()
                    let connectRow: ButtonRow = self.form.rowBy(tag: "connect")!
                    connectRow.evaluateHidden()
                    connectRow.updateCell()
                    let externalURLRow: URLRow = self.form.rowBy(tag: "baseURL")!
                    if boolVal == true {
                        externalURLRow.title = L10n.Settings.ConnectionSection.ExternalBaseUrl.title
                    } else {
                        externalURLRow.title = L10n.Settings.ConnectionSection.BaseUrl.title
                    }
                    externalURLRow.updateCell()
                    self.tableView.reloadData()
                }
            }

            <<< LabelRow("ssid") {
                $0.title = L10n.Settings.ConnectionSection.NetworkName.title
                $0.value = L10n.ClientEvents.EventType.unknown
                $0.hidden = Condition(booleanLiteral: !self.internalBaseURLEnabled)
                if let ssid = self.internalBaseURLSSID {
                    $0.value = ssid
                } else if let ssid = ConnectionInfo.currentSSID() {
                    $0.value = ssid
                }
                self.internalBaseURLSSID = $0.value
            }

            <<< URLRow("internalBaseURL") {
                $0.title = L10n.Settings.ConnectionSection.InternalBaseUrl.title
                $0.value = self.internalBaseURL
                $0.placeholder = "http://hassio.local:8123"
                $0.hidden = Condition(booleanLiteral: !self.internalBaseURLEnabled)
            }.onCellHighlightChanged({ (_, row) in
                if row.isHighlighted == false {
                    if let url = row.value {
                        let cleanUrl = self.cleanBaseURL(baseUrl: url)
                        if !cleanUrl.hasValidScheme {
                            let title = L10n.Settings.ConnectionSection.InvalidUrlSchemeNotification.title
                            let message = L10n.Settings.ConnectionSection.InvalidUrlSchemeNotification.message
                            let alert = UIAlertController(title: title, message: message,
                                                          preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: L10n.okLabel, style: UIAlertActionStyle.default,
                                                          handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        } else {
                            self.internalBaseURL = cleanUrl.cleanedURL
                        }
                    }
                }
            })

            <<< SwitchRow("basicAuth") {
                $0.title = "Basic authentication"
                $0.value = self.basicAuthEnabled
            }.onChange { row in
                if let boolVal = row.value {
                    print("Setting rows to val", !boolVal)
                    let basicAuthUsername: TextRow = self.form.rowBy(tag: "basicAuthUsername")!
                    basicAuthUsername.hidden = Condition(booleanLiteral: !boolVal)
                    basicAuthUsername.evaluateHidden()
                    let basicAuthPassword: PasswordRow = self.form.rowBy(tag: "basicAuthPassword")!
                    basicAuthPassword.hidden = Condition(booleanLiteral: !boolVal)
                    basicAuthPassword.evaluateHidden()
                    self.tableView.reloadData()
                }
            }

            <<< TextRow("basicAuthUsername") {
                $0.title = L10n.Settings.ConnectionSection.BasicAuth.Username.title
                $0.hidden = Condition(booleanLiteral: !self.basicAuthEnabled)
                $0.value = self.connectionInfo?.basicAuthCredentials?.username ?? ""
                $0.placeholder = L10n.Settings.ConnectionSection.BasicAuth.Username.placeholder
            }.onChange { row in
                self.basicAuthUsername = row.value
            }

            <<< PasswordRow("basicAuthPassword") {
                $0.title = L10n.Settings.ConnectionSection.BasicAuth.Password.title
                $0.value = self.connectionInfo?.basicAuthCredentials?.password ?? ""
                $0.placeholder = L10n.Settings.ConnectionSection.BasicAuth.Password.placeholder
                $0.hidden = Condition(booleanLiteral: !self.basicAuthEnabled)
            }.onChange { row in
                self.basicAuthPassword = row.value
            }.cellUpdate { cell, row in
                if !row.isValid {
                    cell.titleLabel?.textColor = .red
                }
            }

            <<< ButtonRow("connect") {
                    $0.title = L10n.Settings.ConnectionSection.SaveButton.title
                }.onCellSelection { _, _ in
                    if self.form.validate().count == 0 {
                        self.validateConnection()
                    }
                }
            +++ Section(header: L10n.Settings.StatusSection.header, footer: "") {
                $0.tag = "status"
                $0.hidden = Condition(booleanLiteral: !self.configured)
            }
            <<< LabelRow("locationName") {
                $0.title = L10n.Settings.StatusSection.LocationNameRow.title
                $0.value = L10n.Settings.StatusSection.LocationNameRow.placeholder
                if let locationName = prefs.string(forKey: "location_name") {
                    $0.value = locationName
                }
            }
            <<< LabelRow("version") {
                $0.title = L10n.Settings.StatusSection.VersionRow.title
                $0.value = L10n.Settings.StatusSection.VersionRow.placeholder
                if let version = prefs.string(forKey: "version") {
                    $0.value = version
                }
            }
            <<< LabelRow("iosComponentLoaded") {
                $0.title = L10n.Settings.StatusSection.IosComponentLoadedRow.title
                $0.value = api?.iosComponentLoaded ?? false ? "✔️" : "✖️"
            }
            <<< LabelRow("deviceTrackerComponentLoaded") {
                $0.title = L10n.Settings.StatusSection.DeviceTrackerComponentLoadedRow.title
                $0.value = api?.deviceTrackerComponentLoaded ?? false ? "✔️" : "✖️"
                $0.hidden = Condition(booleanLiteral: !(Current.settingsStore.locationEnabled))
            }
            <<< LabelRow("notifyPlatformLoaded") {
                $0.title = L10n.Settings.StatusSection.NotifyPlatformLoadedRow.title
                $0.value = api?.iosNotifyPlatformLoaded ?? false ? "✔️" : "✖️"
                $0.hidden = Condition(booleanLiteral: !(api?.notificationsEnabled ?? false))
            }

            +++ Section(header: "", footer: L10n.Settings.DeviceIdSection.footer)
            <<< TextRow("deviceId") {
                $0.title = L10n.Settings.DeviceIdSection.DeviceIdRow.title
                if let deviceID = self.deviceID {
                    $0.value = deviceID
                } else {
                    $0.value = Current.settingsStore.deviceID
                }
                $0.cell.textField.autocapitalizationType = .none
                }.cellUpdate { _, row in
                    if row.isHighlighted == false {
                        if let deviceId = row.value {
                            Current.settingsStore.deviceID = deviceId
                            self.deviceID = deviceId
                            keychain["deviceID"] = deviceId
                        }
                    }
            }
            +++ Section {
                $0.tag = "details"
                $0.hidden = Condition(booleanLiteral: !self.configured)
            }
            <<< ButtonRow("generalSettings") {
                $0.hidden = Condition(booleanLiteral: !OpenInChromeController().isChromeInstalled())
                $0.title = L10n.Settings.GeneralSettingsButton.title
                $0.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                    let view = SettingsDetailViewController()
                    view.detailGroup = "general"
                    return view
                    }, onDismiss: { vc in
                        _ = vc.navigationController?.popViewController(animated: true)
                })
            }

            <<< ButtonRow("enableLocation") {
                $0.title = L10n.Settings.DetailsSection.EnableLocationRow.title
                $0.hidden = Condition(booleanLiteral: Current.settingsStore.locationEnabled)
            }.onCellSelection { _, _ in
                self.authLocationManager.requestAlwaysAuthorization()
            }

            <<< ButtonRow("locationSettings") {
                $0.title = L10n.Settings.DetailsSection.LocationSettingsRow.title
                $0.hidden = Condition(booleanLiteral: !(Current.settingsStore.locationEnabled))
                $0.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                    let view = SettingsDetailViewController()
                    view.detailGroup = "location"
                    return view
                    }, onDismiss: { vc in
                        _ = vc.navigationController?.popViewController(animated: true)
                })
            }

            <<< ButtonRow("enableNotifications") {
                $0.title = L10n.Settings.DetailsSection.EnableNotificationRow.title
                $0.hidden = Condition(booleanLiteral: api?.notificationsEnabled ?? false)
                }.onCellSelection { _, row in
                    if #available(iOS 10, *) {
                        let center = UNUserNotificationCenter.current()
                        center.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
                            if error != nil {
                                let title = L10n.Settings.ConnectionSection.ErrorEnablingNotifications.title
                                let message = L10n.Settings.ConnectionSection.ErrorEnablingNotifications.message
                                let alert = UIAlertController(title: title,
                                                              message: message,
                                                              preferredStyle: UIAlertControllerStyle.alert)
                                alert.addAction(UIAlertAction(title: L10n.okLabel, style: UIAlertActionStyle.default,
                                                              handler: nil))
                                self.present(alert, animated: true, completion: nil)
                            } else {
                                print("Notifications Permissions finished!", granted)
                                prefs.setValue(granted, forKey: "notificationsEnabled")
                                prefs.synchronize()
                                if granted, let api = api {
                                    api.setupPush()
                                    DispatchQueue.main.async(execute: {
                                        row.hidden = true
                                        row.updateCell()
                                        row.evaluateHidden()
                                        let settingsRow: ButtonRow = self.form.rowBy(tag: "notificationSettings")!
                                        settingsRow.hidden = false
                                        settingsRow.evaluateHidden()
                                        let loadedRow: LabelRow = self.form.rowBy(tag: "notifyPlatformLoaded")!
                                        loadedRow.hidden = false
                                        loadedRow.evaluateHidden()
                                        self.tableView.reloadData()
                                    })
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async(execute: {
                            let setting = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
                            UIApplication.shared.registerUserNotificationSettings(setting)
                            UIApplication.shared.registerForRemoteNotifications()
                        })
                    }
            }

            <<< ButtonRow("notificationSettings") {
                $0.title = L10n.Settings.DetailsSection.NotificationSettingsRow.title
                $0.hidden = Condition(booleanLiteral: !(api?.notificationsEnabled ?? false))
                $0.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                    let view = SettingsDetailViewController()
                    view.detailGroup = "notifications"
                    return view
                    }, onDismiss: { vc in
                        _ = vc.navigationController?.popViewController(animated: true)
                })
            }

            <<< ButtonRow("eventLog") {
                $0.title = L10n.Settings.EventLog.title
                let controllerProvider = ControllerProvider.storyBoard(storyboardId: "clientEventsList",
                                                                       storyboardName: "ClientEvents",
                                                                       bundle: Bundle.main)
                $0.presentationMode = .show(controllerProvider: controllerProvider, onDismiss: { vc in
                    _ = vc.navigationController?.popViewController(animated: true)
                })
            }

            +++ Section {
                $0.tag = "reset"
                $0.hidden = Condition(booleanLiteral: !self.configured)
            }
            <<< ButtonRow("resetApp") {
                $0.title = L10n.Settings.ResetSection.ResetRow.title
                }.cellUpdate { cell, _ in
                    cell.textLabel?.textColor = .red
                }.onCellSelection { _, row in
                    let alert = UIAlertController(title: L10n.Settings.ResetSection.ResetAlert.title,
                                                  message: L10n.Settings.ResetSection.ResetAlert.message,
                                                  preferredStyle: UIAlertControllerStyle.alert)

                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

                    alert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { (_) in
                        row.hidden = true
                        row.evaluateHidden()
                        self.ResetApp()
                    }))

                    self.present(alert, animated: true, completion: nil)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @objc func HomeAssistantDiscovered(_ notification: Notification) {
        let discoverySection: Section = self.form.sectionBy(tag: "discoveredInstances")!
        discoverySection.hidden = false
        discoverySection.evaluateHidden()
        if let userInfo = (notification as Notification).userInfo as? [String: Any] {
            let discoveryInfo = DiscoveryInfoResponse(JSON: userInfo)!
            let needsPass = discoveryInfo.RequiresPassword ? " - "+L10n.Settings.DiscoverySection.requiresPassword : ""
            var url = "\(discoveryInfo.BaseURL!.host!)"
            if let port = discoveryInfo.BaseURL!.port {
                url = "\(discoveryInfo.BaseURL!.host!):\(port)"
            }
            // swiftlint:disable:next line_length
            let detailTextLabel = "\(url) - \(discoveryInfo.Version) - \(discoveryInfo.BaseURL!.scheme!.uppercased()) \(needsPass)"
            if self.form.rowBy(tag: discoveryInfo.LocationName) == nil {
                discoverySection
                    <<< ButtonRow(discoveryInfo.LocationName) {
                            $0.title = discoveryInfo.LocationName
                            $0.cellStyle = UITableViewCellStyle.subtitle
                        }.cellUpdate { cell, _ in
                            cell.textLabel?.textColor = .black
                            cell.detailTextLabel?.text = detailTextLabel
                        }.onCellSelection({ _, _ in
                            self.baseURL = discoveryInfo.BaseURL
                            let urlRow: URLRow = self.form.rowBy(tag: "baseURL")!
                            urlRow.value = discoveryInfo.BaseURL
                            urlRow.updateCell()
                            let apiPasswordRow: PasswordRow = self.form.rowBy(tag: "apiPassword")!
                            apiPasswordRow.value = ""
                            apiPasswordRow.hidden = Condition(booleanLiteral: !discoveryInfo.RequiresPassword)
                            apiPasswordRow.evaluateHidden()
                            if discoveryInfo.RequiresPassword {
                                apiPasswordRow.add(rule: RuleRequired())
                            } else {
                                apiPasswordRow.removeAllRules()
                            }
                            self.tableView?.reloadData()
                        })
                self.tableView?.reloadData()
            } else {
                if let readdedRow: ButtonRow = self.form.rowBy(tag: discoveryInfo.LocationName) {
                    readdedRow.hidden = false
                    readdedRow.updateCell()
                    readdedRow.evaluateHidden()
                    self.tableView?.reloadData()
                }
            }
        }
        self.tableView.reloadData()
    }

    @objc func HomeAssistantUndiscovered(_ notification: Notification) {
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
        self.tableView.reloadData()
    }

    @objc func Connected(_ notification: Notification) {
        let iosComponentLoadedRow: LabelRow = self.form.rowBy(tag: "iosComponentLoaded")!
        let api = HomeAssistantAPI.authenticatedAPI()
        iosComponentLoadedRow.value = api?.iosComponentLoaded ?? false ? "✔️" : "✖️"
        iosComponentLoadedRow.updateCell()
        let deviceTrackerComponentLoadedRow: LabelRow = self.form.rowBy(tag: "deviceTrackerComponentLoaded")!
        deviceTrackerComponentLoadedRow.value = api?.deviceTrackerComponentLoaded ?? false ? "✔️" : "✖️"
        deviceTrackerComponentLoadedRow.updateCell()
        let notifyPlatformLoadedRow: LabelRow = self.form.rowBy(tag: "notifyPlatformLoaded")!
        notifyPlatformLoadedRow.value = api?.iosNotifyPlatformLoaded ?? false ? "✔️" : "✖️"
        notifyPlatformLoadedRow.updateCell()
    }

    func ResetApp() {
        print("Resetting app!")
        resetStores()
        let bundleId = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
        UserDefaults.standard.synchronize()
        prefs.removePersistentDomain(forName: bundleId)
        prefs.synchronize()
        let urlRow: URLRow = self.form.rowBy(tag: "baseURL")!
        urlRow.value = nil
        urlRow.updateCell()
        let apiPasswordRow: PasswordRow = self.form.rowBy(tag: "apiPassword")!
        apiPasswordRow.value = ""
        apiPasswordRow.updateCell()
        let statusSection: Section = self.form.sectionBy(tag: "status")!
        statusSection.hidden = true
        statusSection.evaluateHidden()
        let detailsSection: Section = self.form.sectionBy(tag: "details")!
        detailsSection.hidden = true
        detailsSection.evaluateHidden()
        self.tableView.reloadData()
    }

    /// Grab the connection info from fields in the UI.
    private func connectionInfoFromUI() -> ConnectionInfo? {
        if let baseURL = self.baseURL {
            let credentials: ConnectionInfo.BasicAuthCredentials?
            if let username = self.basicAuthUsername, let password = self.basicAuthPassword {
                credentials = ConnectionInfo.BasicAuthCredentials(username: username, password: password)
            } else {
                credentials = nil
            }

            let connectionInfo = ConnectionInfo(baseURL: baseURL,
                                                internalBaseURL: self.internalBaseURL,
                                                internalSSID: self.internalBaseURLSSID,
                                                basicAuthCredentials: credentials)
            return connectionInfo
        }

        return nil
    }

    private func handleConnectionError(_ error: (Error)) {
        print("Connection error!", error)
        var errorMessage = error.localizedDescription
        if let error = error as? AFError {
            if error.responseCode == 401 {
                errorMessage = L10n.Settings.ConnectionError.Forbidden.message
            }
        }
        let title = L10n.Settings.ConnectionErrorNotification.title
        let message = L10n.Settings.ConnectionErrorNotification.message(errorMessage)
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: L10n.okLabel,
                                      style: UIAlertActionStyle.default,
                                      handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    /// Attempt to connect to the server with the supplied credentials. If it succeeds, save those
    /// credentials and update the UI
    private func validateConnection() {
        let keychain = Keychain(service: "io.robbie.homeassistant")

        guard let connectionInfo = self.connectionInfoFromUI() else {
            let errMsg = L10n.Settings.ConnectionError.InvalidUrl.message
            let alert = UIAlertController(title: L10n.Settings.ConnectionError.InvalidUrl.title,
                                          message: errMsg,
                                          preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: L10n.okLabel,
                                          style: UIAlertActionStyle.default,
                                          handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }

        if !self.useLegacyAuth {
            let tokenManager = TokenManager(baseURL: connectionInfo.activeURL, tokenInfo: nil)
            _ = firstly {
                self.authenticationController.authenticateWithBrowser(at: connectionInfo.activeURL)
                }.then { (code: String) -> Promise<String> in
                    return tokenManager.initialTokenWithCode(code)
                }.then { _ -> Promise<ConfigResponse> in
                    // At this point we are authenticated with modern auth. Clear legacy password.
                    keychain["apiPassword"] = nil
                    Current.settingsStore.connectionInfo = connectionInfo
                    guard let tokenInfo = Current.settingsStore.tokenInfo else {
                        throw SettingsError.configurationFailed
                    }

                    let api = HomeAssistantAPI(connectionInfo: connectionInfo,
                                               authenticationMethod: .modern(tokenInfo: tokenInfo))
                    return api.Connect()
                }.done { config in
                    self.configureUIWith(configResponse: config)
                }.catch { error in
                    self.handleConnectionError(error)
            }
        } else {
            let api = HomeAssistantAPI(connectionInfo: connectionInfo,
                                       authenticationMethod: .legacy(apiPassword: self.password))
            api.Connect().done { config in
                /// Connected with legacy auth. Store credentials.
                Current.settingsStore.connectionInfo = connectionInfo
                if let password = self.password {
                    keychain["apiPassword"] = password
                }

                self.configureUIWith(configResponse: config)
                }.catch { error in
                    self.handleConnectionError(error)
            }
        }

    }

    private func configureDiscoveryObservers() {
        let queue = DispatchQueue(label: "io.robbie.homeassistant", attributes: [])
        queue.async { () -> Void in
            self.discovery.stopDiscovery()
            self.discovery.stopPublish()

            self.discovery.startDiscovery()
            self.discovery.startPublish()
        }

        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(SettingsViewController.HomeAssistantDiscovered(_:)),
                           name: NSNotification.Name(rawValue: "homeassistant.discovered"),
                           object: nil)

        center.addObserver(self,
                           selector: #selector(SettingsViewController.HomeAssistantUndiscovered(_:)),
                           name: NSNotification.Name(rawValue: "homeassistant.undiscovered"),
                           object: nil)

        center.addObserver(self,
                           selector: #selector(SettingsViewController.Connected(_:)),
                           name: NSNotification.Name(rawValue: "connected"),
                           object: nil)
    }
    private func configureUIWith(configResponse config: ConfigResponse) {
        print("Connected!")
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
        let closeSelector = #selector(SettingsViewController.closeSettings(_:))
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self,
                                         action: closeSelector)
        self.navigationItem.setRightBarButton(doneButton, animated: true)
        self.tableView.reloadData()
        self.delegate?.userReconnected()
    }

    @objc func openAbout(_ sender: UIButton) {
        let aboutView = AboutViewController()

        let navController = UINavigationController(rootViewController: aboutView)
        self.show(navController, sender: nil)
        //        self.present(navController, animated: true, completion: nil)
    }

    @objc func closeSettings(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways {
            Current.settingsStore.locationEnabled = true
            let enableLocationRow: ButtonRow = self.form.rowBy(tag: "enableLocation")!
            enableLocationRow.hidden = true
            enableLocationRow.updateCell()
            enableLocationRow.evaluateHidden()
            let locationSettingsRow: ButtonRow = self.form.rowBy(tag: "locationSettings")!
            locationSettingsRow.hidden = false
            locationSettingsRow.updateCell()
            locationSettingsRow.evaluateHidden()
            let deviceTrackerComponentLoadedRow: LabelRow = self.form.rowBy(
                tag: "deviceTrackerComponentLoaded")!
            deviceTrackerComponentLoadedRow.hidden = false
            deviceTrackerComponentLoadedRow.evaluateHidden()
            deviceTrackerComponentLoadedRow.updateCell()
            self.tableView.reloadData()
            if prefs.bool(forKey: "locationUpdateOnZone") == false {
                HomeAssistantAPI.authenticatedAPI()?.regionManager.syncMonitoredRegions()
            }
//            _ = HomeAssistantAPI.sharedInstance.getAndSendLocation(trigger: .Manual)
        }
    }

    func cleanBaseURL(baseUrl: URL) -> (hasValidScheme: Bool, cleanedURL: URL) {
        if (baseUrl.absoluteString.hasPrefix("http://") || baseUrl.absoluteString.hasPrefix("https://")) == false {
            return (false, baseUrl)
        }
        var urlComponents = URLComponents()
        urlComponents.scheme = baseUrl.scheme
        urlComponents.host = baseUrl.host
        urlComponents.port = baseUrl.port
        //        if urlComponents.port == nil {
        //            urlComponents.port = (baseUrl.scheme == "http") ? 80 : 443
        //        }
        return (true, urlComponents.url!)
    }
}

protocol ConnectionInfoChangedDelegate: class {
    func userReconnected()
}
