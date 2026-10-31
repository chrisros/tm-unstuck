import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var monitor: TMMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            backupSection
            if !monitor.mounts.isEmpty {
                Divider()
                mountsSection
            }
            Divider()
            snapshotsSection
            if monitor.needsAttention {
                Button {
                    monitor.fixEverything()
                } label: {
                    Label("Clear stuck backup", systemImage: "wrench.and.screwdriver")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .help("Stops the backup, restarts backupd and ejects all Time Machine disks (one admin prompt)")
            }
            if let text = monitor.working ?? monitor.message {
                HStack(spacing: 6) {
                    if monitor.working != nil { ProgressView().controlSize(.small) }
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .disabled(monitor.working != nil)
        .task { await monitor.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Time Machine").font(.headline)
            Spacer()
            Button {
                Task { await monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
    }

    // MARK: Backup

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(monitor.isStuck ? Color.orange : monitor.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(statusTitle).font(.body.weight(.medium))
                Spacer()
            }
            if let progress = monitor.status?.percent, monitor.isRunning {
                ProgressView(value: min(max(progress, 0), 1))
            }
            if let detail = statusDetail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if monitor.isStuck {
                Label("No progress for \(duration(monitor.stalledFor)) — looks stuck", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                if monitor.isRunning {
                    Button("Stop backup") { monitor.stopBackup() }
                } else {
                    Button("Back up now") { monitor.startBackup() }
                }
                Button("Force-quit backupd") { monitor.forceQuitBackupd() }
                    .help("Kills backupd as root; launchd restarts it immediately")
            }
            .controlSize(.small)
        }
    }

    private var statusTitle: String {
        guard let status = monitor.status else { return "Checking…" }
        guard status.running else { return "Idle" }
        if let pct = status.percent { return "\(status.phaseDescription) · \(Int(pct * 100))%" }
        return status.phaseDescription
    }

    private var statusDetail: String? {
        guard let status = monitor.status, status.running else { return nil }
        var parts: [String] = []
        if let since = monitor.runningSince { parts.append("running \(duration(Date().timeIntervalSince(since)))") }
        if let bytes = status.bytes {
            let copied = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            if let total = status.totalBytes, total > 0 {
                parts.append("\(copied) of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
            } else {
                parts.append(copied)
            }
        }
        if let remaining = status.timeRemaining, remaining > 0 { parts.append("~\(duration(remaining)) left") }
        parts.append("last progress \(duration(monitor.stalledFor)) ago")
        return parts.joined(separator: " · ")
    }

    // MARK: Mounts

    private var mountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Attached backup disks").font(.subheadline.weight(.medium))
                if monitor.hasStaleMounts {
                    Text("stale").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
                Button("Eject all") { monitor.eject(monitor.mounts) }
                    .controlSize(.small)
            }
            ForEach(monitor.mounts) { mount in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mount.title).lineLimit(1).truncationMode(.middle)
                        Text(mount.kindLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        monitor.eject([mount])
                    } label: {
                        Image(systemName: "eject")
                    }
                    .buttonStyle(.borderless)
                    .help("Force eject \(mount.mountPoint ?? mount.device)")
                }
            }
            if monitor.isRunning {
                Text("A backup is running — stop it before ejecting.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Snapshots

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Local snapshots (\(monitor.snapshots.count))").font(.subheadline.weight(.medium))
                Spacer()
                if !monitor.snapshots.isEmpty {
                    Button("Delete all") { monitor.deleteAllSnapshots() }
                        .controlSize(.small)
                }
            }
            if monitor.snapshots.isEmpty {
                Text("None").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(monitor.snapshots) { snapshot in
                            HStack {
                                Text(snapshot.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? snapshot.dateString)
                                    .font(.callout.monospacedDigit())
                                Spacer()
                                Button {
                                    monitor.delete(snapshot)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete \(snapshot.name)")
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Stuck after \(monitor.stuckMinutes) min without progress", value: $monitor.stuckMinutes, in: 5...240, step: 5)
                .font(.caption)
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { monitor.launchAtLogin },
                    set: { monitor.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }
}

private func duration(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute] : [.second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: max(seconds, 0)) ?? "\(Int(seconds))s"
}
