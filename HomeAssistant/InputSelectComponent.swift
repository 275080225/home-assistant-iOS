//
//  InputSelectComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper

class InputSelect: Entity {
    
    var Options: [String]?
    
    required init?(_ map: Map) {
        super.init(value: map)
    }
    
    required init() {
        super.init()
    }
    
    override func mapping(map: Map) {
        super.mapping(map)
        
        Options          <- map["attributes.options"]
    }
    
    override class func ignoredProperties() -> [String] {
        return ["Options"]
    }
}