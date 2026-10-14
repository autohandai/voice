import AppKit
import AutohandVoiceCore
import SwiftUI

struct AboutView: View {
    private enum Section: CaseIterable, Identifiable {
        case overview
        case notices

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .overview: "About"
            case .notices: "Notices"
            }
        }
    }

    private let metadata = AboutMetadata.current

    @State private var selectedSection = Section.overview
    @State private var executableChecksum = "Calculating…"
    @State private var notices = "Loading notices…"

    var body: some View {
        VStack(spacing: 0) {
            AboutHero(
                productName: metadata.productName,
                summary: metadata.summary
            )

            Picker("About section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch selectedSection {
                case .overview:
                    overview
                case .notices:
                    noticesView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadAboutDetails()
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 28,
                    verticalSpacing: 12
                ) {
                    aboutRow(
                        label: "Version",
                        value: "\(installedVersion) (\(buildNumber))"
                    )
                    aboutRow(label: "Architecture", value: architecture)
                    aboutRow(
                        label: "Engine",
                        value: "CoreML · Apple Neural Engine"
                    )
                    aboutRow(label: "Recognition", value: "Local only")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Executable SHA-256")
                            .font(.headline)

                        Spacer()

                        Button {
                            copyChecksum()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .disabled(executableChecksum.count != 64)
                        .help("Copy executable checksum")
                    }

                    Text(executableChecksum)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(
                            "Executable SHA-256 checksum: "
                                + executableChecksum
                        )
                }

                HStack(alignment: .top, spacing: 28) {
                    AboutPromise(
                        symbol: "memorychip",
                        title: "Private by design",
                        detail: "Speech stays on this Mac."
                    )
                    AboutPromise(
                        symbol: "icloud.slash",
                        title: "No remote fallback",
                        detail: "Failures remain visible."
                    )
                    AboutPromise(
                        symbol: "text.badge.checkmark",
                        title: "Final text only",
                        detail: "Partial speech is provisional."
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Built by \(metadata.companyName)")
                        .font(.headline)
                    Text(metadata.upstreamAttribution)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        Link("Website", destination: Brand.websiteURL)
                        Link(
                            "Privacy",
                            destination: Brand.privacyPolicyURL
                        )
                        Link("Source", destination: Brand.repositoryURL)
                        Button("View licenses") {
                            selectedSection = .notices
                        }
                        .buttonStyle(.link)
                    }
                }

                Text("© 2026 Autohand AI LLC")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
    }

    private var noticesView: some View {
        ScrollView {
            Text(notices)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
                .padding(28)
        }
        .accessibilityLabel("Open-source licenses and notices")
    }

    private func aboutRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .font(.headline)
                .gridColumnAlignment(.trailing)

            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var installedVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? metadata.version
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "development"
    }

    private var architecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        "Intel (x86_64)"
        #else
        "Unsupported architecture"
        #endif
    }

    private func loadAboutDetails() async {
        notices = loadNotices()

        guard let executableURL = Bundle.main.executableURL else {
            executableChecksum = "Executable unavailable"
            return
        }

        do {
            executableChecksum = try await Task.detached(
                priority: .utility
            ) {
                try ExecutableChecksum.sha256Hex(of: executableURL)
            }.value
        } catch {
            executableChecksum = "Checksum unavailable: \(error.localizedDescription)"
        }
    }

    private func loadNotices() -> String {
        guard let url = Bundle.main.url(
            forResource: metadata.noticesResourceName,
            withExtension: metadata.noticesResourceExtension,
            subdirectory: "Legal"
        ) else {
            return """
            Notices are unavailable in this development build.

            See LICENSE, NOTICE.md, and LICENSES.md in the source repository:
            \(Brand.repositoryURL.absoluteString)
            """
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Notices could not be read: \(error.localizedDescription)"
        }
    }

    private func copyChecksum() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(executableChecksum, forType: .string)
    }
}

private struct AboutHero: View {
    let productName: String
    let summary: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 28) {
            bundledLogo
                .frame(width: 158, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text(productName)
                    .font(
                        .system(size: 35, weight: .semibold, design: .rounded)
                    )
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 390, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 38)
        .frame(height: 170)
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(
                        colorScheme == .dark ? 0.16 : 0.10
                    ),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var bundledLogo: some View {
        if let image = logoImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            AutohandBrandMark(ringDiameter: 24)
        }
    }

    private var logoImage: NSImage? {
        let resource = colorScheme == .dark
            ? "autohand-logo-dark"
            : "autohand-logo-light"

        guard let url = Bundle.main.url(
            forResource: resource,
            withExtension: "svg",
            subdirectory: "Brand"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private struct AboutPromise: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
