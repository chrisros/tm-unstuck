// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TMUnstuck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TMUnstuck", path: "Sources/TMUnstuck")
    ]
)
