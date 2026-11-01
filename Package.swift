// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ECGMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ECGMenu", path: "Sources/ECGMenu")
    ]
)
