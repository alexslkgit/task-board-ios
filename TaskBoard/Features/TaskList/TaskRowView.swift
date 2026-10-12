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
        static let toggleFont = Font.title2
        static let notesFont = Font.subheadline
    }

    enum Symbols {
        static let done = "checkmark.circle.fill"
        static let notDone = "circle"
    }

    enum Strings {
        static let done: LocalizedStringKey = "Done"
        static let notDone: LocalizedStringKey = "Not done"
        static let markDone: LocalizedStringKey = "Mark done"
        static let markNotDone: LocalizedStringKey = "Mark not done"
        static let delete: LocalizedStringKey = "Delete"
    }
}

struct TaskRowView: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void

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
            DueDateLabel(task: task)
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
        .accessibilityAction(named: Constants.Strings.delete, onDelete)
    }
}

#if DEBUG
#Preview("States") {
    List(PreviewData.tasks) { task in
        TaskRowView(task: task, onToggle: {}, onDelete: {})
    }
}

#Preview("Accessibility size") {
    List(PreviewData.tasks) { task in
        TaskRowView(task: task, onToggle: {}, onDelete: {})
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
