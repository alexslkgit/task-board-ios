import SwiftUI

private enum Constants {
    enum Layout {
        static let badgeHorizontalPadding: CGFloat = 8
        static let badgeVerticalPadding: CGFloat = 3
        static let badgeOpacity = 0.15
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

    var body: some View {
        Label(priority.title, systemImage: priority.symbol)
            .labelStyle(.titleAndIcon)
            .font(Constants.Layout.badgeFont)
            .padding(.horizontal, Constants.Layout.badgeHorizontalPadding)
            .padding(.vertical, Constants.Layout.badgeVerticalPadding)
            .foregroundStyle(priority.tint)
            .background(priority.tint.opacity(Constants.Layout.badgeOpacity), in: .capsule)
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
