// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "EC25Manager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EC25Manager", targets: ["EC25Manager"])
    ],
    targets: [
        .target(
            name: "CEC25USB",
            path: "Sources/CEC25USB",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("usb-1.0")
            ]
        ),
        .executableTarget(
            name: "EC25Manager",
            dependencies: ["CEC25USB"],
            path: "Sources/EC25Manager",
            swiftSettings: [
                // CommandLineTools lacks the SwiftUI macro plugin; borrow the one
                // from Xcode-beta 27 (matches the macOS 27 SDK) so `swift build`
                // can compile SwiftUI (@State, Liquid Glass, …) without needing
                // the full Xcode toolchain / license.
                .unsafeFlags(["-plugin-path", "/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"])
            ],
            linkerSettings: [
                // Let dev runs (.build/release/EC25Manager) find the Homebrew libusb.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"])
            ]
        )
    ]
)
