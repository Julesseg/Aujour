// swift-tools-version: 6.0
import PackageDescription

// AujourCore is the platform-agnostic heart of the app: all business logic
// lives here. It depends on nothing but the standard library + Foundation,
// so its behavior is unit-tested with `swift test` on any platform — no
// Xcode or simulator required. The iOS app target in App/ is a thin UI
// layer on top.
let package = Package(
    name: "AujourCore",
    // Stated so that Xcode builds this package for the same iOS as the app
    // target that consumes it. Left unsaid, a package's iOS floor is old
    // enough (12.0) that Swift concurrency does not exist there, and an
    // `async` declaration in Core fails the archive build while `swift test`
    // — which builds for the host — stays green. Written as a string because
    // the enum case for this version needs a newer toolchain than the Linux
    // container CI runs `swift test` in.
    platforms: [.iOS("26.0")],
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
