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
            exact: "0.15.8"
        ),
    ],
    targets: [
        // llama.cpp b11721 (MIT): a universal macOS framework with Metal
        // shaders built in. Runs the optional on-device Talk model.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11721/llama-b11721-xcframework.zip",
            checksum: "9efc8f94a7fb54abb4931bac484a025417cee5bbf8e15ba49b4d9ddef997460f"
        ),
        .target(
            name: "AutohandVoiceLLM",
            dependencies: ["AutohandVoiceCore", "llama"]
        ),
        .target(
            name: "AutohandVoiceCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "AutohandVoice",
            dependencies: ["AutohandVoiceCore", "AutohandVoiceLLM"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
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
