// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rectmangle",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Rectmangle", path: "Sources/Rectmangle"),
    ]
)
