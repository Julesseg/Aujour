// swift-tools-version: 6.0
import PackageDescription

// AujourCore is the platform-agnostic heart of the app: all business logic
// lives here. It depends on nothing but the standard library + Foundation,
// so its behavior is unit-tested with `swift test` on any platform — no
// Xcode or simulator required. The iOS app target in App/ is a thin UI
// layer on top.
let package = Package(
    name: "AujourCore",
    products: [
        .library(name: "AujourCore", targets: ["AujourCore"]),
    ],
    targets: [
        .target(name: "AujourCore"),
        .testTarget(
            name: "AujourCoreTests",
            dependencies: ["AujourCore"]
        ),
    ]
)
