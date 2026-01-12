//
//  ClaudeUsageIndicator.swift
//  boringNotch
//
//  Displays Claude API usage quota in the notch
//

import SwiftUI
import Defaults

// MARK: - Compact Usage Indicator (for closed notch)

/// Small usage bar shown alongside Claude Code status in closed notch
struct ClaudeUsageCompactIndicator: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared
    @Default(.showClaudeUsageInClosedNotch) var showInClosedNotch

    var body: some View {
        if showInClosedNotch, usageManager.isConfigured, let fiveHour = usageManager.usageData.fiveHour {
            HStack(spacing: 4) {
                // Percentage text
                Text(fiveHour.formattedPercentage)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(colorForLevel(fiveHour.usageLevel))

                // Mini progress bar
                UsageMiniBar(percentage: fiveHour.percentage)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.4))
            .clipShape(Capsule())
        }
    }

    private func colorForLevel(_ level: UsageLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

/// Tiny progress bar for closed notch
struct UsageMiniBar: View {
    let percentage: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.2))

                // Fill
                Capsule()
                    .fill(fillColor)
                    .frame(width: geometry.size.width * CGFloat(min(percentage, 100) / 100))
            }
        }
        .frame(width: 30, height: 4)
    }

    private var fillColor: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - Expanded Usage View (for open notch / stats view)

/// Full usage display for the expanded notch view
struct ClaudeUsageExpandedView: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.secondary)
                Text("API Usage")
                    .font(.headline)

                Spacer()

                // Refresh button
                Button(action: {
                    Task {
                        await usageManager.manualRefresh()
                    }
                }) {
                    Image(systemName: usageManager.isLoading ? "arrow.trianglehead.2.clockwise" : "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(usageManager.isLoading ? 360 : 0))
                        .animation(usageManager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: usageManager.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(usageManager.isLoading)
            }

            if !usageManager.isConfigured {
                // Not configured state
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Session key required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Configure in Settings → Claude Code")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if let error = usageManager.lastError {
                // Error state
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                // Usage bars
                VStack(spacing: 10) {
                    // 5-hour limit (always shown)
                    if let fiveHour = usageManager.usageData.fiveHour {
                        UsageBarRow(
                            label: "5 Hour",
                            data: fiveHour,
                            icon: "clock"
                        )
                    }

                    // 7-day limit
                    if let sevenDay = usageManager.usageData.sevenDay {
                        UsageBarRow(
                            label: "7 Day",
                            data: sevenDay,
                            icon: "calendar"
                        )
                    }

                    // Opus limit
                    if let opus = usageManager.usageData.opus {
                        UsageBarRow(
                            label: "Opus",
                            data: opus,
                            icon: "sparkles"
                        )
                    }

                    // Sonnet limit
                    if let sonnet = usageManager.usageData.sonnet {
                        UsageBarRow(
                            label: "Sonnet",
                            data: sonnet,
                            icon: "wand.and.stars"
                        )
                    }

                    // Extra usage (paid)
                    if let extra = usageManager.usageData.extraUsage, extra.enabled {
                        ExtraUsageRow(data: extra)
                    }
                }

                // Last updated
                Text("Updated \(usageManager.usageData.fetchedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

/// Single usage bar row
struct UsageBarRow: View {
    let label: String
    let data: ClaudeUsageData.LimitData
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(data.formattedPercentage)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(colorForLevel(data.usageLevel))

                if data.resetsAt != nil {
                    Text("• \(data.formattedRemaining)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForLevel(data.usageLevel))
                        .frame(width: geometry.size.width * CGFloat(min(data.percentage, 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }

    private func colorForLevel(_ level: UsageLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

/// Extra usage (paid) row
struct ExtraUsageRow: View {
    let data: ClaudeUsageData.ExtraUsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("Extra Usage")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(data.formattedUsed) / \(data.formattedLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.purple)
            }

            if let percentage = data.percentage {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple)
                            .frame(width: geometry.size.width * CGFloat(min(percentage, 100) / 100))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: - Settings Section

/// Settings view for configuring Claude Usage
struct ClaudeUsageSettingsView: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared
    @Default(.enableClaudeUsage) var enableUsage
    @Default(.claudeUsageRefreshMode) var refreshMode
    @Default(.claudeUsageRefreshInterval) var refreshInterval
    @Default(.showClaudeUsageInClosedNotch) var showInClosedNotch

    @State private var sessionKeyInput: String = ""
    @State private var showSessionKey: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Usage Tracking", isOn: $enableUsage)
                    .onChange(of: enableUsage) { _, newValue in
                        if newValue && usageManager.isConfigured {
                            usageManager.startRefreshing()
                        } else {
                            usageManager.stopRefreshing()
                        }
                    }
            }

            if enableUsage {
                Section("Session Key") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if showSessionKey {
                                TextField("sk-ant-...", text: $sessionKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("sk-ant-...", text: $sessionKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showSessionKey.toggle() }) {
                                Image(systemName: showSessionKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack {
                            Button("Save") {
                                if usageManager.isValidSessionKey(sessionKeyInput) {
                                    usageManager.sessionKey = sessionKeyInput
                                    usageManager.startRefreshing()
                                }
                            }
                            .disabled(!usageManager.isValidSessionKey(sessionKeyInput))

                            if usageManager.isConfigured {
                                Button("Clear", role: .destructive) {
                                    usageManager.clearCredentials()
                                    sessionKeyInput = ""
                                }
                            }
                        }

                        Text("Get your session key from claude.ai cookies (DevTools → Application → Cookies → sessionKey)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    sessionKeyInput = usageManager.sessionKey ?? ""
                }

                Section("Refresh") {
                    Picker("Mode", selection: $refreshMode) {
                        ForEach(UsageRefreshMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    if refreshMode == .fixed {
                        Picker("Interval", selection: $refreshInterval) {
                            ForEach(UsageRefreshInterval.allCases) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                    } else {
                        HStack {
                            Text("Current Mode")
                            Spacer()
                            Text(usageManager.currentMonitoringMode.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Display") {
                    Toggle("Show in Closed Notch", isOn: $showInClosedNotch)
                }

                Section("Status") {
                    HStack {
                        Text("Configured")
                        Spacer()
                        Image(systemName: usageManager.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(usageManager.isConfigured ? .green : .red)
                    }

                    if let error = usageManager.lastError {
                        HStack {
                            Text("Error")
                            Spacer()
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compact Stats (for Claude Code Stats View)

/// Simplified usage display for embedding in Claude Code stats
struct ClaudeUsageCompactStats: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("API Usage")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                // Refresh button
                Button(action: {
                    Task { await usageManager.manualRefresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(usageManager.isLoading ? 360 : 0))
                        .animation(usageManager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: usageManager.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(usageManager.isLoading)
            }

            if let error = usageManager.lastError {
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(.red)
            } else {
                // 5-hour bar (primary)
                if let fiveHour = usageManager.usageData.fiveHour {
                    HStack(spacing: 6) {
                        Text("5hr")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.1))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForLevel(fiveHour.usageLevel))
                                    .frame(width: max(0, geo.size.width * CGFloat(min(fiveHour.percentage, 100) / 100)))
                            }
                        }
                        .frame(height: 6)

                        Text(fiveHour.formattedPercentage)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(colorForLevel(fiveHour.usageLevel))
                            .frame(width: 32, alignment: .trailing)

                        if fiveHour.resetsAt != nil {
                            Text(fiveHour.formattedRemaining)
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                // 7-day bar (if available)
                if let sevenDay = usageManager.usageData.sevenDay {
                    HStack(spacing: 6) {
                        Text("7d")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.1))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.purple)
                                    .frame(width: max(0, geo.size.width * CGFloat(min(sevenDay.percentage, 100) / 100)))
                            }
                        }
                        .frame(height: 6)

                        Text(sevenDay.formattedPercentage)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.purple)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func colorForLevel(_ level: UsageLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Previews

#Preview("Compact Indicator") {
    HStack {
        ClaudeUsageCompactIndicator()
    }
    .padding()
    .background(Color.black)
}

#Preview("Expanded View") {
    ClaudeUsageExpandedView()
        .frame(width: 300)
        .padding()
        .background(Color.gray.opacity(0.2))
}

#Preview("Settings") {
    ClaudeUsageSettingsView()
        .frame(width: 400, height: 500)
}
