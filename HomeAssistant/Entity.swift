//
//  Entity.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper
import RealmSwift
import Realm

class Entity: Object, StaticMappable {
    let DefaultEntityUIColor = colorWithHexString("#44739E", alpha: 1)
    
    dynamic var ID: String = ""
    dynamic var Domain: String = ""
    dynamic var State: String = ""
    dynamic var Attributes: [String:AnyObject] {
        get {
            guard let dictionaryData = attributesData else {
                return [String: AnyObject]()
            }
            do {
                let dict = try JSONSerialization.jsonObject(with: dictionaryData, options: []) as? [String: AnyObject]
                return dict!
            } catch {
                return [String: AnyObject]()
            }
        }
        
        set {
            do {
                let data = try JSONSerialization.data(withJSONObject: newValue, options: [])
                attributesData = data
            } catch {
                attributesData = nil
            }
        }
    }
    fileprivate dynamic var attributesData: Data?
    dynamic var FriendlyName: String? = nil
    dynamic var Hidden = false
    dynamic var Icon: String? = nil
    dynamic var MobileIcon: String? = nil
    dynamic var Picture: String? = nil
    var DownloadedPicture: UIImage?
    var UnitOfMeasurement: String?
    dynamic var LastChanged: Date? = nil
    dynamic var LastUpdated: Date? = nil
//    let Groups = LinkingObjects(fromType: Group.self, property: "Entities")
    
    // Z-Wave properties
    dynamic var Location: String? = nil
    dynamic var NodeID: String? = nil
    var BatteryLevel = RealmOptional<Int>()
    
    // MARK: - Requireds - https://github.com/Hearst-DD/ObjectMapper/issues/462
    required init() { super.init() }
    required init?(_ map: Map) { super.init() }
    required init(value: AnyObject, schema: RLMSchema) { super.init(value: value, schema: schema) }
    required init(realm: RLMRealm, schema: RLMObjectSchema) { super.init(realm: realm, schema: schema) }
    
    init(id: String) {
        super.init()
        self.ID = id
        self.Domain = EntityIDToDomainTransform().transformFromJSON(self.ID as AnyObject?)!
    }
    
    class func objectForMapping(_ map: Map) -> Mappable? {
        if let entityId: String = map["entity_id"].value() {
            let entityType = EntityIDToDomainTransform().transformFromJSON(entityId as AnyObject?)!
            switch entityType {
            case "binary_sensor":
                return BinarySensor(map)
            case "climate":
                return Climate(map)
            case "device_tracker":
                return DeviceTracker(map)
            case "group":
                return Group(map)
            case "garage_door":
                return GarageDoor(map)
            case "input_boolean":
                return InputBoolean(map)
            case "input_slider":
                return InputSlider(map)
            case "input_select":
                return InputSelect(map)
            case "light":
                return Light(map)
            case "lock":
                return Lock(map)
            case "media_player":
                return MediaPlayer(map)
            case "scene":
                return Scene(map)
            case "script":
                return Script(map)
            case "sensor":
                return Sensor(map)
            case "sun":
                return Sun(map)
            case "switch":
                return Switch(map)
            case "thermostat":
                return Thermostat(map)
            case "weblink":
                return Weblink(map)
            case "zone":
                return Zone(map)
            default:
                print("No class found for:", entityType)
                return Entity(map)
            }
        }
        return nil
    }

    func mapping(_ map: Map) {
        ID                <- map["entity_id"]
        Domain            <- (map["entity_id"], EntityIDToDomainTransform())
        State             <- map["state"]
        Attributes        <- map["attributes"]
        FriendlyName      <- map["attributes.friendly_name"]
        Hidden            <- map["attributes.hidden"]
        Icon              <- map["attributes.icon"]
        MobileIcon        <- map["attributes.mobile_icon"]
        Picture           <- map["attributes.entity_picture"]
        UnitOfMeasurement <- map["attributes.unit_of_measurement"]
        LastChanged       <- (map["last_changed"], HomeAssistantTimestampTransform())
        LastUpdated       <- (map["last_updated"], HomeAssistantTimestampTransform())
        
        // Z-Wave properties
        NodeID            <- map["attributes.node_id"]
        Location          <- map["attributes.location"]
        BatteryLevel      <- map["attributes.battery_level"]
        
        if let pic = self.Picture {
            HomeAssistantAPI.sharedInstance.getImage(pic).then { image -> Void in
                self.DownloadedPicture = image
                }.error { err -> Void in
                    print("Error when attempting to download image", err)
            }
        }
    }
    
    override class func ignoredProperties() -> [String] {
        return ["Attributes", "DownloadedPicture"]
    }
    
    override static func primaryKey() -> String? {
        return "ID"
    }
    
    func turnOn() {
        HomeAssistantAPI.sharedInstance.turnOnEntity(self)
    }
    
    func turnOff() {
        HomeAssistantAPI.sharedInstance.turnOffEntity(self)
    }
    
    func toggle() {
        HomeAssistantAPI.sharedInstance.toggleEntity(self)
    }
    
    var ComponentIcon : String {
        switch (self.Domain) {
        case "alarm_control_panel":
            return "mdi:bell"
        case "automation":
            return "mdi:playlist-play"
        case "binary_sensor":
            return "mdi:checkbox-marked-circle"
        case "camera":
            return "mdi:video"
        case "climate":
            return "mdi:nest-thermostat"
        case "configurator":
            return "mdi:settings"
        case "conversation":
            return "mdi:text-to-speech"
        case "cover":
            return "mdi:window-closed"
        case "device_tracker":
            return "mdi:account"
        case "fan":
            return "mdi:fan"
        case "garage_door":
            return "mdi:glassdoor"
        case "group":
            return "mdi:google-circles-communities"
        case "homeassistant":
            return "mdi:home"
        case "hvac":
            return "mdi:air-conditioner"
        case "input_boolean":
            return "mdi:drawing"
        case "input_select":
            return "mdi:format-list-bulleted"
        case "input_slider":
            return "mdi:ray-vertex"
        case "light":
            return "mdi:lightbulb"
        case "lock":
            return "mdi:lock"
        case "media_player":
            return "mdi:cast"
        case "notify":
            return "mdi:comment-alert"
        case "proximity":
            return "mdi:apple-safari"
        case "rollershutter":
            return "mdi:window-closed"
        case "scene":
            return "mdi:google-pages"
        case "script":
            return "mdi:file-document"
        case "sensor":
            return "mdi:eye"
        case "simple_alarm":
            return "mdi:bell"
        case "sun":
            return "mdi:white-balance-sunny"
        case "switch":
            return "mdi:flash"
        case "thermostat":
            return "mdi:nest-thermostat"
        case "updater":
            return "mdi:cloud-upload"
        case "weblink":
            return "mdi:open-in-new"
        default:
            print("Unable to find icon for domain \(self.Domain) (\(self.State))")
            return "mdi:bookmark"
        }
    }
    
    func StateIcon() -> String {
        switch self {
        case is BinarySensor:
            return (self as! BinarySensor).StateIcon()
        case is Lock:
            return (self as! Lock).StateIcon()
        case is MediaPlayer:
            return (self as! MediaPlayer).StateIcon()
        default:
            if self.MobileIcon != nil { return self.MobileIcon! }
            if self.Icon != nil { return self.Icon! }
            
            if (self.UnitOfMeasurement == "°C" || self.UnitOfMeasurement == "°F") {
                return "mdi:thermometer"
            } else if (self.UnitOfMeasurement == "Mice") {
                return "mdi:mouse-variant"
            }
            return self.ComponentIcon
        }
    }

    func EntityColor() -> UIColor {
        switch self {
        case is Light:
            return (self as! Light).EntityColor()
        case is Sun:
            return (self as! Sun).EntityColor()
        case is SwitchableEntity:
            return (self as! SwitchableEntity).EntityColor()
        default:
            let hexColor = self.State == "unavailable" ? "#bdbdbd" : "#44739E"
            return colorWithHexString(hexColor, alpha: 1)
        }
    }
    
    var EntityIcon: UIImage {
        var icon = self.StateIcon()
        if self.MobileIcon != nil { icon = self.MobileIcon! }
        if self.Icon != nil { icon = self.Icon! }
        return getIconForIdentifier(icon, iconWidth: 30, iconHeight: 30, color: EntityColor())
    }
    
    var Name : String {
        if let friendly = self.FriendlyName {
            return friendly
        } else {
            return self.ID.replacingOccurrences(of: "\(self.Domain).", with: "").capitalized
        }
    }
    
}

open class StringObject: Object {
    open dynamic var value: String?
}

open class EntityIDToDomainTransform: TransformType {
    public typealias Object = String
    public typealias JSON = String
    
    public init() {}
    
    open func transformFromJSON(_ value: AnyObject?) -> String? {
        if let entityId = value as? String {
            return entityId.components(separatedBy: ".")[0]
        }
        return nil
    }
    
    open func transformToJSON(_ value: String?) -> String? {
        return nil
    }
}

open class HomeAssistantTimestampTransform: DateFormatterTransform {
    
    public init() {
        let formatter = DateFormatter()
        formatter.locale = NSLocale(localeIdentifier: "en_US_POSIX") as Locale!
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let HATimezone = UserDefaults.standard.string(forKey: "time_zone") {
            formatter.timeZone = NSTimeZone(identifier: HATimezone)!
        } else {
            formatter.timeZone = NSTimeZone.autoupdatingCurrent
        }
        
        super.init(dateFormatter: formatter)
    }
}

open class ComponentBoolTransform: TransformType {
    
    public typealias Object = Bool
    public typealias JSON = String
    
    let trueValue: String
    let falseValue: String
    
    public init(trueValue: String, falseValue: String) {
        self.trueValue = trueValue
        self.falseValue = falseValue
    }
    
    open func transformFromJSON(_ value: AnyObject?) -> Bool? {
        return (String(value!) == self.trueValue)
    }
    
    open func transformToJSON(_ value: Bool?) -> String? {
        return (value == true) ? self.trueValue : self.falseValue
    }
}
