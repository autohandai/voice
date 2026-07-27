import AutohandVoiceCore
import Charts
import Observation
import SwiftUI

@MainActor
@Observable
final class UsageInsightsModel {
    let session: VoiceSession
    var days: [UsageInsightDay] = []
    var errorMessage: String?

    private let store = UsageInsightsStore()

    init(session: VoiceSession) {
        self.session = session
        session.onInsightsChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    var summary: UsageInsightsSummary {
        UsageInsightsSummary(days: days)
    }

    var recentDays: [UsageInsightDay] {
        Array(days.prefix(30).reversed())
    }

    func refresh() {
        do {
            days = try store.load()
            errorMessage = session.usageInsightsError
        } catch {
            days = []
            errorMessage =
                "Could not load usage insights: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool) {
        session.setUsageInsightsEnabled(enabled)
        refresh()
    }

    func reset() {
        do {
            try session.resetUsageInsights()
            days = []
            errorMessage = nil
        } catch {
            errorMessage =
                "Could not reset usage insights: \(error.localizedDescription)"
        }
    }
}

struct UsageInsightsView: View {
    @Bindable var model: UsageInsightsModel
    @State private var confirmsReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()

            if model.session.preferences.usageInsightsEnabled {
                if model.days.isEmpty {
                    ContentUnavailableView(
                        "No Usage Yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text(
                            "Aggregate metrics appear after future dictations. Transcript text is never required."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    summary
                    dailyChart
                    dailyTable
                }
            } else {
                ContentUnavailableView(
                    "Private Insights Are Off",
                    systemImage: "chart.bar.xaxis",
                    description: Text(
                        "Enable independently from transcript history to store bounded aggregate counters on this Mac."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Usage insights error: \(error)")
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 500)
        .confirmationDialog(
            "Reset all private usage statistics?",
            isPresented: $confirmsReset
        ) {
            Button("Reset Statistics", role: .destructive) {
                model.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes aggregate counters from this Mac.")
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                insightsHeading
                Spacer()
                insightsControls
            }
            VStack(alignment: .leading, spacing: 12) {
                insightsHeading
                insightsControls
            }
        }
    }

    private var summary: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 150),
                    alignment: .leading
                ),
            ],
            alignment: .leading,
            spacing: 10
        ) {
            summaryItem(
                "Dictations",
                model.summary.dictationCount.formatted()
            )
            summaryItem(
                "Words",
                model.summary.wordCount.formatted()
            )
            summaryItem(
                "Recording time",
                duration(model.summary.recordingDuration)
            )
            summaryItem(
                "Average processing",
                duration(model.summary.averageProcessingLatency)
            )
            summaryItem(
                "Insertion success",
                model.summary.insertionSuccessRate.formatted(
                    .percent.precision(.fractionLength(0))
                )
            )
            summaryItem(
                "Estimated time saved",
                duration(model.summary.estimatedTypingTimeSaved)
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var insightsHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Private Usage Insights")
                .font(.title)
            Text("Optional aggregate metrics stored only on this Mac.")
                .foregroundStyle(.secondary)
        }
    }

    private var insightsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Collect Insights",
                isOn: Binding(
                    get: {
                        model.session.preferences.usageInsightsEnabled
                    },
                    set: { model.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            Button("Reset All…", role: .destructive) {
                confirmsReset = true
            }
            .disabled(model.days.isEmpty)
        }
    }

    private func summaryItem(
        _ label: String,
        _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words per day · last 30 active days")
                .font(.headline)
            Chart(model.recentDays) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Words", day.wordCount)
                )
                .accessibilityLabel(
                    day.day.formatted(date: .abbreviated, time: .omitted)
                )
                .accessibilityValue("\(day.wordCount.formatted()) words")
            }
            .chartYAxisLabel("Words")
            .frame(height: 150)
            .accessibilityLabel("Daily word count chart")
            .accessibilityValue(chartSummary)
        }
    }

    private var dailyTable: some View {
        Table(model.days) {
            TableColumn("Date") { day in
                Text(day.day.formatted(date: .abbreviated, time: .omitted))
            }
            TableColumn("Dictations") { day in
                Text(day.dictationCount.formatted())
            }
            TableColumn("Words") { day in
                Text(day.wordCount.formatted())
            }
            TableColumn("Recording") { day in
                Text(duration(day.recordingDuration))
            }
            TableColumn("Processing") { day in
                Text(duration(day.processingDuration))
            }
            TableColumn("Inserted") { day in
                Text(
                    "\(day.insertionSuccessCount.formatted()) of "
                        + "\(day.insertionSuccessCount + day.insertionFailureCount)"
                )
            }
        }
        .frame(minHeight: 170)
        .accessibilityLabel("Daily usage data table")
    }

    private var chartSummary: String {
        let total = model.recentDays.reduce(0) { $0 + $1.wordCount }
        return "\(total.formatted()) words across \(model.recentDays.count.formatted()) active days"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 2
            )
        )
    }
}
