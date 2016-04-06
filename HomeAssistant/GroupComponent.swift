//
//  GroupComponent.swift
//  HomeAssistant
//
//  Created by Robbie Trencheny on 4/5/16.
//  Copyright © 2016 Robbie Trencheny. All rights reserved.
//

import Foundation
import ObjectMapper

let isAllGroupTransform = TransformOf<Bool, String>(fromJSON: { (value: String?) -> Bool? in
    return Bool((String(value!).rangeOfString("group.all_") != nil))
    }, toJSON: { (value: Bool?) -> String? in
        if let value = value {
            return String(value)
        }
        return nil
})

class Group: Entity {
    
    var IsAllGroup: Bool?
    var Auto: Bool?
    var Order: Int?
    var EntityIds: [String]?
    
    required init?(_ map: Map) {
        super.init(map)
    }
    
    override func mapping(map: Map) {
        super.mapping(map)
        
        IsAllGroup    <- (map["entity_id"], isAllGroupTransform)
        Auto          <- map["attributes.auto"]
        Order         <- map["attributes.order"]
        EntityIds     <- map["attributes.entity_id"]
    }
}