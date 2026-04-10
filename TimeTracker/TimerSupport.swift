import Foundation
import SwiftUI
import SwiftData
import Combine

// Bridge old API names to the shared TimerManager defined elsewhere.
@MainActor
extension TimerManager {
    // Start alias to match older call sites
    func start(for subtask: Subtask) {
        startTimer(for: subtask)
    }
    
    // Stop alias to match older call sites
    func stop() {
        stopTimer()
    }
}

