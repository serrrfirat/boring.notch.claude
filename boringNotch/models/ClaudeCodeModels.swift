//
//  ClaudeCodeModels.swift
//  boringNotch
//
//  Created for Claude Code Notch integration
//

import Foundation

// MARK: - Session Discovery

/// Represents an active Claude Code IDE session from ~/.claude/ide/*.lock
struct ClaudeSession: Identifiable, Codable, Equatable {
    // Use workspace path as unique ID since multiple sessions can share the same PID (Cursor)
    var id: String { workspaceFolders.first ?? "\(pid)" }

    let pid: Int
    let workspaceFolders: [String]
    let ideName: String
    let transport: String?
    let runningInWindows: Bool?

    /// Derived from workspace path for project JSONL lookup
    var projectKey: String? {
        guard let workspace = workspaceFolders.first else { return nil }
        // Convert /Users/foo/bar.baz to -Users-foo-bar-baz
        // Claude Code keeps the leading dash, so we only trim trailing dashes
        return workspace
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Display name for UI (last folder component)
    var displayName: String {
        guard let workspace = workspaceFolders.first else { return "Unknown" }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }
}

// MARK: - Token Usage

/// Token usage data from JSONL message.usage field
struct TokenUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    /// Context window is 200k for opus-4-5
    static let contextWindow = 200_000

    var contextPercentage: Double {
        guard Self.contextWindow > 0 else { return 0 }
        return min(100, Double(totalTokens) / Double(Self.contextWindow) * 100)
    }
}

// MARK: - Tool Execution

/// Represents a tool call in progress or completed
struct ToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let argument: String?
    let startTime: Date
    var endTime: Date?
    var isRunning: Bool { endTime == nil }

    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }
}

// MARK: - Agent Info

/// Represents a background agent task
struct AgentInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let startTime: Date
    var isActive: Bool = true

    var durationSeconds: Int {
        Int(Date().timeIntervalSince(startTime))
    }
}

// MARK: - Todo Item

/// Claude Code todo item
struct ClaudeTodoItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: TodoStatus

    enum TodoStatus: String {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

// MARK: - Complete State

/// Complete Claude Code state for display
struct ClaudeCodeState: Equatable {
    var sessionId: String = ""
    var model: String = ""
    var cwd: String = ""
    var gitBranch: String = ""

    var tokenUsage: TokenUsage = TokenUsage()

    var lastMessage: String = ""
    var lastMessageTime: Date?

    var activeTools: [ToolExecution] = []
    var recentTools: [ToolExecution] = []

    var agents: [AgentInfo] = []
    var todos: [ClaudeTodoItem] = []

    var isConnected: Bool = false
    var lastUpdateTime: Date?

    // Convenience accessors
    var contextPercentage: Double { tokenUsage.contextPercentage }
    var hasActiveTools: Bool { !activeTools.isEmpty }
    var currentToolName: String? { activeTools.first?.toolName }
}

// MARK: - JSONL Parsing Helpers

/// Represents a parsed JSONL line from session log
struct SessionLogEntry {
    let type: String
    let sessionId: String?
    let model: String?
    let cwd: String?
    let gitBranch: String?
    let usage: TokenUsage?
    let messageContent: String?
    let toolUse: ToolUseInfo?
    let toolResult: ToolResultInfo?
    let timestamp: Date?
}

struct ToolUseInfo {
    let id: String
    let name: String
    let input: [String: Any]?
}

struct ToolResultInfo {
    let toolUseId: String
    let content: String?
    let isError: Bool
}
