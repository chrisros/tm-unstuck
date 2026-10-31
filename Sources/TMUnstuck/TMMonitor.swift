import Foundation
import ServiceManagement

@MainActor
final class TMMonitor: ObservableObject {
    @Published private(set) var status: BackupStatus?
    @Published private(set) var runningSince: Date?
    @Published private(set) var lastProgressAt = Date()
    @Published private(set) var mounts: [TMMount] = []
    @Published private(set) var snapshots: [LocalSnapshot] = []
    @Published private(set) var working: String?
    @Published var message: String?
    @Published var stuckMinutes: Int {
        didSet { UserDefaults.standard.set(stuckMinutes, forKey: "stuckMinutes") }
    }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private var fingerprint: String?
    private var refreshing = false
    private var timer: Timer?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "stuckMinutes")
        stuckMinutes = saved > 0 ? saved : 15
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    // MARK: - Derived state

    var isRunning: Bool { status?.running ?? false }

    var stalledFor: TimeInterval { Date().timeIntervalSince(lastProgressAt) }

    var isStuck: Bool { isRunning && stalledFor > Double(stuckMinutes * 60) }

    /// Backup disks left attached while no backup is running.
    var hasStaleMounts: Bool { !isRunning && !mounts.isEmpty }

    var needsAttention: Bool { isStuck || hasStaleMounts }

    var menuBarSymbol: String {
        if needsAttention { return "exclamationmark.triangle" }
        if isRunning { return "arrow.triangle.2.circlepath" }
        return "clock.arrow.circlepath"
    }

    // MARK: - Polling

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        async let statusResult = Shell.run("/usr/bin/tmutil", ["status", "-X"])
        async let mountResult = Shell.run("/sbin/mount")
        async let imageResult = Shell.run("/usr/bin/hdiutil", ["info", "-plist"])
        async let snapshotResult = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])

        let statusText = await statusResult.output
        if let data = statusText.data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            apply(BackupStatus(plist: plist))
        }

        mounts = TMMount.parseMountTable(await mountResult.output) + TMMount.parseDiskImages(await imageResult.output)
        snapshots = LocalSnapshot.parse(await snapshotResult.output)
    }

    private func apply(_ new: BackupStatus) {
        let now = Date()
        if new.running && runningSince == nil {
            // First sighting (e.g. right after app launch): trust backupd's own timestamp if it has one.
            runningSince = new.stateChangedAt ?? now
            lastProgressAt = new.stateChangedAt ?? now
        } else if !new.running {
            runningSince = nil
            lastProgressAt = now
        } else if new.fingerprint != fingerprint {
            lastProgressAt = now
        }
        fingerprint = new.fingerprint
        status = new
    }

    // MARK: - Actions

    func startBackup() {
        perform("Starting backup…", success: "Backup requested.") {
            await Shell.run("/usr/bin/tmutil", ["startbackup"])
        }
    }

    func stopBackup() {
        perform("Stopping backup…", success: "Stop requested. backupd may take a minute to wind down.") {
            await Shell.run("/usr/bin/tmutil", ["stopbackup"])
        }
    }

    func forceQuitBackupd() {
        perform("Force-quitting backupd…", success: "backupd restarted. launchd brings it back automatically.") {
            await Shell.runAsAdmin(Self.killScript)
        }
    }

    func eject(_ targets: [TMMount]) {
        let script = Self.ejectScript(targets)
        perform("Ejecting…", success: "Ejected \(targets.count) item\(targets.count == 1 ? "" : "s").") {
            await Shell.runAsAdmin(script)
        }
    }

    /// Stops the backup, restarts backupd and detaches every Time Machine disk in a single admin prompt.
    func fixEverything() {
        let script = [Self.killScript, Self.ejectScript(mounts)].filter { !$0.isEmpty }.joined(separator: "; ")
        perform("Clearing stuck backup…", success: "Cleared. Time Machine will retry on its next schedule.") {
            await Shell.runAsAdmin(script)
        }
    }

    func delete(_ snapshot: LocalSnapshot) {
        perform("Deleting snapshot…", success: "Deleted snapshot \(snapshot.dateString).") {
            await Shell.runAsAdmin("/usr/bin/tmutil deletelocalsnapshots \(snapshot.dateString)")
        }
    }

    func deleteAllSnapshots() {
        perform("Deleting all snapshots…", success: "Deleted all local snapshots.") {
            await Shell.runAsAdmin("/usr/bin/tmutil deletelocalsnapshots /")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static let killScript =
        "/usr/bin/tmutil stopbackup; /usr/bin/killall backupd; sleep 3; /usr/bin/killall -9 backupd 2>/dev/null; true"

    private static func ejectScript(_ targets: [TMMount]) -> String {
        // Innermost first: backup volumes, then their disk images, then the network share holding them.
        targets.sorted { $0.kind.rawValue < $1.kind.rawValue }
            .map { "\($0.ejectCommand) 2>&1" }
            .joined(separator: "; ")
    }

    private func perform(_ label: String, success: String, _ command: @escaping () async -> CommandResult) {
        guard working == nil else { return }
        working = label
        message = nil
        Task {
            let r = await command()
            if r.ok {
                message = success
            } else if !r.cancelled {
                let detail = (r.error.isEmpty ? r.output : r.error).trimmingCharacters(in: .whitespacesAndNewlines)
                message = "Failed: \(detail.isEmpty ? "exit \(r.status)" : detail)"
            }
            working = nil
            await refresh()
        }
    }
}
