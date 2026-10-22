// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftDefaultApps",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DefaultAppsCore", path: "Sources/DefaultAppsCore"),
        .executableTarget(name: "swda", dependencies: ["DefaultAppsCore"], path: "Sources/swda"),
        .executableTarget(name: "SwiftDefaultApps", dependencies: ["DefaultAppsCore"], path: "Sources/SwiftDefaultApps"),
    ]
)
