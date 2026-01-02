//
//  ClaudeCodeStatsView.swift
//  boringNotch
//
//  Expanded view showing full Claude Code stats panel
//

import SwiftUI

struct ClaudeCodeStatsView: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with session picker - always visible
            HStack {
                SessionPicker(manager: manager)
                Spacer()
                if manager.state.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Connected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if manager.state.isConnected {
                // Model and branch info
                HStack(spacing: 8) {
                    if !manager.state.model.isEmpty {
                        Label(modelDisplayName, systemImage: "brain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !manager.state.gitBranch.isEmpty {
                        Label(manager.state.gitBranch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Context usage section - always visible
                ContextBarWithLabel(
                    percentage: manager.state.contextPercentage,
                    tokensUsed: manager.state.tokenUsage.totalTokens,
                    tokensTotal: TokenUsage.contextWindow
                )

                // Two-column layout: Active/Recent tools on left, Last output on right
                HStack(alignment: .top, spacing: 16) {
                    // Left column: Tools
                    VStack(alignment: .leading, spacing: 8) {
                        // Active tools (limit to 2)
                        if !manager.state.activeTools.isEmpty {
                            ActiveToolsSectionCompact(tools: Array(manager.state.activeTools.prefix(2)))
                        }

                        // Recent tools (limit to 3)
                        if !manager.state.recentTools.isEmpty {
                            RecentToolsSectionCompact(tools: Array(manager.state.recentTools.prefix(3)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right column: Last output
                    if !manager.state.lastMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Output")
                                .font(.caption.weight(.medium))
                            Text(manager.state.lastMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

            } else {
                // Not connected state
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No Claude Code session selected")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if manager.availableSessions.isEmpty {
                        Text("Start Claude Code in a terminal to begin monitoring")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    private var modelDisplayName: String {
        if manager.state.model.contains("opus") {
            return "Opus 4.5"
        } else if manager.state.model.contains("sonnet") {
            return "Sonnet 4"
        } else if manager.state.model.contains("haiku") {
            return "Haiku"
        }
        return "Claude"
    }
}

struct ActiveToolsSection: View {
    let tools: [ToolExecution]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Active Tools")
                    .font(.caption.weight(.medium))
                Text("(\(tools.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(tools) { tool in
                HStack(spacing: 6) {
                    ToolActivityIndicator(isActive: true, toolName: tool.toolName)
                        .scaleEffect(0.8)

                    Text(tool.toolName)
                        .font(.caption)

                    if let arg = tool.argument {
                        Text(arg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// Compact version for two-column layout
struct ActiveToolsSectionCompact: View {
    let tools: [ToolExecution]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)

            ForEach(tools) { tool in
                HStack(spacing: 4) {
                    ToolActivityIndicator(isActive: true, toolName: tool.toolName)
                        .scaleEffect(0.6)

                    Text(tool.toolName)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct RecentToolsSection: View {
    let tools: [ToolExecution]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Tools")
                .font(.caption.weight(.medium))

            ForEach(tools.prefix(5)) { tool in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)

                    Text(tool.toolName)
                        .font(.caption)

                    if let arg = tool.argument {
                        Text(arg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let duration = tool.durationMs {
                        Text("\(duration)ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// Compact version for two-column layout
struct RecentToolsSectionCompact: View {
    let tools: [ToolExecution]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)

            ForEach(tools) { tool in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green)

                    Text(tool.toolName)
                        .font(.caption2)

                    if let arg = tool.argument {
                        Text(arg)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct LastMessageSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Output")
                .font(.caption.weight(.medium))

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
    }
}

#Preview {
    ClaudeCodeStatsView()
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .padding()
}
