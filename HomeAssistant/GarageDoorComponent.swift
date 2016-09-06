//
//  GarageDoorComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper

class GarageDoor: Entity {
    
    dynamic var IsOpen: Bool = false
    
    override func mapping(map: Map) {
        super.mapping(map)
        
        IsOpen    <- (map["state"], ComponentBoolTransform(trueValue: "open", falseValue: "closed"))
    }
    
    override var ComponentIcon: String {
        return "mdi:glassdoor"
    }
}