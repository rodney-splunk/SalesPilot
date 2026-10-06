import Foundation

enum WorkspacePaths {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["SALESPILOT_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = Bundle.main.object(forInfoDictionaryKey: "SalesPilotWorkspaceRoot") as? String, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/sales-copilot", isDirectory: true)
    }
    static var practiceRoot: URL?
    static var dataRoot: URL { practiceRoot ?? root }
    static var session: URL { dataRoot.appendingPathComponent("sessions/latest.json") }
    static var engine: URL { root.appendingPathComponent("engine", isDirectory: true) }
}

import SwiftUI
import AppKit

enum SalesPilotStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.42, green: 0.78, blue: 0.73, alpha: 1)
            : NSColor(red: 0.06, green: 0.39, blue: 0.38, alpha: 1)
    })
    static let buttonFill = Color(red: 0.06, green: 0.39, blue: 0.38)
}
