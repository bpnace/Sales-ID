//
//  Item.swift
//  SalesID
//
//  Created by Tarik Marshall on 08.08.25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
