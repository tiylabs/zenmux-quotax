import Foundation

public final class PersistentLogStore {
    private struct SessionState: Codable {
        var sessionID: String
        var pid: Int32
        var startedAt: String
        var lastUpdatedAt: String
        var endedAt: String?
        var normalTermination: Bool
        var terminationReason: String?
    }

    public static let shared = PersistentLogStore()

    public let logDirectoryURL: URL
    public let currentLogFileURL: URL

    private let sessionStateURL: URL
    private let lock = NSRecursiveLock()
    private let isoFormatter: ISO8601DateFormatter
    private let fileManager: FileManager
    private var fileHandle: FileHandle?
    private var minimumLevel: AppLogLevel = .info
    private var sessionID = UUID().uuidString
    private var hasStarted = false
    private var isShutDown = false
    private var sessionStartedAt: String?
    private var lastSessionStateWriteAt = Date.distantPast

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        let libraryLogsURL: URL
        if let libraryURL {
            libraryLogsURL = libraryURL.appendingPathComponent("Logs", isDirectory: true)
        } else {
            libraryLogsURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        }
        self.logDirectoryURL = libraryLogsURL.appendingPathComponent(AppConstants.Logging.directoryName, isDirectory: true)
        self.currentLogFileURL = logDirectoryURL.appendingPathComponent(AppConstants.Logging.currentFileName, isDirectory: false)
        self.sessionStateURL = logDirectoryURL.appendingPathComponent(AppConstants.Logging.sessionStateFileName, isDirectory: false)
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter.timeZone = .current
    }

    public func start(minimumLevel: AppLogLevel) {
        lock.lock()
        defer { lock.unlock() }

        self.minimumLevel = minimumLevel
        guard !hasStarted else { return }
        beginSessionLocked()
    }

    public func setMinimumLevel(_ level: AppLogLevel) {
        lock.lock()
        defer { lock.unlock() }

        let previousLevel = minimumLevel
        minimumLevel = level
        guard hasStarted, previousLevel != level else { return }
        writeIfAllowedLocked(
            level: .info,
            category: "settings",
            message: "Log minimum level changed from \(previousLevel.rawValueString) to \(level.rawValueString)",
            forceSync: true
        )
    }

    public func write(level: AppLogLevel, category: String, message: () -> String, file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        lock.lock()
        defer { lock.unlock() }

        guard shouldWrite(level) else { return }
        if !hasStarted {
            startLockedIfNeeded()
        }
        let renderedMessage = message()
        guard shouldWrite(level) else { return }
        let source = "\(file):\(line) \(function)"
        writeLocked(
            level: level,
            category: category,
            message: renderedMessage,
            source: source,
            forceSync: level.shouldSynchronizeImmediately || category == "lifecycle"
        )
    }

    public func flush() {
        lock.lock()
        defer { lock.unlock() }

        synchronizeLocked()
        updateSessionState(normalTermination: false, terminationReason: nil)
    }

    public func shutdown(reason: String) {
        lock.lock()
        defer { lock.unlock() }

        guard hasStarted else { return }
        writeIfAllowedLocked(
            level: .info,
            category: "lifecycle",
            message: "Persistent file logging shutting down; reason=\(reason)",
            forceSync: true
        )
        updateSessionState(normalTermination: true, terminationReason: reason)
        synchronizeLocked()
        closeFileLocked()
        isShutDown = true
    }

    public func clearArchivedLogs() {
        lock.lock()
        defer { lock.unlock() }

        guard let files = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil) else { return }
        for fileURL in files where fileURL.lastPathComponent.hasPrefix("quotax-") && fileURL.pathExtension == "log" {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func startLockedIfNeeded() {
        guard !hasStarted else { return }
        beginSessionLocked()
    }

    private func beginSessionLocked() {
        hasStarted = true
        isShutDown = false
        sessionID = UUID().uuidString
        sessionStartedAt = timestamp()
        lastSessionStateWriteAt = .distantPast
        do {
            try prepareLogFileIfNeeded()
            let previousState = readSessionState()
            updateSessionState(normalTermination: false, terminationReason: nil)
            if let previousState, !previousState.normalTermination {
                writeUnexpectedPreviousSessionLocked(previousState)
            }
            writeIfAllowedLocked(
                level: .info,
                category: "lifecycle",
                message: "Persistent file logging started; file=\(currentLogFileURL.path), minimumLevel=\(minimumLevel.rawValueString)",
                forceSync: true
            )
        } catch {
            hasStarted = false
        }
    }

    private func shouldWrite(_ level: AppLogLevel) -> Bool {
        level.rawValue >= minimumLevel.rawValue
    }

    private func writeUnexpectedPreviousSessionLocked(_ previousState: SessionState) {
        let message = [
            "Previous session ended unexpectedly",
            "previousSession=\(previousState.sessionID)",
            "previousPid=\(previousState.pid)",
            "previousStartedAt=\(previousState.startedAt)",
            "previousLastUpdatedAt=\(previousState.lastUpdatedAt)"
        ].joined(separator: "; ")
        writeIfAllowedLocked(level: .error, category: "lifecycle", message: message, forceSync: true)
    }

    private func prepareLogFileIfNeeded() throws {
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: currentLogFileURL.path) {
            fileManager.createFile(atPath: currentLogFileURL.path, contents: nil)
        }
        try rotateCurrentLogIfNeeded()
        fileHandle = try FileHandle(forWritingTo: currentLogFileURL)
        try fileHandle?.seekToEnd()
    }

    private func rotateCurrentLogIfNeeded() throws {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: currentLogFileURL.path),
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.uint64Value >= AppConstants.Logging.maxFileSizeBytes
        else {
            return
        }

        let archiveName = "quotax-\(archiveTimestamp())-\(UUID().uuidString).log"
        let archiveURL = logDirectoryURL.appendingPathComponent(archiveName, isDirectory: false)
        try fileManager.moveItem(at: currentLogFileURL, to: archiveURL)
        fileManager.createFile(atPath: currentLogFileURL.path, contents: nil)
        removeExcessArchivedLogs()
    }

    private func removeExcessArchivedLogs() {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: logDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else {
            return
        }
        let archivedLogs =
            files
            .filter {
                $0.lastPathComponent.hasPrefix("quotax-") && $0.pathExtension == "log"
            }
            .sorted { lhs, rhs in
                let lhsValues = try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                let rhsValues = try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                let lhsDate = lhsValues?.contentModificationDate ?? .distantPast
                let rhsDate = rhsValues?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
        for fileURL in archivedLogs.dropFirst(AppConstants.Logging.maxArchivedFiles) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func writeIfAllowedLocked(level: AppLogLevel, category: String, message: String, forceSync: Bool) {
        guard shouldWrite(level) else { return }
        writeLocked(level: level, category: category, message: message, source: nil, forceSync: forceSync)
    }

    private func writeLocked(level: AppLogLevel, category: String, message: String, source: String? = nil, forceSync: Bool) {
        guard !isShutDown || category == "lifecycle" else { return }
        do {
            if fileHandle == nil {
                try prepareLogFileIfNeeded()
            }
            let sourceText = source.map { " [source=\(sanitize($0))]" } ?? ""
            let line = "\(timestamp()) [\(level.label)] [\(category)] [session=\(sessionID)] [pid=\(ProcessInfo.processInfo.processIdentifier)]\(sourceText) \(sanitize(message))\n"
            guard let data = line.data(using: .utf8) else { return }
            if shouldRotateBeforeWriting(entrySize: UInt64(data.count)) {
                closeFileLocked()
                try rotateCurrentLogIfNeeded()
                fileHandle = try FileHandle(forWritingTo: currentLogFileURL)
                try fileHandle?.seekToEnd()
            }
            try fileHandle?.write(contentsOf: data)
            updateSessionStateIfNeeded(force: forceSync)
            if forceSync {
                synchronizeLocked()
            }
        } catch {
            reportEmergencyLogFailure("Failed to write log entry", error: error)
            closeFileLocked()
        }
    }

    private func shouldRotateBeforeWriting(entrySize: UInt64) -> Bool {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: currentLogFileURL.path),
            let fileSize = attributes[.size] as? NSNumber
        else {
            return false
        }
        return fileSize.uint64Value + entrySize >= AppConstants.Logging.maxFileSizeBytes
    }

    private func updateSessionStateIfNeeded(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSessionStateWriteAt) >= 1 else { return }
        updateSessionState(normalTermination: false, terminationReason: nil)
    }

    private func updateSessionState(normalTermination: Bool, terminationReason: String?) {
        let now = timestamp()
        let state = SessionState(
            sessionID: sessionID,
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: sessionStartedAt ?? now,
            lastUpdatedAt: now,
            endedAt: normalTermination ? now : nil,
            normalTermination: normalTermination,
            terminationReason: terminationReason
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        do {
            try data.write(to: sessionStateURL, options: .atomic)
            lastSessionStateWriteAt = Date()
        } catch {
            reportEmergencyLogFailure("Failed to write session state", error: error)
        }
    }

    private func readSessionState() -> SessionState? {
        guard let data = try? Data(contentsOf: sessionStateURL) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    private func timestamp() -> String {
        isoFormatter.string(from: Date())
    }

    private func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private func sanitize(_ message: String) -> String {
        message.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
    }

    private func reportEmergencyLogFailure(_ context: String, error: Error) {
        let fallbackLine = [
            timestamp(),
            "[ERROR]",
            "[logging]",
            "[session=\(sessionID)]",
            "[pid=\(ProcessInfo.processInfo.processIdentifier)]",
            "\(context): \(sanitize(error.localizedDescription))\n"
        ].joined(separator: " ")
        if let data = fallbackLine.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private func synchronizeLocked() {
        if #available(macOS 10.15.4, *) {
            try? fileHandle?.synchronize()
        } else {
            fileHandle?.synchronizeFile()
        }
    }

    private func closeFileLocked() {
        if #available(macOS 10.15.4, *) {
            try? fileHandle?.close()
        } else {
            fileHandle?.closeFile()
        }
        fileHandle = nil
    }
}
