//
//  ClaudeCodeCompactView.swift
//  boringNotch
//
//  Compact view shown in the closed notch state
//  Shows: tool activity indicator, last message preview, context bar
//

import SwiftUI

struct ClaudeCodeCompactView: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            // Activity indicator
            ToolActivityIndicator(
                isActive: manager.state.hasActiveTools,
                toolName: manager.state.currentToolName
            )

            // Last message preview
            if !manager.state.lastMessage.isEmpty {
                Text(manager.state.lastMessage)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary.opacity(0.9))
            } else if manager.state.isConnected {
                Text("Waiting for activity...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Not connected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Context usage bar
            if manager.state.isConnected {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(manager.state.contextPercentage))%")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundColor(.secondary)

                    ContextBar(
                        percentage: manager.state.contextPercentage,
                        width: 50,
                        height: 4
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}

struct ClaudeCodeCompactViewMinimal: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            // Simple activity dots
            ToolActivityIndicatorCompact(isActive: manager.state.hasActiveTools)

            // Model badge
            if !manager.state.model.isEmpty {
                Text(modelShortName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
            }

            // Context percentage
            Text("\(Int(manager.state.contextPercentage))%")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(contextColor)
        }
    }

    private var modelShortName: String {
        if manager.state.model.contains("opus") {
            return "opus"
        } else if manager.state.model.contains("sonnet") {
            return "sonnet"
        } else if manager.state.model.contains("haiku") {
            return "haiku"
        }
        return "claude"
    }

    private var contextColor: Color {
        let pct = manager.state.contextPercentage
        if pct > 90 { return .red }
        if pct > 75 { return .orange }
        return .green
    }
}

#Preview {
    VStack(spacing: 20) {
        ClaudeCodeCompactView()
            .frame(width: 300)
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)

        ClaudeCodeCompactViewMinimal()
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
    }
    .padding()
}
