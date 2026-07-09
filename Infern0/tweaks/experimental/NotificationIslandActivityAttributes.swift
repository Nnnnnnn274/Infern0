//
//  NotificationIslandActivityAttributes.swift
//  Cyanide
//

import ActivityKit
import Foundation

struct NotificationIslandActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var body: String
        var source: String
        var requestIdentifier: String
        var sequence: Int
        var isVisible: Bool
    }

    var stableIdentifier: String
}
