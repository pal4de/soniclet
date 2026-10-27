// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Soniclet",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Soniclet", targets: ["Soniclet"])],
    targets: [
        .executableTarget(name: "Soniclet", resources: [.process("Resources")])
    ]
)
