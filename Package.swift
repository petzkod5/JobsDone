// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JobsDone",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "JobsDone", targets: ["JobsDone"])],
    targets: [
        .executableTarget(name: "JobsDone", path: "Sources", swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]),
        .testTarget(name: "JobsDoneTests", dependencies: ["JobsDone"], path: "Tests", exclude: ["Native"],
                    swiftSettings: [.unsafeFlags(["-warnings-as-errors"])])
    ],
    swiftLanguageModes: [.v6]
)
