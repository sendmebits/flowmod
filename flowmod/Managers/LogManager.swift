import Foundation
import AppKit

/// Manages debug logging for the app
@MainActor
@Observable
class LogManager {
    static let shared = LogManager()
    
    private let maxLogEntries = 500
    private var logEntries: [LogEntry] = []

    /// Thread-safe mirror of `Settings.debugLogging`, readable from the
    /// event-tap thread without touching the main actor. Kept in sync by
    /// `Settings` whenever the toggle changes (see `setDebugEnabled`).
    @ObservationIgnored private let flagLock = NSLock()
    @ObservationIgnored nonisolated(unsafe) private var debugEnabledFlag = false
    /// Bound the producer backlog as well as the visible log. Event-tap callbacks
    /// must not enqueue one main-queue block per message during a log flood.
    @ObservationIgnored nonisolated(unsafe) private var pendingEntries: [LogEntry] = []
    @ObservationIgnored nonisolated(unsafe) private var drainScheduled = false
    @ObservationIgnored nonisolated(unsafe) private var clearGeneration: UInt64 = 0
    
    /// Shared date formatter (DateFormatter is expensive to create)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    struct LogEntry {
        let timestamp: Date
        let category: String
        let message: String
        
        var formatted: String {
            return "[\(LogManager.dateFormatter.string(from: timestamp))] [\(category)] \(message)"
        }
    }
    
    private init() {}

#if DEBUG || SWIFT_PACKAGE
    static func makeForTesting() -> LogManager {
        LogManager()
    }
#endif
    
    /// Update the cached debug-logging flag. Safe to call from any thread.
    nonisolated func setDebugEnabled(_ enabled: Bool) {
        flagLock.lock()
        debugEnabledFlag = enabled
        flagLock.unlock()
    }

    /// Log a message (only if debug logging is enabled in settings).
    /// Safe to call from any thread — including the event-tap thread. The entry
    /// is appended on the main actor so the UI's observation of `logEntries`
    /// stays intact and the array is never mutated from two threads at once.
    nonisolated func log(_ message: @autoclosure () -> String, category: String = "General") {
        flagLock.lock()
        guard debugEnabledFlag else { flagLock.unlock(); return }
        let generation = clearGeneration
        flagLock.unlock()

        // Evaluate the message outside the lock: callers may inspect other
        // lock-protected state or even clear logs while preparing the message.
        let entry = LogEntry(timestamp: Date(), category: category, message: message())
        flagLock.lock()
        guard generation == clearGeneration else { flagLock.unlock(); return }
        if pendingEntries.count == maxLogEntries {
            pendingEntries.removeFirst()
        }
        pendingEntries.append(entry)
        let needsDrain = !drainScheduled
        drainScheduled = true
        flagLock.unlock()

        if needsDrain {
            DispatchQueue.main.async { [weak self] in
                self?.drainPendingEntries(releaseSchedule: true)
            }
        }
    }

    private func drainPendingEntries(releaseSchedule: Bool) {
        flagLock.lock()
        let entries = pendingEntries
        pendingEntries.removeAll(keepingCapacity: true)
        if releaseSchedule { drainScheduled = false }
        flagLock.unlock()

        guard !entries.isEmpty else { return }
        logEntries.append(contentsOf: entries)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }
    
    /// Get all logs as a formatted string
    func getLogsAsString() -> String {
        // Copy includes messages already captured by the background thread,
        // even when its scheduled UI update has not run yet.
        drainPendingEntries(releaseSchedule: false)
        if logEntries.isEmpty {
            return "No logs available.\n\nNote: Enable 'Debug Logging' in Advanced settings to capture logs."
        }
        
        var output = "FlowMod Debug Logs\n"
        output += "================\n"
        output += "Exported: \(Date())\n"
        output += "Entries: \(logEntries.count)\n\n"
        
        for entry in logEntries {
            output += entry.formatted + "\n"
        }
        
        return output
    }
    
    /// Copy logs to clipboard
    func copyLogsToClipboard() {
        let logs = getLogsAsString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logs, forType: .string)
    }
    
    /// Clear all logs
    func clearLogs() {
        flagLock.lock()
        clearGeneration &+= 1
        pendingEntries.removeAll(keepingCapacity: true)
        flagLock.unlock()
        logEntries.removeAll()
    }
    
    /// Number of log entries
    var entryCount: Int {
        logEntries.count
    }
}
