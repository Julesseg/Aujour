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
    //
    // macOS is here for the same reason, and it is what makes `swift test`
    // work on a Mac at all. Naming any platform leaves the ones left unnamed
    // at their defaults rather than unconstrained, and the default macOS floor
    // (10.13) predates both Swift concurrency and `Duration` — so on a Mac the
    // documented fast loop failed to build, on code CI was compiling happily.
    // CI never saw it: it runs `swift test` in a Linux container, where there
    // is no availability gate to fail. The floor only has to be new enough for
    // what Core already uses; it says nothing about where the app can run.
    platforms: [.iOS("26.0"), .macOS("14.0")],
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
