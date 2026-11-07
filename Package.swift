// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JobsDone",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "JobsDone", targets: ["JobsDone"])],
    targets: [
        .executableTarget(name: "JobsDone", path: "Sources"),
        .testTarget(name: "JobsDoneTests", dependencies: ["JobsDone"], path: "Tests", exclude: ["Native"])
    ],
    swiftLanguageModes: [.v5]
)
