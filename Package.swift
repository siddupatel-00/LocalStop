// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LocalStop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LocalStop",
            path: "Sources/LocalStop"
        )
    ]
)
