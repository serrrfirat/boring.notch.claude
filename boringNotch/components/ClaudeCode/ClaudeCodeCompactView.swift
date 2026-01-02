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
            // Permission indicator (pulsing orange) or activity indicator
            if manager.state.needsPermission {
                PermissionNeededIndicator(toolName: manager.state.pendingPermissionTool)
            } else {
                ToolActivityIndicator(
                    isActive: manager.state.hasActiveTools,
                    toolName: manager.state.currentToolName
                )
            }

            // Last message preview
            if manager.state.needsPermission {
                Text("Approval needed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            } else if !manager.state.lastMessage.isEmpty {
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

/// Pulsing indicator shown when Claude is waiting for user permission
struct PermissionNeededIndicator: View {
    let toolName: String?
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                .frame(width: 16, height: 16)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.8)

            // Inner solid circle
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)

            // Exclamation mark
            Image(systemName: "exclamationmark")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

struct ClaudeCodeCompactViewMinimal: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            // Permission indicator or activity dots
            if manager.state.needsPermission {
                PermissionNeededIndicatorCompact()
            } else {
                ToolActivityIndicatorCompact(isActive: manager.state.hasActiveTools)
            }

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

/// Compact pulsing dot for minimal view
struct PermissionNeededIndicatorCompact: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.2 : 0.9)
            .opacity(isPulsing ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
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

        // Preview permission indicator
        PermissionNeededIndicator(toolName: "Bash")
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
    }
    .padding()
}
