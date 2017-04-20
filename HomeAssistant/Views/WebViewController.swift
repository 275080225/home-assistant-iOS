//
//  WebViewController.swift
//  HomeAssistant
//
//  Created by Robert Trencheny on 4/10/17.
//  Copyright © 2017 Robbie Trencheny. All rights reserved.
//

import UIKit
import WebKit
import MBProgressHUD
import KeychainAccess
import PromiseKit

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    var webView: WKWebView!
    let keychain = Keychain(service: "io.robbie.homeassistant", accessGroup: "UTQFCBPQRF.io.robbie.HomeAssistant")

    override func loadView() {
        let config = WKWebViewConfiguration()
        if let apiPass = keychain["apiPassword"] {
            let scriptStr = "window.hassConnection = createHassConnection(\"\(apiPass)\");"
            let script = WKUserScript(source: scriptStr, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            let userContentController = WKUserContentController()
            userContentController.addUserScript(script)
            config.userContentController = userContentController
        }
        webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view = webView
    }

    // swiftlint:disable:next function_body_length
    override func viewDidLoad() {
        super.viewDidLoad()

        let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        if let baseURL = keychain["baseURL"], let apiPass = keychain["apiPassword"] {
            firstly {
                HomeAssistantAPI.sharedInstance.Setup(baseURL: baseURL, password: apiPass,
                                                      deviceID: keychain["deviceID"])
                }.then {_ in
                    HomeAssistantAPI.sharedInstance.Connect()
                }.then { _ -> Void in
                    if HomeAssistantAPI.sharedInstance.notificationsEnabled {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    print("Connected!")
                    hud.hide(animated: true)
                    let myURL = URL(string: HomeAssistantAPI.sharedInstance.baseURL)
                    let myRequest = URLRequest(url: myURL!)
                    self.webView.load(myRequest)
                    return
                }.catch {err -> Void in
                    print("ERROR on connect!!!", err)
                    hud.hide(animated: true)
                    let settingsView = SettingsViewController()
                    settingsView.showErrorConnectingMessage = true
                    settingsView.showErrorConnectingMessageError = err
                    settingsView.doneButton = true
                    let navController = UINavigationController(rootViewController: settingsView)
                    self.present(navController, animated: true, completion: nil)
            }
        } else {
            let settingsView = SettingsViewController()
            settingsView.doneButton = true
            let navController = UINavigationController(rootViewController: settingsView)
            self.present(navController, animated: true, completion: {
                hud.hide(animated: true)
            })
        }

        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    override func viewDidAppear(_ animated: Bool) {
        var toolbarItems: [UIBarButtonItem] = []

        let tabBarIconColor = Entity().DefaultEntityUIColor

        if HomeAssistantAPI.sharedInstance.locationEnabled {

            let uploadIcon = getIconForIdentifier("mdi:upload",
                                                  iconWidth: 30,
                                                  iconHeight: 30,
                                                  color: tabBarIconColor)

            toolbarItems.append(UIBarButtonItem(image: uploadIcon,
                                                style: .plain,
                                                target: self,
                                                action: #selector(sendCurrentLocation(_:))
                )
            )

            let mapIcon = getIconForIdentifier("mdi:map",
                                               iconWidth: 30,
                                               iconHeight: 30,
                                               color: tabBarIconColor)

            toolbarItems.append(UIBarButtonItem(image: mapIcon,
                                                style: .plain,
                                                target: self,
                                                action: #selector(openMapView(_:))))
        }

        toolbarItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

        let refreshIcon = getIconForIdentifier("mdi:reload", iconWidth: 30, iconHeight: 30, color: tabBarIconColor)

        toolbarItems.append(UIBarButtonItem(image: refreshIcon,
                                            style: .plain,
                                            target: self,
                                            action: #selector(refreshWebView(_:))))

        let settingsIcon = getIconForIdentifier("mdi:settings", iconWidth: 30, iconHeight: 30, color: tabBarIconColor)

        toolbarItems.append(UIBarButtonItem(image: settingsIcon,
                                            style: .plain,
                                            target: self,
                                            action: #selector(openSettingsView(_:))))

        self.setToolbarItems(toolbarItems, animated: false)

        if HomeAssistantAPI.sharedInstance.URLSet {
            let myURL = URL(string: HomeAssistantAPI.sharedInstance.baseURL)
            let myRequest = URLRequest(url: myURL!)
            self.webView.load(myRequest)
        }
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            openURLInBrowser(urlToOpen: navigationAction.request.url!)
        }
        return nil
    }

    func refreshWebView(_ sender: UIButton) {
        self.webView.reload()
    }

    func openSettingsView(_ sender: UIButton) {
        let settingsView = SettingsViewController()
        settingsView.doneButton = true
        settingsView.hidesBottomBarWhenPushed = true

        let navController = UINavigationController(rootViewController: settingsView)
        self.present(navController, animated: true, completion: nil)
    }

    func openMapView(_ sender: UIButton) {
        let devicesMapView = DevicesMapViewController()

        let navController = UINavigationController(rootViewController: devicesMapView)
        self.present(navController, animated: true, completion: nil)
    }

    func sendCurrentLocation(_ sender: UIButton) {
        HomeAssistantAPI.sharedInstance.sendOneshotLocation().then { _ -> Void in
            let alert = UIAlertController(title: L10n.ManualLocationUpdateNotification.title,
                                          message: L10n.ManualLocationUpdateNotification.message,
                                          preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: L10n.okLabel, style: UIAlertActionStyle.default, handler: nil))
            self.present(alert, animated: true, completion: nil)
            }.catch {error in
                let nserror = error as NSError
                let message = L10n.ManualLocationUpdateFailedNotification.message(nserror.localizedDescription)
                let alert = UIAlertController(title: L10n.ManualLocationUpdateFailedNotification.title,
                                              message: message,
                                              preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: L10n.okLabel, style: UIAlertActionStyle.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
        }
    }

}
