// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceChessCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VoiceChessCore", targets: ["VoiceChessCore"]),
    ],
    targets: [
        .target(name: "VoiceChessCore"),
        .testTarget(name: "VoiceChessCoreTests", dependencies: ["VoiceChessCore"]),
    ]
)
