import Foundation

struct BackupStatus {
    var running: Bool
    var phase: String?
    var percent: Double?
    var bytes: Double?
    var totalBytes: Double?
    var files: Double?
    var timeRemaining: Double?
    var stateChangedAt: Date?

    init(plist: [String: Any]) {
        let progress = plist["Progress"] as? [String: Any] ?? [:]
        running = (plist["Running"] as? NSNumber)?.boolValue ?? false
        phase = plist["BackupPhase"] as? String
        let pct = number(progress["Percent"]) ?? number(plist["Percent"])
        percent = (pct ?? -1) >= 0 ? pct : nil
        bytes = number(progress["bytes"])
        totalBytes = number(progress["totalBytes"])
        files = number(progress["files"])
        timeRemaining = number(progress["TimeRemaining"])
        if let raw = plist["DateOfStateChange"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            stateChangedAt = formatter.date(from: raw)
        } else {
            stateChangedAt = plist["DateOfStateChange"] as? Date
        }
    }

    /// Changes whenever backupd reports any forward motion.
    var fingerprint: String {
        "\(running)|\(phase ?? "")|\(percent ?? -1)|\(bytes ?? -1)|\(files ?? -1)"
    }

    var phaseDescription: String {
        switch phase {
        case nil: return running ? "Running" : "Idle"
        case "Starting": return "Starting"
        case "PreparingSourceVolumes", "Preparing": return "Preparing"
        case "FindingBackupVol": return "Looking for backup disk"
        case "MountingBackupVol", "MountingBackupVolForHealthCheck", "MountingDiskImage": return "Mounting backup disk"
        case "FindingChanges": return "Scanning for changes"
        case "Copying": return "Copying"
        case "ThinningPreBackup", "ThinningPostBackup", "LazyThinning", "DeletingOldBackups": return "Cleaning up old backups"
        case "HealthCheckFsck", "HealthCheckCopyHFSMeta": return "Verifying backups"
        case "Finishing": return "Finishing"
        case "Stopping": return "Stopping"
        case let other?:
            return other.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
    }
}

private func number(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String { return Double(s) }
    return nil
}

/// A Time Machine share, backup volume or disk image that is currently attached.
struct TMMount: Identifiable, Hashable {
    enum Kind: Int { case volume, diskImage, share }

    let kind: Kind
    let device: String
    let mountPoint: String?

    var id: String { "\(kind.rawValue)|\(device)|\(mountPoint ?? "")" }

    var title: String {
        if let mountPoint { return (mountPoint as NSString).lastPathComponent }
        return (device as NSString).lastPathComponent
    }

    var kindLabel: String {
        switch kind {
        case .volume: return "Backup volume"
        case .diskImage: return "Disk image"
        case .share: return "Network share"
        }
    }

    var ejectCommand: String {
        switch kind {
        case .diskImage: return "/usr/bin/hdiutil detach -force \(Shell.quote(device))"
        case .volume, .share: return "/usr/sbin/diskutil unmount force \(Shell.quote(mountPoint ?? device))"
        }
    }

    static func parseMountTable(_ text: String) -> [TMMount] {
        let pattern = try! NSRegularExpression(pattern: #"^(.+) on (.+) \(([^,)]+)"#)
        return text.split(separator: "\n").compactMap { line in
            let line = String(line)
            guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let dev = Range(match.range(at: 1), in: line),
                  let path = Range(match.range(at: 2), in: line),
                  let fs = Range(match.range(at: 3), in: line) else { return nil }
            let mountPoint = String(line[path])
            guard mountPoint.contains("/.timemachine/")
                    || mountPoint.hasPrefix("/Volumes/Backups of ")
                    || mountPoint.hasPrefix("/Volumes/com.apple.TimeMachine.") else { return nil }
            let isShare = ["smbfs", "afpfs", "nfs"].contains(String(line[fs]))
            return TMMount(kind: isShare ? .share : .volume, device: String(line[dev]), mountPoint: mountPoint)
        }
    }

    static func parseDiskImages(_ text: String) -> [TMMount] {
        guard let data = text.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [] }
        return images.compactMap { image in
            guard let path = image["image-path"] as? String,
                  path.hasSuffix(".sparsebundle") || path.hasSuffix(".backupbundle") || path.hasSuffix(".sparsebundle/") else { return nil }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let devices = entities.compactMap { $0["dev-entry"] as? String }
            guard let device = devices.min(by: { $0.count < $1.count }) else { return nil }
            return TMMount(kind: .diskImage, device: device, mountPoint: path)
        }
    }
}

struct LocalSnapshot: Identifiable, Hashable {
    let name: String
    let dateString: String
    let date: Date?

    var id: String { name }

    static func parse(_ text: String) -> [LocalSnapshot] {
        let pattern = try! NSRegularExpression(pattern: #"com\.apple\.TimeMachine\.(\d{4}-\d{2}-\d{2}-\d{6})\.local"#)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text), let date = Range(match.range(at: 1), in: text) else { return nil }
            let dateString = String(text[date])
            return LocalSnapshot(name: String(text[whole]), dateString: dateString, date: formatter.date(from: dateString))
        }
        .sorted { $0.dateString > $1.dateString }
    }
}
