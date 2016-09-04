//
//  InputBooleanComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper

class InputBoolean: SwitchableEntity {
    
    override func mapping(map: Map) {
        super.mapping(map)
    }
    
    override var ComponentIcon: String {
        return "mdi:drawing"
    }
}