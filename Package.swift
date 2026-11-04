// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdaNote",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MeetingCore"),
        .executableTarget(name: "MeetingWindow", dependencies: ["MeetingCore"]),
        .testTarget(name: "MeetingCoreTests", dependencies: ["MeetingCore"])
    ]
)
