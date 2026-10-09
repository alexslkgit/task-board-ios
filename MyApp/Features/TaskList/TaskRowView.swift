import SwiftUI

private enum Constants {
    enum Layout {
        static let spacing: CGFloat = 12
        static let largeTextSpacing: CGFloat = 8
        static let textSpacing: CGFloat = 2
        static let spacerMinLength: CGFloat = 8
        static let titleLines = 2
        static let notesLines = 1
        static let largeTextNotesLines = 2
        static let badgeHorizontalPadding: CGFloat = 8
        static let badgeVerticalPadding: CGFloat = 3
        static let badgeOpacity = 0.15
        static let toggleFont = Font.title2
        static let notesFont = Font.subheadline
        static let badgeFont = Font.caption2.weight(.semibold)
    }

    enum Symbols {
        static let done = "checkmark.circle.fill"
        static let notDone = "circle"
        static let high = "exclamationmark.2"
        static let medium = "exclamationmark"
        static let low = "arrow.down"
    }

    enum Strings {
        static let done: LocalizedStringKey = "Done"
        static let notDone: LocalizedStringKey = "Not done"
        static let markDone: LocalizedStringKey = "Mark as done"
        static let markNotDone: LocalizedStringKey = "Mark as not done"
        static func priority(_ name: String) -> String { String(localized: "Priority: \(name)") }
    }
}

struct TaskRowView: View {
    let task: TaskItem
    let onToggle: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var toggleButton: some View {
        Button(action: onToggle) {
            Image(systemName: task.isDone ? Constants.Symbols.done : Constants.Symbols.notDone)
                .font(Constants.Layout.toggleFont)
                .foregroundStyle(task.isDone ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityHidden(true)
    }

    private func texts(titleLimit: Int?, notesLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: Constants.Layout.textSpacing) {
            Text(task.title)
                .lineLimit(titleLimit)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(Constants.Layout.notesFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(notesLimit)
            }
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: Constants.Layout.spacing) {
                    toggleButton
                    VStack(alignment: .leading, spacing: Constants.Layout.largeTextSpacing) {
                        texts(titleLimit: nil, notesLimit: Constants.Layout.largeTextNotesLines)
                        PriorityBadge(priority: task.priority)
                    }
                }
            } else {
                HStack(spacing: Constants.Layout.spacing) {
                    toggleButton
                    texts(titleLimit: Constants.Layout.titleLines, notesLimit: Constants.Layout.notesLines)
                    Spacer(minLength: Constants.Layout.spacerMinLength)
                    PriorityBadge(priority: task.priority)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isDone ? Constants.Strings.done : Constants.Strings.notDone)
        .accessibilityAction(
            named: task.isDone ? Constants.Strings.markNotDone : Constants.Strings.markDone,
            onToggle
        )
    }
}

private struct PriorityBadge: View {
    let priority: Priority

    private var color: Color {
        switch priority {
        case .high: .red
        case .medium: .orange
        case .low: .gray
        }
    }

    private var symbol: String {
        switch priority {
        case .high: Constants.Symbols.high
        case .medium: Constants.Symbols.medium
        case .low: Constants.Symbols.low
        }
    }

    var body: some View {
        Label(priority.title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(Constants.Layout.badgeFont)
            .padding(.horizontal, Constants.Layout.badgeHorizontalPadding)
            .padding(.vertical, Constants.Layout.badgeVerticalPadding)
            .foregroundStyle(color)
            .background(color.opacity(Constants.Layout.badgeOpacity), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Constants.Strings.priority(priority.title))
    }
}
