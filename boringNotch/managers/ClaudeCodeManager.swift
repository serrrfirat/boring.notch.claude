//
//  ClaudeCodeManager.swift
//  boringNotch
//
//  Created for Claude Code Notch integration
//

import Foundation
import Combine
import UserNotifications
import AppKit

@MainActor
final class ClaudeCodeManager: ObservableObject {
    static let shared = ClaudeCodeManager()

    // MARK: - Published Properties

    @Published private(set) var availableSessions: [ClaudeSession] = []
    @Published var selectedSession: ClaudeSession?
    @Published private(set) var state: ClaudeCodeState = ClaudeCodeState()
    @Published private(set) var dailyStats: DailyStats = DailyStats()

    // MARK: - Private Properties

    // Use the real home directory, not the sandboxed container
    private let claudeDir: URL = {
        // Get the real home directory by reading from passwd, bypassing sandbox
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            let homePath = String(cString: home)
            return URL(fileURLWithPath: homePath).appendingPathComponent(".claude")
        }
        // Fallback to standard (will be sandboxed)
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }()
    private var ideDir: URL { claudeDir.appendingPathComponent("ide") }
    private var projectsDir: URL { claudeDir.appendingPathComponent("projects") }

    private var sessionFileWatcher: DispatchSourceFileSystemObject?
    private var ideDirWatcher: DispatchSourceFileSystemObject?
    private var sessionFileHandle: FileHandle?
    private var lastReadPosition: UInt64 = 0

    private var sessionScanTimer: Timer?

    // MARK: - Initialization

    private init() {
        setupNotifications()
        startSessionScanning()
        loadDailyStats()
    }

    // Note: cleanup is handled by stopWatching() called manually or when app terminates

    // MARK: - Public Methods

    /// Scan for active Claude Code sessions
    func scanForSessions() {
        let fm = FileManager.default

        print("[ClaudeCode] Scanning for sessions in: \(ideDir.path)")

        guard fm.fileExists(atPath: ideDir.path) else {
            print("[ClaudeCode] IDE directory does not exist")
            availableSessions = []
            return
        }

        do {
            let lockFiles = try fm.contentsOfDirectory(at: ideDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "lock" }

            print("[ClaudeCode] Found \(lockFiles.count) lock files")

            var sessions: [ClaudeSession] = []

            for lockFile in lockFiles {
                print("[ClaudeCode] Checking lock file: \(lockFile.lastPathComponent)")

                guard let data = fm.contents(atPath: lockFile.path) else {
                    print("[ClaudeCode] Could not read lock file data")
                    continue
                }

                do {
                    let session = try JSONDecoder().decode(ClaudeSession.self, from: data)
                    print("[ClaudeCode] Decoded session: pid=\(session.pid), workspace=\(session.workspaceFolders.first ?? "none"), projectKey=\(session.projectKey ?? "none")")

                    // Verify process is still running
                    if isProcessRunning(pid: session.pid) {
                        print("[ClaudeCode] Process \(session.pid) is running, adding session")
                        sessions.append(session)
                    } else {
                        print("[ClaudeCode] Process \(session.pid) is NOT running, skipping")
                    }
                } catch {
                    print("[ClaudeCode] Failed to decode session: \(error)")
                }
            }

            print("[ClaudeCode] Total active sessions: \(sessions.count)")
            availableSessions = sessions

            // Auto-select if only one session and none selected
            if selectedSession == nil && sessions.count == 1 {
                print("[ClaudeCode] Auto-selecting single session")
                selectSession(sessions[0])
            }

            // Clear selection if selected session no longer exists
            if let selected = selectedSession,
               !sessions.contains(where: { $0.pid == selected.pid }) {
                selectedSession = nil
                state = ClaudeCodeState()
                stopWatchingSessionFile()
            }

        } catch {
            print("[ClaudeCode] Error scanning for sessions: \(error)")
        }
    }

    /// Select a session to monitor
    func selectSession(_ session: ClaudeSession) {
        guard session != selectedSession else { return }

        print("[ClaudeCode] Selecting session: \(session.displayName)")
        selectedSession = session
        state = ClaudeCodeState()
        state.cwd = session.workspaceFolders.first ?? ""

        startWatchingSessionFile()
    }

    /// Manually refresh state
    func refresh() {
        scanForSessions()
        if selectedSession != nil {
            readNewSessionData()
        }
    }

    // MARK: - Session Scanning

    private func startSessionScanning() {
        // Initial scan
        scanForSessions()

        // Periodic scan every 5 seconds
        sessionScanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForSessions()
                self?.loadDailyStats()
            }
        }
    }

    private func isProcessRunning(pid: Int) -> Bool {
        // Use NSRunningApplication or check /proc to avoid sandbox restrictions with kill()
        // The kill() approach doesn't work in sandboxed apps
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.processIdentifier == Int32(pid) }) {
            return true
        }

        // Fallback: check if the process directory exists (works for any process)
        let procPath = "/proc/\(pid)"
        if FileManager.default.fileExists(atPath: procPath) {
            return true
        }

        // Another fallback: try to get process info via sysctl
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)

        // If sysctl succeeds and returns data, process exists
        return result == 0 && size > 0
    }

    // MARK: - File Watching

    private func startWatchingSessionFile() {
        stopWatchingSessionFile()

        guard let session = selectedSession,
              let projectKey = session.projectKey else {
            print("[ClaudeCode] No session or projectKey available")
            return
        }

        print("[ClaudeCode] Looking for project dir with key: \(projectKey)")
        let projectDir = projectsDir.appendingPathComponent(projectKey)
        print("[ClaudeCode] Project dir path: \(projectDir.path)")
        print("[ClaudeCode] Project dir exists: \(FileManager.default.fileExists(atPath: projectDir.path))")

        // Find the most recent JSONL file (not agent files)
        guard let jsonlFile = findCurrentSessionFile(in: projectDir) else {
            print("[ClaudeCode] No session file found for project: \(projectKey)")
            return
        }

        print("[ClaudeCode] Watching session file: \(jsonlFile.path)")

        // Open file for reading
        do {
            sessionFileHandle = try FileHandle(forReadingFrom: jsonlFile)

            // Seek to end to only read new content
            sessionFileHandle?.seekToEndOfFile()
            lastReadPosition = sessionFileHandle?.offsetInFile ?? 0

            // But first, read recent history for initial state
            loadRecentHistory(from: jsonlFile)

        } catch {
            print("Error opening session file: \(error)")
            return
        }

        // Set up file system watcher
        let fd = open(jsonlFile.path, O_EVTONLY)
        guard fd >= 0 else {
            print("Failed to open file descriptor for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readNewSessionData()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sessionFileWatcher = source
        state.isConnected = true
    }

    private func stopWatchingSessionFile() {
        sessionFileWatcher?.cancel()
        sessionFileWatcher = nil
        sessionFileHandle?.closeFile()
        sessionFileHandle = nil
        lastReadPosition = 0
        state.isConnected = false
    }

    private func stopWatching() {
        sessionScanTimer?.invalidate()
        sessionScanTimer = nil
        stopWatchingSessionFile()
        ideDirWatcher?.cancel()
        ideDirWatcher = nil
    }

    private func findCurrentSessionFile(in projectDir: URL) -> URL? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectDir.path) else { return nil }

        do {
            let files = try fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    return date1 > date2
                }

            return files.first
        } catch {
            print("Error finding session file: \(error)")
            return nil
        }
    }

    // MARK: - Data Reading

    private func loadRecentHistory(from file: URL) {
        print("[ClaudeCode] Loading recent history from: \(file.lastPathComponent)")

        // Read last ~50 lines for initial state
        guard let data = FileManager.default.contents(atPath: file.path),
              let content = String(data: data, encoding: .utf8) else {
            print("[ClaudeCode] Could not read file contents")
            return
        }

        let lines = content.components(separatedBy: .newlines)
        let recentLines = lines.suffix(50)
        print("[ClaudeCode] Parsing \(recentLines.count) recent lines from \(lines.count) total")

        for line in recentLines where !line.isEmpty {
            parseJSONLLine(line)
        }

        print("[ClaudeCode] After parsing - model: \(state.model), tokens: \(state.tokenUsage.totalTokens), connected: \(state.isConnected)")
        state.lastUpdateTime = Date()
    }

    private func readNewSessionData() {
        guard let handle = sessionFileHandle else { return }

        // Read new data from last position
        handle.seek(toFileOffset: lastReadPosition)
        let newData = handle.readDataToEndOfFile()
        lastReadPosition = handle.offsetInFile

        guard !newData.isEmpty,
              let content = String(data: newData, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseJSONLLine(line)
        }

        state.lastUpdateTime = Date()
    }

    // MARK: - JSONL Parsing

    private func parseJSONLLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Extract session info
        if let sessionId = json["sessionId"] as? String {
            state.sessionId = sessionId
        }
        if let cwd = json["cwd"] as? String {
            state.cwd = cwd
        }
        if let gitBranch = json["gitBranch"] as? String {
            state.gitBranch = gitBranch
        }

        // Parse message content
        if let message = json["message"] as? [String: Any] {
            parseMessage(message)
        }

        // Parse tool use results
        if json["toolUseResult"] != nil {
            // Tool completed - could track timing here
        }
    }

    private func parseMessage(_ message: [String: Any]) {
        // Extract model
        if let model = message["model"] as? String {
            state.model = model
        }

        // Extract token usage
        if let usage = message["usage"] as? [String: Any] {
            state.tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? state.tokenUsage.inputTokens
            state.tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? state.tokenUsage.outputTokens
            state.tokenUsage.cacheReadInputTokens = usage["cache_read_input_tokens"] as? Int ?? state.tokenUsage.cacheReadInputTokens
            state.tokenUsage.cacheCreationInputTokens = usage["cache_creation_input_tokens"] as? Int ?? state.tokenUsage.cacheCreationInputTokens
        }

        // Extract message content
        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String {
                    switch type {
                    case "text":
                        if let text = item["text"] as? String {
                            // Get first line or first 100 chars as preview
                            let preview = text.components(separatedBy: .newlines).first ?? text
                            state.lastMessage = String(preview.prefix(100))
                            state.lastMessageTime = Date()
                        }

                    case "tool_use":
                        if let toolId = item["id"] as? String,
                           let toolName = item["name"] as? String {
                            // Parse TodoWrite tool to extract todos
                            if toolName == "TodoWrite",
                               let input = item["input"] as? [String: Any],
                               let todos = input["todos"] as? [[String: Any]] {
                                parseTodos(todos)
                            }

                            let tool = ToolExecution(
                                id: toolId,
                                toolName: toolName,
                                argument: extractToolArgument(from: item["input"]),
                                startTime: Date()
                            )
                            // Add to active tools
                            if !state.activeTools.contains(where: { $0.id == toolId }) {
                                state.activeTools.append(tool)
                            }
                        }

                    default:
                        break
                    }
                }
            }
        }

        // Check for tool_result in user messages to mark tools as complete
        if let role = message["role"] as? String, role == "user",
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "tool_result",
                   let toolUseId = item["tool_use_id"] as? String {
                    // Mark tool as complete
                    if let index = state.activeTools.firstIndex(where: { $0.id == toolUseId }) {
                        var tool = state.activeTools.remove(at: index)
                        tool.endTime = Date()
                        state.recentTools.insert(tool, at: 0)
                        // Keep only last 10 recent tools
                        if state.recentTools.count > 10 {
                            state.recentTools.removeLast()
                        }
                    }
                }
            }
        }
    }

    private func extractToolArgument(from input: Any?) -> String? {
        guard let input = input as? [String: Any] else { return nil }

        // Common argument names
        if let pattern = input["pattern"] as? String { return pattern }
        if let command = input["command"] as? String { return String(command.prefix(50)) }
        if let filePath = input["file_path"] as? String { return URL(fileURLWithPath: filePath).lastPathComponent }
        if let query = input["query"] as? String { return String(query.prefix(50)) }
        if let prompt = input["prompt"] as? String { return String(prompt.prefix(50)) }

        return nil
    }

    private func parseTodos(_ todosArray: [[String: Any]]) {
        var newTodos: [ClaudeTodoItem] = []

        for todoDict in todosArray {
            guard let content = todoDict["content"] as? String,
                  let statusStr = todoDict["status"] as? String else {
                continue
            }

            let status: ClaudeTodoItem.TodoStatus
            switch statusStr {
            case "pending":
                status = .pending
            case "in_progress":
                status = .inProgress
            case "completed":
                status = .completed
            default:
                status = .pending
            }

            newTodos.append(ClaudeTodoItem(content: content, status: status))
        }

        // Replace the entire todo list (TodoWrite always sends the complete list)
        state.todos = newTodos
    }

    // MARK: - Notifications

    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyAgentCompletion(agent: AgentInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Agent Completed"
        content.body = "\(agent.name): \(agent.description)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Daily Stats

    /// Load daily stats from ~/.claude/stats-cache.json
    func loadDailyStats() {
        let statsFile = claudeDir.appendingPathComponent("stats-cache.json")

        guard FileManager.default.fileExists(atPath: statsFile.path),
              let data = FileManager.default.contents(atPath: statsFile.path) else {
            print("[ClaudeCode] stats-cache.json not found")
            return
        }

        do {
            let cache = try JSONDecoder().decode(StatsCache.self, from: data)

            // Get today's date in the format used by the cache (YYYY-MM-DD)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())

            var stats = DailyStats()

            // Try to find today's activity first, otherwise get the most recent
            let sortedActivity = cache.dailyActivity?.sorted { $0.date > $1.date }
            if let todayActivity = sortedActivity?.first(where: { $0.date == today }) {
                stats.date = today
                stats.messageCount = todayActivity.messageCount ?? 0
                stats.toolCallCount = todayActivity.toolCallCount ?? 0
                stats.sessionCount = todayActivity.sessionCount ?? 0
            } else if let latestActivity = sortedActivity?.first {
                // Use most recent day's stats
                stats.date = latestActivity.date
                stats.messageCount = latestActivity.messageCount ?? 0
                stats.toolCallCount = latestActivity.toolCallCount ?? 0
                stats.sessionCount = latestActivity.sessionCount ?? 0
            }

            // Try to find today's token usage first, otherwise get the most recent
            let sortedTokens = cache.dailyModelTokens?.sorted { $0.date > $1.date }
            let targetDate = stats.date.isEmpty ? today : stats.date
            if let dayTokens = sortedTokens?.first(where: { $0.date == targetDate }),
               let tokensByModel = dayTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
            } else if let latestTokens = sortedTokens?.first,
                      let tokensByModel = latestTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
                if stats.date.isEmpty {
                    stats.date = latestTokens.date
                }
            }

            dailyStats = stats
            print("[ClaudeCode] Loaded daily stats for \(stats.date): \(stats.messageCount) msgs, \(stats.toolCallCount) tools, \(stats.tokensUsed) tokens")

        } catch {
            print("[ClaudeCode] Error parsing stats-cache.json: \(error)")
        }
    }
}
