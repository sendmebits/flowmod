//
//  Item.swift
//  minput
//
//  Created by Chris Greco on 2026-01-31.
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
