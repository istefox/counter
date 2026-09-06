import SwiftUI

struct UsageProgressRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.displayTitle)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(limit.percent, 0), 100), total: 100)
                .tint(limit.percent >= 90 ? .red : .accentColor)
            if let resetsAt = limit.resetsAt {
                Text("Reset: \(resetsAt.formatted(date: .long, time: .shortened)) (\(relativeDescription(for: resetsAt)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func relativeDescription(for date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}
