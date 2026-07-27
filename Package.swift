// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutohandVoice",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AutohandVoiceCore", targets: ["AutohandVoiceCore"]),
        .executable(name: "autohand-voice", targets: ["AutohandVoice"]),
        .executable(name: "autohand-voice-stt", targets: ["AutohandVoiceSTT"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.14.4"
        ),
    ],
    targets: [
        .target(
            name: "AutohandVoiceCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "AutohandVoice",
            dependencies: ["AutohandVoiceCore"]
        ),
        .executableTarget(
            name: "AutohandVoiceSTT",
            dependencies: ["AutohandVoiceCore"]
        ),
        .testTarget(
            name: "AutohandVoiceCoreTests",
            dependencies: ["AutohandVoiceCore"]
        ),
    ]
)
