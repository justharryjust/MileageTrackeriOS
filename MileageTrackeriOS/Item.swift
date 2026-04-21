//
//  Item.swift
//  MileageTrackeriOS
//
//  Created by Harry Just on 21/04/2026.
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
