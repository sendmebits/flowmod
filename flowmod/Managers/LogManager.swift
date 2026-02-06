import Foundation
import AppKit

/// Manages debug logging for the app
@MainActor
@Observable
class LogManager {
    static let shared = LogManager()
    
    private let maxLogEntries = 500
    private var logEntries: [LogEntry] = []
    
    struct LogEntry {
        let timestamp: Date
        let category: String
        let message: String
        
        var formatted: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return "[\(formatter.string(from: timestamp))] [\(category)] \(message)"
        }
    }
    
    private init() {}
    
    /// Log a message (only if debug logging is enabled in settings)
    func log(_ message: String, category: String = "General") {
        guard Settings.shared.debugLogging else { return }
        
        let entry = LogEntry(timestamp: Date(), category: category, message: message)
        logEntries.append(entry)
        
        // Trim old entries if needed
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }
    
    /// Get all logs as a formatted string
    func getLogsAsString() -> String {
        if logEntries.isEmpty {
            return "No logs available.\n\nNote: Enable 'Debug Logging' in Advanced settings to capture logs."
        }
        
        var output = "minput Debug Logs\n"
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
