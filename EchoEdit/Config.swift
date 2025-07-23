//
//  Config.swift
//  EchoEdit
//
//  Created by Steven Strange on 6/26/25.
//

import Foundation

struct AppConfig {
    // MARK: - UI Settings
    static let maxImageDimension: CGFloat = 1600
    static let defaultPromptDelay: UInt64 = 3_000_000_000 // 3 seconds
    static let defaultCharDelay: UInt64 = 30_000_000      // 30 ms
}
