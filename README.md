# TM Unstuck

A tiny macOS menu bar app that shows what Time Machine is doing and clears it when it gets stuck.

Time Machine sometimes hangs on "Preparing backup…" or "Cleaning up…" for hours, or leaves the backup disk mounted after a backup that never finished. Fixing that usually means opening Terminal and running `tmutil` and `killall` as root. TM Unstuck puts those fixes in the menu bar.

## Why I built this

I ran into this after turning on automatic Time Machine backups to a NAS. I work with a lot of large video files, and Time Machine tried to back all of them up at once. It couldn't finish in the two hours my laptop was open. After that the backup was stuck: it never completed or recovered on its own. Meanwhile the local snapshot it had made for the backup kept taking up a lot of disk space on my Mac.

Getting out of that state meant digging through `tmutil` commands. This app makes the stuck state visible and lets you clear it, including deleting the leftover local snapshots, in a couple of clicks.

## Features

- **Live backup status:** current phase, percent, bytes copied, time running and time since the last progress. Polled every 10 seconds.
- **Stuck detection:** if a backup makes no progress for a set time (15 minutes by default, adjustable), the menu bar icon changes to a warning.
- **Stale disk detection:** lists Time Machine network shares, backup volumes and sparsebundle disk images that are still attached, and marks them stale when no backup is running.
- **One-click fix:** "Clear stuck backup" stops the backup, restarts `backupd` and force-ejects every Time Machine disk, all behind a single admin prompt.
- **Individual actions:** stop or start a backup, force-quit `backupd`, eject single disks.
- **Local snapshots:** list and delete local Time Machine APFS snapshots, one at a time or all at once.
- **Launch at login.**

Runs without a Dock icon and has no dependencies beyond macOS itself.

## Requirements

- macOS 14 Sonoma or later
- To build: Xcode 15+ or the Swift 5.10+ command-line tools

## Install

### Download

Get `TM-Unstuck.zip` from the [latest release](../../releases/latest), unzip it and move **TM Unstuck.app** to `/Applications` or `~/Applications`.

The app is ad-hoc signed, not notarized, so macOS blocks the first launch. Either right-click the app and choose **Open**, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/TM Unstuck.app"
```

### Build from source

```bash
git clone https://github.com/<you>/tm-unstuck.git
cd tm-unstuck
./build.sh --install   # builds build/TM Unstuck.app and copies it to ~/Applications
open ~/Applications/TM\ Unstuck.app
```

Without `--install` the app is only built into `build/`.

## How it works

TM Unstuck is a thin UI over Apple's own command-line tools:

| What | Command | Needs admin |
| --- | --- | --- |
| Backup status | `tmutil status -X` | no |
| Attached backup disks | `mount`, `hdiutil info -plist` | no |
| Local snapshots | `tmutil listlocalsnapshots /` | no |
| Start / stop backup | `tmutil startbackup` / `tmutil stopbackup` | no |
| Force-quit backupd | `killall backupd` (then `-9` if needed) | yes |
| Eject disks | `diskutil unmount force`, `hdiutil detach -force` | yes |
| Delete snapshots | `tmutil deletelocalsnapshots <date \| />` | yes |

Admin actions run through `osascript … with administrator privileges`, so you get the standard macOS password prompt each time. Nothing is installed as a privileged helper, and the app never stores your password.

`backupd` is managed by launchd, so killing it is safe: launchd restarts it right away and Time Machine retries on its normal schedule.

## Caveats

- Force-ejecting a backup disk *during* an active backup can interrupt that backup. The app tells you to stop the backup first, and "Clear stuck backup" always stops it before ejecting.
- Deleting local snapshots frees disk space but removes those restore points.
- Phase names come from `backupd`'s private status output and may change between macOS releases. Unknown phases are shown as-is.

## Project layout

```
Sources/TMUnstuck/
  TMUnstuckApp.swift   App entry point (MenuBarExtra)
  MenuView.swift       The menu panel UI
  TMMonitor.swift      Polling, stuck detection and actions
  Models.swift         Parsers for tmutil, mount and hdiutil output
  Shell.swift          Process and admin-prompt helpers
build.sh               Builds and bundles the .app
```

## Contributing

Issues and pull requests are welcome. If a backup phase shows up with an odd name, please open an issue with the output of `tmutil status -X` from that moment.

## License

[MIT](LICENSE)
