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
import AcknowList
import PromiseKit
import Crashlytics

class SettingsViewController: FormViewController {

    let prefs = NSUserDefaults.standardUserDefaults()
    
    var showErrorConnectingMessage = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        var hideAbout = false
        var hideLowerSave = false
        
        if prefs.boolForKey("emailSet") == false {
            print("This is first launch, let's prompt user for email.")
            let alert = UIAlertController(title: "Welcome", message: "Please enter the email address you used to sign up for the beta program with.", preferredStyle: UIAlertControllerStyle.Alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: emailEntered))
            alert.addTextFieldWithConfigurationHandler({(textField: UITextField!) in
                textField.placeholder = "myawesomeemail@gmail.com"
                textField.keyboardType = .EmailAddress
                self.emailInput = textField
            })
            self.presentViewController(alert, animated: true, completion: nil)
        }
        
        if showErrorConnectingMessage {
            let alert = UIAlertController(title: "Connection error", message: "There was an error connecting to Home Assistant. Please confirm the settings are correct and save to attempt to reconnect.", preferredStyle: UIAlertControllerStyle.Alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: nil))
            self.presentViewController(alert, animated: true, completion: nil)
            hideAbout = true
            hideLowerSave = true
        }
        if prefs.stringForKey("baseURL") == nil {
            hideAbout = true
            hideLowerSave = true
        }
        self.navigationItem.rightBarButtonItem = hideAbout ? UIBarButtonItem(barButtonSystemItem: .Save, target: self, action: #selector(SettingsViewController.saveSettingsButton(_:))) : UIBarButtonItem(title: "About", style: .Plain, target: self, action: #selector(SettingsViewController.aboutButtonPressed(_:)))
        
        let discovery = Bonjour()
        
        let queue = dispatch_queue_create("io.robbie.homeassistant", nil);
        dispatch_async(queue) { () -> Void in
            NSLog("Attempting to discover Home Assistant instances, also publishing app to Bonjour/mDNS to hopefully have HA load the iOS/ZeroConf components.")
            discovery.stopDiscovery()
            discovery.stopPublish()
            
            discovery.startDiscovery()
            discovery.startPublish()
            
            sleep(60)
            
            NSLog("Stopping Home Assistant discovery")
            discovery.stopDiscovery()
            discovery.stopPublish()
        }

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SettingsViewController.HomeAssistantDiscovered(_:)), name:"homeassistant.discovered", object: nil)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SettingsViewController.HomeAssistantUndiscovered(_:)), name:"homeassistant.undiscovered", object: nil)
        
        form
            +++ Section(header: "Discovered Home Assistants", footer: ""){
                $0.tag = "discoveredInstances"
                $0.hidden = true
            }
        
        form
            +++ Section(header: "Connection information", footer: "URL format should be protocol://hostname_or_ip:portnumber. NO slashes. Only provide a port number if not using 80/443. Examples: http://192.168.1.2:8123, https://demo.home-assistant.io.\r\nIf you do not have an API password set, leave the field blank.")
            <<< URLRow("baseURL") {
                $0.title = "Base URL"
                if let baseURL = prefs.stringForKey("baseURL") {
                    $0.value = NSURL(string: baseURL)
                }
                $0.placeholder = "https://homeassistant.myhouse.com"
            }.onChange({ _ in
                let apiPasswordRow: PasswordRow = self.form.rowByTag("apiPassword")!
                apiPasswordRow.value = ""
                apiPasswordRow.disabled = false
                apiPasswordRow.evaluateDisabled()
            })
            <<< PasswordRow("apiPassword") {
                $0.title = "API Password"
                if let apiPass = prefs.stringForKey("apiPassword") {
                    $0.value = apiPass
                }
                $0.placeholder = "password"
            }
            +++ Section(header: "Settings", footer: ""){
                $0.hidden = Condition(booleanLiteral: showErrorConnectingMessage)
            }
            <<< TextRow("deviceId") {
                let cleanModel = UIDevice.currentDevice().model.lowercaseString.stringByReplacingOccurrencesOfString(" ", withString: "")
                $0.placeholder = cleanModel
                $0.title = "Device ID (location tracking)"
                if let deviceId = prefs.stringForKey("deviceId") {
                    $0.value = deviceId
                } else {
                    $0.value = cleanModel
                }
                $0.cell.textField.autocapitalizationType = .None
            }
            <<< SwitchRow("allowAllGroups") {
                $0.title = "Show all groups"
                $0.value = prefs.boolForKey("allowAllGroups")
            }
            <<< ButtonRow() {
                $0.title = "Save"
                $0.hidden = Condition(booleanLiteral: hideLowerSave)
            }.onCellSelection {_,_ in
                self.saveSettings()
            }
        
            if showErrorConnectingMessage == false {
                if let endpointArn = prefs.stringForKey("endpointARN") {
                    form
                        +++ Section(header: "Push information", footer: "")
                        <<< TextAreaRow() {
                            $0.placeholder = "EndpointArn"
                            $0.value = endpointArn.componentsSeparatedByString("/").last
                            $0.disabled = true
                            $0.textAreaHeight = TextAreaHeight.Dynamic(initialTextViewHeight: 40)
                    }
                }
            }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    func aboutButtonPressed(sender: UIButton) {
        let viewController = AcknowListViewController()
        if let navigationController = self.navigationController {
            navigationController.pushViewController(viewController, animated: true)
        }
    }

    func HomeAssistantDiscovered(notification: NSNotification){
        let discoverySection : Section = self.form.sectionByTag("discoveredInstances")!
        discoverySection.hidden = false
        discoverySection.evaluateHidden()
        if let userInfo = notification.userInfo as? [String:AnyObject] {
            let name = userInfo["name"] as! String
            let baseUrl = userInfo["baseUrl"] as! String
            let requiresAPIPassword = userInfo["requires_api_password"] as! Bool
            let useSSL = userInfo["use_ssl"] as! Bool
            let needsPass = requiresAPIPassword ? " - Requires password" : ""
            if self.form.rowByTag(name) == nil {
                discoverySection
                    <<< ButtonRow(name) {
                            $0.title = name
                            $0.cellStyle = UITableViewCellStyle.Subtitle
                        }.cellUpdate { cell, row in
                            cell.textLabel?.textColor = .blackColor()
                            cell.detailTextLabel?.text = baseUrl + " - " + (userInfo["version"] as! String) + " - " + (useSSL ? "HTTPS" : "HTTP") + needsPass
                        }.onCellSelection({ cell, row in
                            let urlRow: URLRow = self.form.rowByTag("baseURL")!
                            urlRow.value = NSURL(string: baseUrl)
                            urlRow.updateCell()
                            let apiPasswordRow: PasswordRow = self.form.rowByTag("apiPassword")!
                            apiPasswordRow.value = ""
                            apiPasswordRow.disabled = Condition(booleanLiteral: !requiresAPIPassword)
                            apiPasswordRow.evaluateDisabled()
                        })
                self.tableView?.reloadData()
            } else {
                if let readdedRow : ButtonRow = self.form.rowByTag(name) {
                    readdedRow.hidden = false
                    readdedRow.updateCell()
                    readdedRow.evaluateHidden()
                }
            }
        }
    }

    func HomeAssistantUndiscovered(notification: NSNotification){
        if let userInfo = notification.userInfo as? [String:AnyObject] {
            let name = userInfo["name"] as! String
            if let removingRow : ButtonRow = self.form.rowByTag(name) {
                removingRow.hidden = true
                removingRow.evaluateHidden()
                removingRow.updateCell()
            }
        }
        let discoverySection : Section = self.form.sectionByTag("discoveredInstances")!
        discoverySection.hidden = Condition(booleanLiteral: (discoverySection.count < 1))
        discoverySection.evaluateHidden()
    }

    
    @IBOutlet var emailInput: UITextField!
    func emailEntered(sender: UIAlertAction) {
        print("Captured email", emailInput.text)
        Crashlytics.sharedInstance().setUserEmail(emailInput.text)
        print("First launch, setting NSUserDefault.")
        prefs.setBool(true, forKey: "emailSet")
    }
    
    func saveSettingsButton(sender: UIButton) {
        saveSettings()
    }
    
    func saveSettings() {
        if let urlRow: URLRow = self.form.rowByTag("baseURL") {
            if let url = urlRow.value {
                self.prefs.setValue(url.absoluteString, forKey: "baseURL")
            }
        }
        if let apiPasswordRow: PasswordRow = self.form.rowByTag("apiPassword") {
            if let password = apiPasswordRow.value {
                self.prefs.setValue(password, forKey: "apiPassword")
            }
        }
        if let deviceIdRow: TextRow = self.form.rowByTag("deviceId") {
            if let deviceId = deviceIdRow.value {
                self.prefs.setValue(deviceId, forKey: "deviceId")
            }
        }
        if let allowAllGroupsRow: SwitchRow = self.form.rowByTag("allowAllGroups") {
            if let allowAllGroups = allowAllGroupsRow.value {
                self.prefs.setBool(allowAllGroups, forKey: "allowAllGroups")
            }
        }
        
        let pscope = PermissionScope()
        
        pscope.addPermission(LocationAlwaysPermission(),
                             message: "We use this to inform\r\nHome Assistant of your device presence.")
        pscope.addPermission(NotificationsPermission(),
                             message: "We use this to let you\r\nsend notifications to your device.")
        pscope.show({finished, results in
            if finished {
                print("Permissions finished, resetting API!")
                self.dismissViewControllerAnimated(true, completion: nil)
                (UIApplication.sharedApplication().delegate as! AppDelegate).initAPI()
            }
        }, cancelled: { (results) -> Void in
            print("Permissions finished, resetting API!")
            self.dismissViewControllerAnimated(true, completion: nil)
            (UIApplication.sharedApplication().delegate as! AppDelegate).initAPI()
        })
    }
    
}

