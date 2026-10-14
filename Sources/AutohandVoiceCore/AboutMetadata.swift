import Foundation

public struct AboutMetadata: Equatable, Sendable {
    public let productName: String
    public let companyName: String
    public let version: String
    public let summary: String
    public let upstreamAttribution: String
    public let noticesResourceName: String
    public let noticesResourceExtension: String
    public let licensedComponents: [String]

    public static let current = AboutMetadata(
        productName: Brand.productName,
        companyName: "Autohand AI",
        version: Brand.version,
        summary:
            "Native, private voice input for Mac. "
            + "Speech recognition runs locally with CoreML.",
        upstreamAttribution:
            "Based on Dictate by brando, used under the MIT License.",
        noticesResourceName: "THIRD-PARTY-NOTICES",
        noticesResourceExtension: "txt",
        licensedComponents: [
            "Autohand Voice",
            "Dictate",
            "FluidAudio",
            "NVIDIA Parakeet TDT 0.6B v3",
        ]
    )
}
