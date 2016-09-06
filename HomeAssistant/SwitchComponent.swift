//
//  SwitchComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper
import RealmSwift

class Switch: SwitchableEntity {
    
    var TodayMilliwattHours = RealmOptional<Int>()
    var CurrentPowerMilliwattHours = RealmOptional<Int>()
    
    override func mapping(_ map: Map) {
        super.mapping(map)
        
        TodayMilliwattHours          <- map["attributes.today_mwh"]
        CurrentPowerMilliwattHours   <- map["attributes.current_power_mwh"]
    }
    
    override var ComponentIcon: String {
        return "mdi:flash"
    }
}
