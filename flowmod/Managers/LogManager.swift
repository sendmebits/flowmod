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
    
    /// Update the cached debug-logging flag. Safe to call from any thread.
    nonisolated func setDebugEnabled(_ enabled: Bool) {
        flagLock.lock()
        debugEnabledFlag = enabled
        flagLock.unlock()
    }

    private nonisolated var debugEnabled: Bool {
        flagLock.lock()
        defer { flagLock.unlock() }
        return debugEnabledFlag
    }

    /// Log a message (only if debug logging is enabled in settings).
    /// Safe to call from any thread — including the event-tap thread. The entry
    /// is appended on the main actor so the UI's observation of `logEntries`
    /// stays intact and the array is never mutated from two threads at once.
    nonisolated func log(_ message: String, category: String = "General") {
        guard debugEnabled else { return }

        let entry = LogEntry(timestamp: Date(), category: category, message: message)
        DispatchQueue.main.async { [weak self] in
            self?.appendEntry(entry)
        }
    }

    private func appendEntry(_ entry: LogEntry) {
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }
    
    /// Get all logs as a formatted string
    func getLogsAsString() -> String {
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
        logEntries.removeAll()
    }
    
    /// Number of log entries
    var entryCount: Int {
        logEntries.count
    }
}
