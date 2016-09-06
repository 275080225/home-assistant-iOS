//
//  ServiceExecuted.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/9/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper

class ServiceExecutedEvent: SSEEvent {
    var ServiceCallID: String?
    
    required init?(_ map: Map) {
        super.init(map)
    }
    
    override func mapping(_ map: Map) {
        super.mapping(map)
        ServiceCallID <- map["data.service_call_id"]
    }
}
