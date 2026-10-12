import SwiftUI

private enum Constants {
    enum Layout {
        static let badgeVerticalPadding: CGFloat = 3
        static let badgeOpacity = 0.15
        static let badgeDarkOpacity = 0.25
        static let badgeIconSpacing: CGFloat = 4
        static let badgeLightMix = 0.45
        static let badgeDarkMix = 0.35
        static let badgeWidth: CGFloat = 80
        static let badgeMaxWidth: CGFloat = 190
        static let badgeMinScale = 0.7
        static let badgeFont = Font.caption2.weight(.semibold)
        static let dueFont = Font.caption
    }

    enum Symbols {
        static let high = "exclamationmark.2"
        static let medium = "exclamationmark"
        static let low = "arrow.down"
    }

    enum Strings {
        static let overdue: LocalizedStringKey = "Overdue"
        static func priority(_ name: String) -> String { String(localized: "Priority: \(name)") }
        static func due(_ relative: String) -> String { String(localized: "Due \(relative)") }
    }
}

extension Priority {
    var tint: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .high: Constants.Symbols.high
        case .medium: Constants.Symbols.medium
        case .low: Constants.Symbols.low
        }
    }
}

extension TaskItem {
    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now)
    }
}

struct PriorityBadge: View {
    let priority: Priority

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption2) private var width = Constants.Layout.badgeWidth

    private var isDark: Bool { colorScheme == .dark }

    private var foreground: Color {
        isDark
            ? priority.tint.mix(with: .white, by: Constants.Layout.badgeDarkMix)
            : priority.tint.mix(with: .black, by: Constants.Layout.badgeLightMix)
    }

    var body: some View {
        HStack(spacing: Constants.Layout.badgeIconSpacing) {
            Image(systemName: priority.symbol)
            Text(priority.title)
        }
        .font(Constants.Layout.badgeFont)
        .lineLimit(1)
        .minimumScaleFactor(Constants.Layout.badgeMinScale)
        .frame(width: min(width, Constants.Layout.badgeMaxWidth))
        .padding(.vertical, Constants.Layout.badgeVerticalPadding)
        .foregroundStyle(foreground)
        .background(
            priority.tint.opacity(isDark ? Constants.Layout.badgeDarkOpacity : Constants.Layout.badgeOpacity),
            in: .capsule
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Constants.Strings.priority(priority.title))
    }
}

struct DueDateLabel: View {
    let task: TaskItem

    private var relative: String {
        guard let dueDate = task.dueDate else { return "" }
        let day = Calendar.current.startOfDay(for: dueDate)
        let style = Date.RelativeFormatStyle(allowedFields: [.day], presentation: .named, unitsStyle: .wide)
        return Constants.Strings.due(day.formatted(style))
    }

    var body: some View {
        if task.dueDate != nil {
            Group {
                if task.isOverdue {
                    Text(Constants.Strings.overdue).foregroundStyle(.red)
                } else {
                    Text(relative).foregroundStyle(.secondary)
                }
            }
            .font(Constants.Layout.dueFont)
        }
    }
}
