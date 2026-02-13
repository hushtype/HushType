//
//  Item.swift
//  HushType
//
//  Created by Harun Güngörer on 13.02.2026.
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
