//
//  HAAPI.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 3/25/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Alamofire
import AlamofireObjectMapper
import PromiseKit
import Crashlytics
import CoreLocation
import CoreMotion
import DeviceKit
import Foundation
import KeychainAccess
import ObjectMapper
import RealmSwift
import UserNotifications
import Intents

private let keychain = Keychain(service: "io.robbie.homeassistant")

// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
public class HomeAssistantAPI {
    public enum APIError: Error {
        case managerNotAvailable
        case invalidResponse
        case cantBuildURL
        case notConfigured
    }

    public enum AuthenticationMethod {
        case legacy(apiPassword: String?)
        case modern(tokenInfo: TokenInfo)
    }

    let prefs = UserDefaults(suiteName: Constants.AppGroupID)!

    public var pushID: String?

    public var loadedComponents = [String]()

    var apiPassword: String?

    private(set) var manager: Alamofire.SessionManager!

    public var oneShotLocationManager: OneShotLocationManager?

    public var cachedEntities: [Entity]?

    public var notificationsEnabled: Bool {
        return self.prefs.bool(forKey: "notificationsEnabled")
    }

    public var iosComponentLoaded: Bool {
        return self.loadedComponents.contains("ios")
    }

    public var deviceTrackerComponentLoaded: Bool {
        return self.loadedComponents.contains("device_tracker")
    }

    public var iosNotifyPlatformLoaded: Bool {
        return self.loadedComponents.contains("notify.ios")
    }

    var enabledPermissions: [String] {
        var permissionsContainer: [String] = []
        if self.notificationsEnabled {
            permissionsContainer.append("notifications")
        }
        if Current.settingsStore.locationEnabled {
            permissionsContainer.append("location")
        }
        return permissionsContainer
    }

    var tokenManager: TokenManager?
    public var connectionInfo: ConnectionInfo

    /// Initialzie an API object with an authenticated tokenManager.
    public init(connectionInfo: ConnectionInfo, authenticationMethod: AuthenticationMethod) {
        self.connectionInfo = connectionInfo

        switch authenticationMethod {
        case .legacy(let apiPassword):
            self.manager = self.configureSessionManager(withPassword: apiPassword)
        case .modern(let tokenInfo):
            // TODO: Take this into account when promoting to the main API. The one in Current is separate, which is bad.
            self.tokenManager = TokenManager(connectionInfo: connectionInfo, tokenInfo: tokenInfo)
            let manager = self.configureSessionManager()
            manager.retrier = self.tokenManager
            manager.adapter = self.tokenManager
            self.manager = manager
        }

        let basicAuthKeychain = Keychain(server: self.connectionInfo.baseURL.absoluteString,
                                         protocolType: .https,
                                         authenticationType: .httpBasic)
        self.configureBasicAuthWithKeychain(basicAuthKeychain)

        self.pushID = self.prefs.string(forKey: "pushID")

        UNUserNotificationCenter.current().getNotificationSettings(completionHandler: { (settings) in
            self.prefs.setValue((settings.authorizationStatus == UNAuthorizationStatus.authorized),
                           forKey: "notificationsEnabled")
        })

    }

    /// Configure global state of the app to use our newly validated credentials.
    func confirmAPI() {
        Current.tokenManager = self.tokenManager
    }

    public func Connect() -> Promise<ConfigResponse> {
        return Promise { seal in
            GetConfig().done { config in
                if let components = config.Components {
                    self.loadedComponents = components
                }
                self.prefs.setValue(config.ConfigDirectory, forKey: "config_dir")
                self.prefs.setValue(config.LocationName, forKey: "location_name")
                self.prefs.setValue(config.Latitude, forKey: "latitude")
                self.prefs.setValue(config.Longitude, forKey: "longitude")
                self.prefs.setValue(config.TemperatureUnit, forKey: "temperature_unit")
                self.prefs.setValue(config.LengthUnit, forKey: "length_unit")
                self.prefs.setValue(config.MassUnit, forKey: "mass_unit")
                self.prefs.setValue(config.VolumeUnit, forKey: "volume_unit")
                self.prefs.setValue(config.Timezone, forKey: "time_zone")
                self.prefs.setValue(config.Version, forKey: "version")

                Crashlytics.sharedInstance().setObjectValue(config.Version, forKey: "hass_version")
                Crashlytics.sharedInstance().setObjectValue(self.loadedComponents.joined(separator: ","),
                                                            forKey: "loadedComponents")
                Crashlytics.sharedInstance().setObjectValue(self.enabledPermissions.joined(separator: ","),
                                                            forKey: "allowedPermissions")

                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "connected"),
                                                object: nil,
                                                userInfo: nil)

                _ = self.getManifestJSON().done { manifest in
                    if let themeColor = manifest.ThemeColor {
                        self.prefs.setValue(themeColor, forKey: "themeColor")
                    }
                }

                _ = self.GetStates().done { entities in
                    self.cachedEntities = entities
                    self.storeEntities(entities: entities)
                    if self.loadedComponents.contains("ios") {
                        CLSLogv("iOS component loaded, attempting identify", getVaList([]))
                        _ = self.identifyDevice()
                    }

                    seal.fulfill(config)
                }
            }.catch {error in
                print("Error at launch!", error)
                Crashlytics.sharedInstance().recordError(error)
                seal.reject(error)
            }

        }
    }

    public enum HomeAssistantAPIError: Error {
        case notAuthenticated
        case unknown
    }

    private static var sharedAPI: HomeAssistantAPI?
    public static func authenticatedAPI() -> HomeAssistantAPI? {
        if let api = sharedAPI {
            return api
        }

        guard let connectionInfo = Current.settingsStore.connectionInfo else {
            return nil
        }

        if let tokenInfo = Current.settingsStore.tokenInfo {
            let api = HomeAssistantAPI(connectionInfo: connectionInfo,
                                       authenticationMethod: .modern(tokenInfo: tokenInfo))
            self.sharedAPI = api
        } else {
            let api = HomeAssistantAPI(connectionInfo: connectionInfo,
                                       authenticationMethod: .legacy(apiPassword: keychain["apiPassword"]))
            self.sharedAPI = api
        }

        return self.sharedAPI
    }

    public static var authenticatedAPIPromise: Promise<HomeAssistantAPI> {
        return Promise { seal in
            if let api = self.authenticatedAPI() {
                seal.fulfill(api)
            } else {
                seal.reject(APIError.notConfigured)
            }
        }
    }

    public func getManifestJSON() -> Promise<ManifestJSON> {
        return Promise { seal in
            if let manager = self.manager {
                let queryUrl = self.connectionInfo.activeURL.appendingPathComponent("manifest.json")
                _ = manager.request(queryUrl, method: .get)
                    .validate()
                    .responseObject { (response: DataResponse<ManifestJSON>) in
                        switch response.result {
                        case .success:
                            if let resVal = response.result.value {
                                seal.fulfill(resVal)
                            } else {
                                seal.reject(APIError.invalidResponse)
                            }
                        case .failure(let error):
                            CLSLogv("Error on GetManifestJSON() request: %@",
                                    getVaList([error.localizedDescription]))
                            Crashlytics.sharedInstance().recordError(error)
                            seal.reject(error)
                        }
                }
            } else {
                seal.reject(APIError.managerNotAvailable)
            }
        }
    }

    public func GetStatus() -> Promise<StatusResponse> {
        return self.request(path: "", callingFunctionName: "\(#function)", method: .get)
    }

    public func GetConfig() -> Promise<ConfigResponse> {
        return self.request(path: "config", callingFunctionName: "\(#function)")
    }

    public func GetServices() -> Promise<[ServicesResponse]> {
        return self.request(path: "services", callingFunctionName: "\(#function)")
    }

    public func GetStates() -> Promise<[Entity]> {
        return self.request(path: "states", callingFunctionName: "\(#function)")
    }

    public func GetEntityState(entityId: String) -> Promise<Entity> {
        return self.request(path: "states/\(entityId)", callingFunctionName: "\(#function)")
    }

    public func SetState(entityId: String, state: String) -> Promise<Entity> {
        return self.request(path: "states/\(entityId)", callingFunctionName: "\(#function)", method: .post,
                            parameters: ["state": state], encoding: JSONEncoding.default)
    }

    public func createEvent(eventType: String, eventData: [String: Any]) -> Promise<String> {
        return Promise { seal in
            let queryUrl = self.connectionInfo.activeAPIURL.appendingPathComponent("events/\(eventType)")
            _ = manager.request(queryUrl, method: .post,
                                parameters: eventData, encoding: JSONEncoding.default)
                .validate()
                .responseJSON { response in
                    switch response.result {
                    case .success:
                        if let jsonDict = response.result.value as? [String: String],
                            let msg = jsonDict["message"] {
                            seal.fulfill(msg)
                        }
                    case .failure(let error):
                        CLSLogv("Error when attemping to CreateEvent(): %@",
                                getVaList([error.localizedDescription]))
                        Crashlytics.sharedInstance().recordError(error)
                        seal.reject(error)
                    }
            }
        }
    }

    public func downloadDataAt(url: URL) -> Promise<Data> {
        return Promise { seal in
            self.manager.download(url).responseData { downloadResponse in
                switch downloadResponse.result {
                case .success(let data):
                    seal.fulfill(data)
                case .failure(let error):
                    seal.reject(error)
                }
            }
        }
    }

    public func callService(domain: String, service: String, serviceData: [String: Any],
                            shouldLog: Bool = true)
        -> Promise<[Entity]> {
        return Promise { seal in
            let queryUrl =
                self.connectionInfo.activeAPIURL.appendingPathComponent("services/\(domain)/\(service)")
            _ = manager.request(queryUrl, method: .post,
                                parameters: serviceData, encoding: JSONEncoding.default)
                .validate()
                .responseArray { (response: DataResponse<[Entity]>) in
                    switch response.result {
                    case .success:
                        if let resVal = response.result.value {
                            if shouldLog {
                                let event = ClientEvent(text: "Calling service: \(domain) - \(service)",
                                    type: .serviceCall, payload: serviceData)
                                Current.clientEventStore.addEvent(event)
                            }

                            // Don't want to donate device_tracker.see calls
                            if #available(iOS 12.0, *), service != "see" {
                                let intent = CallServiceIntent()
                                intent.serviceName = domain + "." + service

                                let jsonData = try? JSONSerialization.data(withJSONObject: serviceData, options: [])
                                let jsonString = String(data: jsonData!, encoding: .utf8)

                                intent.serviceData = jsonString
                                let interaction = INInteraction(intent: intent, response: nil)
                                interaction.donate { (error) in
                                    if error != nil {
                                        if let error = error as NSError? {
                                            print("Interaction donation failed: \(error)")
                                        } else {
                                            print("Successfully donated interaction")
                                        }
                                    } else {
                                        print("Donated call service interaction")
                                    }
                                }
                            }

                            seal.fulfill(resVal)
                        } else {
                            seal.reject(APIError.invalidResponse)
                        }
                    case .failure(let error):
                        if let afError = error as? AFError {
                            var errorUserInfo: [String: Any] = [:]
                            if let data = response.data, let utf8Text = String(data: data, encoding: .utf8) {
                                if let errorJSON = utf8Text.dictionary(),
                                    let errMessage = errorJSON["message"] as? String {
                                    errorUserInfo["errorMessage"] = errMessage
                                }
                            }
                            CLSLogv("Error on CallService() request: %@", getVaList([afError.localizedDescription]))
                            Crashlytics.sharedInstance().recordError(afError)
                            let customError = NSError(domain: "io.robbie.HomeAssistant",
                                                      code: afError.responseCode!,
                                                      userInfo: errorUserInfo)
                            seal.reject(customError)
                        } else {
                            CLSLogv("Error on CallService() request: %@", getVaList([error.localizedDescription]))
                            Crashlytics.sharedInstance().recordError(error)
                            seal.reject(error)
                        }
                    }
            }
        }
    }

    public func RenderTemplate(templateStr: String) -> Promise<String> {
        return Promise { seal in
            let queryUrl = self.connectionInfo.activeAPIURL.appendingPathComponent("template")
            _ = manager.request(queryUrl, method: .post,
                                parameters: ["template":templateStr], encoding: JSONEncoding.default)
                .validate()
                .responseString { response in
                    switch response.result {
                    case .success:
                        if let strResponse = response.result.value {
                            seal.fulfill(strResponse)
                        }
                    case .failure(let error):
                        CLSLogv("Error when attemping to RenderTemplate(): %@",
                                getVaList([error.localizedDescription]))
                        Crashlytics.sharedInstance().recordError(error)
                        seal.reject(error)
                    }
            }
        }
    }

    public func getDiscoveryInfo(baseUrl: URL) -> Promise<DiscoveryInfoResponse> {
        return self.request(path: "discover_info", callingFunctionName: "\(#function)")
    }

    public func identifyDevice() -> Promise<String> {
        return self.request(path: "ios/identify", callingFunctionName: "\(#function)", method: .post,
                     parameters: buildIdentifyDict(), encoding: JSONEncoding.default)
    }

    public func removeDevice() -> Promise<String> {
        return self.request(path: "ios/identify", callingFunctionName: "\(#function)", method: .delete,
                            parameters: buildRemovalDict(), encoding: JSONEncoding.default)
    }

    public func registerDeviceForPush(deviceToken: String) -> Promise<PushRegistrationResponse> {
        let queryUrl = "https://ios-push.home-assistant.io/registrations"
        return Promise { seal in
            Alamofire.request(queryUrl,
                              method: .post,
                              parameters: buildPushRegistrationDict(deviceToken: deviceToken),
                              encoding: JSONEncoding.default
                ).validate().responseObject {(response: DataResponse<PushRegistrationResponse>) in
                    switch response.result {
                    case .success:
                        if let json = response.result.value {
                            seal.fulfill(json)
                        } else {
                            let retErr = NSError(domain: "io.robbie.HomeAssistant",
                                                 code: 404,
                                                 userInfo: ["message": "json was nil!"])
                            CLSLogv("Error when attemping to registerDeviceForPush(), json was nil!: %@",
                                    getVaList([retErr.localizedDescription]))
                            Crashlytics.sharedInstance().recordError(retErr)
                            seal.reject(retErr)
                        }
                    case .failure(let error):
                        CLSLogv("Error when attemping to registerDeviceForPush(): %@",
                                getVaList([error.localizedDescription]))
                        Crashlytics.sharedInstance().recordError(error)
                        seal.reject(error)
                    }
            }
        }
    }

    public func turnOn(entityId: String) -> Promise<[Entity]> {
        return callService(domain: "homeassistant", service: "turn_on", serviceData: ["entity_id": entityId])
    }

    public func turnOnEntity(entity: Entity) -> Promise<[Entity]> {
        return callService(domain: "homeassistant", service: "turn_on", serviceData: ["entity_id": entity.ID])
    }

    public func turnOff(entityId: String) -> Promise<[Entity]> {
        return callService(domain: "homeassistant", service: "turn_off", serviceData: ["entity_id": entityId])
    }

    public func turnOffEntity(entity: Entity) -> Promise<[Entity]> {
        return callService(domain: "homeassistant", service: "turn_off",
                           serviceData: ["entity_id": entity.ID])
    }

    public func toggle(entityId: String) -> Promise<[Entity]> {
        return callService(domain: "homeassistant", service: "toggle", serviceData: ["entity_id": entityId])
    }

    public func toggleEntity(entity: Entity) -> Promise<[Entity]> {
        return callService(domain: "homeassistant", service: "toggle", serviceData: ["entity_id": entity.ID])
    }

    public func getPushSettings() -> Promise<PushConfiguration> {
        return self.request(path: "ios/push", callingFunctionName: "\(#function)")
    }

    private func buildIdentifyDict() -> [String: Any] {
        let deviceKitDevice = Device()

        let ident = IdentifyRequest()
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") {
            if let stringedBundleVersion = bundleVersion as? String {
                ident.AppBuildNumber = Int(stringedBundleVersion)
            }
        }
        if let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") {
            if let stringedVersionNumber = versionNumber as? String {
                ident.AppVersionNumber = stringedVersionNumber
            }
        }
        ident.AppBundleIdentifer = Bundle.main.bundleIdentifier
        ident.DeviceID = Current.settingsStore.deviceID
        ident.DeviceLocalizedModel = deviceKitDevice.localizedModel
        ident.DeviceModel = deviceKitDevice.model
        ident.DeviceName = deviceKitDevice.name
        ident.DevicePermanentID = Current.deviceIDProvider()
        ident.DeviceSystemName = deviceKitDevice.systemName
        ident.DeviceSystemVersion = deviceKitDevice.systemVersion
        ident.DeviceType = deviceKitDevice.description
        ident.Permissions = self.enabledPermissions
        ident.PushID = pushID
        ident.PushSounds = Notifications.installedPushNotificationSounds()

        UIDevice.current.isBatteryMonitoringEnabled = true

        switch UIDevice.current.batteryState {
        case .unknown:
            ident.BatteryState = "Unknown"
        case .charging:
            ident.BatteryState = "Charging"
        case .unplugged:
            ident.BatteryState = "Unplugged"
        case .full:
            ident.BatteryState = "Full"
        }

        ident.BatteryLevel = Int(UIDevice.current.batteryLevel*100)
        if ident.BatteryLevel == -100 { // simulator fix
            ident.BatteryLevel = 100
        }

        UIDevice.current.isBatteryMonitoringEnabled = false

        return Mapper().toJSON(ident)
    }

    private func buildPushRegistrationDict(deviceToken: String) -> [String: Any] {
        let deviceKitDevice = Device()

        let ident = PushRegistrationRequest()
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") {
            if let stringedBundleVersion = bundleVersion as? String {
                ident.AppBuildNumber = Int(stringedBundleVersion)
            }
        }
        if let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") {
            if let stringedVersionNumber = versionNumber as? String {
                ident.AppVersionNumber = stringedVersionNumber
            }
        }
        if let isSandboxed = Bundle.main.object(forInfoDictionaryKey: "IS_SANDBOXED") {
            if let stringedisSandboxed = isSandboxed as? String {
                ident.APNSSandbox = (stringedisSandboxed == "true")
            }
        }
        ident.AppBundleIdentifer = Bundle.main.bundleIdentifier
        ident.DeviceID = Current.settingsStore.deviceID
        ident.DeviceName = deviceKitDevice.name
        ident.DevicePermanentID = Current.deviceIDProvider()
        ident.DeviceSystemName = deviceKitDevice.systemName
        ident.DeviceSystemVersion = deviceKitDevice.systemVersion
        ident.DeviceType = deviceKitDevice.description
        ident.DeviceTimezone = (NSTimeZone.local as NSTimeZone).name
        ident.PushSounds = Notifications.installedPushNotificationSounds()
        ident.PushToken = deviceToken
        if let email = self.prefs.string(forKey: "userEmail") {
            ident.UserEmail = email
        }
        if let version = self.prefs.string(forKey: "version") {
            ident.HomeAssistantVersion = version
        }
        if let timeZone = self.prefs.string(forKey: "time_zone") {
            ident.HomeAssistantTimezone = timeZone
        }

        return Mapper().toJSON(ident)
    }

    private func buildRemovalDict() -> [String: Any] {
        let deviceKitDevice = Device()

        let ident = IdentifyRequest()
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") {
            if let stringedBundleVersion = bundleVersion as? String {
                ident.AppBuildNumber = Int(stringedBundleVersion)
            }
        }
        if let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") {
            if let stringedVersionNumber = versionNumber as? String {
                ident.AppVersionNumber = stringedVersionNumber
            }
        }
        ident.AppBundleIdentifer = Bundle.main.bundleIdentifier
        ident.DeviceID = Current.settingsStore.deviceID
        ident.DeviceLocalizedModel = deviceKitDevice.localizedModel
        ident.DeviceModel = deviceKitDevice.model
        ident.DeviceName = deviceKitDevice.name
        ident.DevicePermanentID = Current.deviceIDProvider()
        ident.DeviceSystemName = deviceKitDevice.systemName
        ident.DeviceSystemVersion = deviceKitDevice.systemVersion
        ident.DeviceType = deviceKitDevice.description
        ident.Permissions = self.enabledPermissions
        ident.PushID = pushID
        ident.PushSounds = Notifications.installedPushNotificationSounds()

        return Mapper().toJSON(ident)
    }

    func storeEntities(entities: [Entity]) {
        let storeableComponents = ["zone"]
        let storeableEntities = entities.filter { (entity) -> Bool in
            return storeableComponents.contains(entity.Domain)
        }

        for entity in storeableEntities {
            // print("Storing \(entity.ID)")

            if entity.Domain == "zone", let zone = entity as? Zone {
                let storeableZone = RLMZone()
                storeableZone.ID = zone.ID
                storeableZone.Latitude = zone.Latitude
                storeableZone.Longitude = zone.Longitude
                storeableZone.Radius = zone.Radius
                storeableZone.TrackingEnabled = zone.TrackingEnabled
                storeableZone.BeaconUUID = zone.UUID
                storeableZone.BeaconMajor.value = zone.Major
                storeableZone.BeaconMinor.value = zone.Minor

                let realm = Current.realm()
                // swiftlint:disable:next force_try
                try! realm.write {
                    realm.add(RLMZone(zone: zone), update: true)
                }
            }
        }
    }

    private func configureSessionManager(withPassword password: String? = nil) -> SessionManager {
        var headers = Alamofire.SessionManager.defaultHTTPHeaders
        if let password = password {
            headers["X-HA-Access"] = password
        }

        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = headers
        configuration.timeoutIntervalForRequest = 10 // seconds
        return Alamofire.SessionManager(configuration: configuration)
    }

    private func configureBasicAuthWithKeychain(_ basicAuthKeychain: Keychain) {
        if let basicUsername = basicAuthKeychain["basicAuthUsername"],
            let basicPassword = basicAuthKeychain["basicAuthPassword"] {
            self.manager.delegate.sessionDidReceiveChallenge = { session, challenge in
                print("Received basic auth challenge")

                let authMethod = challenge.protectionSpace.authenticationMethod

                guard authMethod == NSURLAuthenticationMethodDefault ||
                    authMethod == NSURLAuthenticationMethodHTTPBasic ||
                    authMethod == NSURLAuthenticationMethodHTTPDigest else {
                        print("Not handling auth method", authMethod)
                        return (.performDefaultHandling, nil)
                }

                return (.useCredential, URLCredential(user: basicUsername, password: basicPassword,
                                                      persistence: .synchronizable))
            }
        }
    }

    public func submitLocation(updateType: LocationUpdateTrigger,
                               location: CLLocation?,
                               visit: CLVisit?,
                               zone: RLMZone?) -> Promise<Void> {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let payload = DeviceTrackerSee(trigger: updateType, location: location, visit: visit, zone: zone)
        payload.Trigger = updateType

        let isBeaconUpdate = (updateType == .BeaconRegionEnter || updateType == .BeaconRegionExit)

        payload.Battery = UIDevice.current.batteryLevel
        payload.DeviceID = Current.settingsStore.deviceID
        payload.Hostname = UIDevice.current.name
        payload.SourceType = (isBeaconUpdate ? .BluetoothLowEnergy : .GlobalPositioningSystem)

        var jsonPayload = "{\"missing\": \"payload\"}"
        if let p = payload.toJSONString(prettyPrint: false) {
            jsonPayload = p
        }

        let payloadDict: [String: Any] = Mapper<DeviceTrackerSee>().toJSON(payload)

        UIDevice.current.isBatteryMonitoringEnabled = false

        let realm = Current.realm()
        // swiftlint:disable:next force_try
        try! realm.write {
            realm.add(LocationHistoryEntry(updateType: updateType, location: payload.cllocation,
                                           zone: zone, payload: jsonPayload))
        }

        let promise = firstly {
            self.identifyDevice()
            }.then {_ in
                self.callService(domain: "device_tracker", service: "see", serviceData: payloadDict,
                                 shouldLog: false)
            }.done { _ in
                print("Device seen!")
                self.sendLocalNotification(withZone: zone, updateType: updateType, payloadDict: payloadDict)
        }

        promise.catch { err in
            print("Error when updating location!", err)
            Crashlytics.sharedInstance().recordError(err as NSError)
        }

        return promise
    }

    public func getAndSendLocation(trigger: LocationUpdateTrigger?) -> Promise<Void> {
        var updateTrigger: LocationUpdateTrigger = .Manual
        if let trigger = trigger {
            updateTrigger = trigger
        }
        print("getAndSendLocation called via", String(describing: updateTrigger))

        return Promise { seal in
            Current.isPerformingSingleShotLocationQuery = true
            self.oneShotLocationManager = OneShotLocationManager { location, error in
                guard let location = location else {
                    seal.reject(error ?? HomeAssistantAPIError.unknown)
                    return
                }

                Current.isPerformingSingleShotLocationQuery = true
                firstly {
                    self.submitLocation(updateType: updateTrigger, location: location,
                                        visit: nil, zone: nil)
                    }.done { _ in
                        seal.fulfill(())
                    }.catch { error in
                        seal.reject(error)
                }
            }
        }
    }

    func sendLocalNotification(withZone: RLMZone?, updateType: LocationUpdateTrigger,
                               payloadDict: [String: Any]) {
        let zoneName = withZone?.Name ?? "Unknown zone"
        let notificationOptions = updateType.notificationOptionsFor(zoneName: zoneName)
        Current.clientEventStore.addEvent(ClientEvent(text: notificationOptions.body, type: .locationUpdate,
                                                      payload: payloadDict))
        if notificationOptions.shouldNotify {
            let content = UNMutableNotificationContent()
            content.title = notificationOptions.title
            content.body = notificationOptions.body
            content.sound = UNNotificationSound.default

            let notificationRequest =
                UNNotificationRequest.init(identifier: notificationOptions.identifier ?? "",
                                           content: content, trigger: nil)
            UNUserNotificationCenter.current().add(notificationRequest)
        }
    }

}
