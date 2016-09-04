//
//  SunComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper
import RealmSwift

class Sun: Entity {
    
    var Elevation = RealmOptional<Float>()
    var NextRising: NSDate? = nil
    var NextSetting: NSDate? = nil
    
    override func mapping(map: Map) {
        super.mapping(map)
        
        Elevation    <- map["attributes.elevation"]
        NextRising   <- (map["attributes.next_rising"], HomeAssistantTimestampTransform())
        NextSetting  <- (map["attributes.next_setting"], HomeAssistantTimestampTransform())
    }
    
    override func EntityColor() -> UIColor {
        return self.State == "above_horizon" ? colorWithHexString("#DCC91F", alpha: 1) : self.DefaultEntityUIColor
    }
    
    override var ComponentIcon: String {
        return "mdi:white-balance-sunny"
    }
}