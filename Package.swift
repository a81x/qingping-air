// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "QingpingAir", platforms: [.macOS(.v14)],
    products: [.executable(name: "QingpingAir", targets: ["QingpingAir"])],
    targets: [
        .target(name: "AirCore"),
        .executableTarget(name: "QingpingAir", dependencies: ["AirCore"]),
        .executableTarget(name: "AirCoreChecks", dependencies: ["AirCore"], path: "Tests/AirCoreTests")
    ]
)
