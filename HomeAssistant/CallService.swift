//
//  CallService.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/9/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper

class CallServiceEvent: SSEEvent {
    var Service: String?
    var Domain: String?
    var ServiceCallID: String?
    var ServiceData: [String:AnyObject] = [:]
    
    required init?(_ map: Map) {
        super.init(map)
    }
    
    override func mapping(map: Map) {
        super.mapping(map)
        Service       <- map["data.service"]
        Domain        <- map["data.domain"]
        ServiceCallID <- map["data.service_call_id"]
        ServiceData   <- map["data.service_data"]
    }
}