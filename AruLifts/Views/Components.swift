import SwiftUI

/// Formats a weight with the user's preferred units.
func formatWeight(_ value: Double, units: AppSettings.Units) -> String {
    let rounded = (value * 10).rounded() / 10
    let number: String
    if rounded == rounded.rounded() {
        number = String(Int(rounded))
    } else {
        number = String(format: "%.1f", rounded)
    }
    return "\(number) \(units.label)"
}

/// A rounded card container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

/// Compact stat used in the home header.
struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.orange)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

/// Category pill used throughout the app.
struct CategoryBadge: View {
    let category: WorkoutCategory
    var body: some View {
        Label(category.displayName, systemImage: category.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(category.color.opacity(0.18), in: Capsule())
            .foregroundStyle(category.color)
    }
}
