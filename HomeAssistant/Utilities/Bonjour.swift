//
//  Bonjur.swift
//  HomeAssistant
//
//  Created by Stephan Vanterpool on 8/24/18.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import DeviceKit
import Foundation
import Shared

class BonjourDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    var resolving = [NetService]()
    var resolvingDict = [String: NetService]()

    // Browser methods

    func netServiceBrowser(_ netServiceBrowser: NetServiceBrowser,
                           didFind netService: NetService,
                           moreComing moreServicesComing: Bool) {
        Current.Log.verbose("BonjourDelegate.Browser.didFindService")
        netService.delegate = self
        resolvingDict[netService.name] = netService
        netService.resolve(withTimeout: 0.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        Current.Log.verbose("BonjourDelegate.Browser.netServiceDidResolveAddress")
        if let txtRecord = sender.txtRecordData() {
            let serviceDict = NetService.dictionary(fromTXTRecord: txtRecord)
            let discoveryInfo = DiscoveryInfoFromDict(locationName: sender.name, netServiceDictionary: serviceDict)
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "homeassistant.discovered"),
                                            object: nil,
                                            userInfo: discoveryInfo.toJSON())
        }
    }

    func netServiceBrowser(_ netServiceBrowser: NetServiceBrowser,
                           didRemove netService: NetService,
                           moreComing moreServicesComing: Bool) {
        Current.Log.verbose("BonjourDelegate.Browser.didRemoveService")
        let discoveryInfo: [NSObject: Any] = ["name" as NSObject: netService.name]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "homeassistant.undiscovered"),
                                        object: nil,
                                        userInfo: discoveryInfo)
        resolvingDict.removeValue(forKey: netService.name)
    }

    private func DiscoveryInfoFromDict(locationName: String,
                                       netServiceDictionary: [String: Data]) -> DiscoveredHomeAssistant {
        var outputDict: [String: Any] = [:]
        for (key, value) in netServiceDictionary {
            outputDict[key] = String(data: value, encoding: .utf8)
            if outputDict[key] as? String == "true" || outputDict[key] as? String == "false" {
                if let stringedKey = outputDict[key] as? String {
                    outputDict[key] = Bool(stringedKey)
                }
            }
        }
        outputDict["location_name"] = locationName
        if let baseURL = outputDict["base_url"] as? String {
            if baseURL.hasSuffix("/") {
                outputDict["base_url"] = baseURL[..<baseURL.index(before: baseURL.endIndex)]
            }
        }
        return DiscoveredHomeAssistant(JSON: outputDict)!
    }
}

class Bonjour {
    var nsb: NetServiceBrowser
    var nsp: NetService
    var nsdel: BonjourDelegate?

    public var browserIsRunning: Bool = false
    public var publishIsRunning: Bool = false

    init() {
        let device = Device.current
        self.nsb = NetServiceBrowser()
        self.nsp = NetService(domain: "local", type: "_hass-mobile-app._tcp.", name: device.name ?? "Unknown",
                              port: 65535)
    }

    func buildPublishDict() -> [String: Data] {
        var publishDict: [String: Data] = [:]
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") {
            if let stringedBundleVersion = bundleVersion as? String {
                if let data = stringedBundleVersion.data(using: .utf8) {
                    publishDict["buildNumber"] = data
                }
            }
        }
        if let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") {
            if let stringedVersionNumber = versionNumber as? String {
                if let data = stringedVersionNumber.data(using: .utf8) {
                    publishDict["versionNumber"] = data
                }
            }
        }
        if let permanentID = Constants.PermanentID.data(using: .utf8) {
            publishDict["permanentID"] = permanentID
        }
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            if let data = bundleIdentifier.data(using: .utf8) {
                publishDict["bundleIdentifier"] = data
            }
        }
        return publishDict
    }

    func startDiscovery() {
        self.browserIsRunning = true
        self.nsdel = BonjourDelegate()
        nsb.delegate = nsdel
        nsb.searchForServices(ofType: "_home-assistant._tcp.", inDomain: "local.")
    }

    func stopDiscovery() {
        self.browserIsRunning = false
        nsb.stop()
    }

    func startPublish() {
        //        self.nsdel = BonjourDelegate()
        //        nsp.delegate = nsdel
        self.publishIsRunning = true
        nsp.setTXTRecord(NetService.data(fromTXTRecord: buildPublishDict()))
        nsp.publish()
    }

    func stopPublish() {
        self.publishIsRunning = false
        nsp.stop()
    }

}
