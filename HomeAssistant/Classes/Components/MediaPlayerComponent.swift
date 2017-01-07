//
//  MediaPlayerComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper
import RealmSwift

class MediaPlayer: SwitchableEntity {

    dynamic var IsPlaying: Bool = false
    dynamic var IsIdle: Bool = false
    var IsVolumeMuted = RealmOptional<Bool>()
    dynamic var MediaContentID: String? = nil
    dynamic var MediaContentType: String? = nil
    var MediaDuration = RealmOptional<Int>()
    dynamic var MediaTitle: String? = nil
    var VolumeLevel = RealmOptional<Float>()
    dynamic var Source: String? = nil
    dynamic var SourceList: [String] = [String]()
    let StoredSourceList = List<StringObject>()
    dynamic var SupportsPause: Bool = false
    dynamic var SupportsSeek: Bool = false
    dynamic var SupportsVolumeSet: Bool = false
    dynamic var SupportsVolumeMute: Bool = false
    dynamic var SupportsPreviousTrack: Bool = false
    dynamic var SupportsNextTrack: Bool = false
    dynamic var SupportsTurnOn: Bool = false
    dynamic var SupportsTurnOff: Bool = false
    dynamic var SupportsPlayMedia: Bool = false
    dynamic var SupportsVolumeStep: Bool = false
    dynamic var SupportsSelectSource: Bool = false
    dynamic var SupportsStop: Bool = false
    dynamic var SupportsClearPlaylist: Bool = false
    var SupportedMediaCommands: Int?

    override func mapping(map: Map) {
        super.mapping(map: map)

        IsPlaying        <- (map["state"], ComponentBoolTransform(trueValue: "playing", falseValue: "paused"))
        IsIdle           <- (map["state"], ComponentBoolTransform(trueValue: "idle", falseValue: ""))
        IsVolumeMuted.value    <- map["attributes.is_volume_muted"]
        MediaContentID   <- map["attributes.media_content_id"]
        MediaContentType <- map["attributes.media_content_type"]
        MediaDuration.value    <- map["attributes.media_duration"]
        MediaTitle       <- map["attributes.media_title"]
        Source           <- map["attributes.source"]
        VolumeLevel.value      <- map["attributes.volume_level"]
        SourceList       <- map["attributes.source_list"]

        var StoredSourceList: [String]? = nil
        StoredSourceList     <- map["attributes.source_list"]
        StoredSourceList?.forEach { option in
            let value = StringObject()
            value.value = option
            self.StoredSourceList.append(value)
        }

        SupportedMediaCommands  <- map["attributes.supported_media_commands"]

        if let supported = self.SupportedMediaCommands {
            let features = MediaPlayerSupportedCommands(rawValue: supported)
            self.SupportsPause = features.contains(.Pause)
            self.SupportsSeek = features.contains(.Seek)
            self.SupportsVolumeSet = features.contains(.VolumeSet)
            self.SupportsVolumeMute = features.contains(.VolumeMute)
            self.SupportsPreviousTrack = features.contains(.PreviousTrack)
            self.SupportsNextTrack = features.contains(.NextTrack)
            self.SupportsTurnOn = features.contains(.TurnOn)
            self.SupportsTurnOff = features.contains(.TurnOff)
            self.SupportsPlayMedia = features.contains(.PlayMedia)
            self.SupportsVolumeStep = features.contains(.VolumeStep)
            self.SupportsSelectSource = features.contains(.SelectSource)
            self.SupportsStop = features.contains(.Stop)
            self.SupportsClearPlaylist = features.contains(.ClearPlaylist)
        }
    }

    override class func ignoredProperties() -> [String] {
        return ["SupportedMediaCommands", "SourceList", "SupportsPause", "SupportsSeek", "SupportsVolumeSet", "SupportsVolumeMute", "SupportsPreviousTrack", "SupportsNextTrack", "SupportsTurnOn", "SupportsTurnOff", "SupportsPlayMedia", "SupportsVolumeStep", "SupportsSelectSource", "SupportsStop", "SupportsClearPlaylist"]
    }

    func humanReadableMediaDuration() -> String {
        if let durationSeconds = self.MediaDuration.value {
            let hours = durationSeconds / 3600
            let minutes = (durationSeconds % 3600) / 60
            let seconds = (durationSeconds % 3600) % 60
            return "\(hours):\(minutes):\(seconds)"
        } else {
            return "00:00:00"
        }
    }

    func muteOn() {
        let _ = HomeAssistantAPI.sharedInstance.CallService(domain: "media_player", service: "volume_mute", serviceData: ["entity_id": self.ID as AnyObject, "is_volume_muted": "on" as AnyObject])
    }
    func muteOff() {
        let _ = HomeAssistantAPI.sharedInstance.CallService(domain: "media_player", service: "volume_mute", serviceData: ["entity_id": self.ID as AnyObject, "is_volume_muted": "off" as AnyObject])
    }
    func setVolume(_ newVolume: Float) {
        let fixedVolume = newVolume/100
        let _ = HomeAssistantAPI.sharedInstance.CallService(domain: "media_player", service: "volume_set", serviceData: ["entity_id": self.ID as AnyObject, "volume_level": fixedVolume as AnyObject])
    }

    override var ComponentIcon: String {
        return "mdi:cast"
    }

    override func StateIcon() -> String {
        return (self.State != "off" && self.State != "idle") ? "mdi:cast-connected" : "mdi:cast"
    }
}

struct MediaPlayerSupportedCommands: OptionSet {
    let rawValue: Int

    static let Pause = MediaPlayerSupportedCommands(rawValue: 1)
    static let Seek = MediaPlayerSupportedCommands(rawValue: 2)
    static let VolumeSet = MediaPlayerSupportedCommands(rawValue: 4)
    static let VolumeMute = MediaPlayerSupportedCommands(rawValue: 8)
    static let PreviousTrack = MediaPlayerSupportedCommands(rawValue: 16)
    static let NextTrack = MediaPlayerSupportedCommands(rawValue: 32)
    static let TurnOn = MediaPlayerSupportedCommands(rawValue: 128)
    static let TurnOff = MediaPlayerSupportedCommands(rawValue: 256)
    static let PlayMedia = MediaPlayerSupportedCommands(rawValue: 512)
    static let VolumeStep = MediaPlayerSupportedCommands(rawValue: 1024)
    static let SelectSource = MediaPlayerSupportedCommands(rawValue: 2048)
    static let Stop = MediaPlayerSupportedCommands(rawValue: 4096)
    static let ClearPlaylist = MediaPlayerSupportedCommands(rawValue: 8192)
}
