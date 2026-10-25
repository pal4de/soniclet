// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SoundSwitch",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SoundSwitch", targets: ["SoundSwitch"])],
    targets: [
        .executableTarget(name: "SoundSwitch", resources: [.process("Resources")])
    ]
)
