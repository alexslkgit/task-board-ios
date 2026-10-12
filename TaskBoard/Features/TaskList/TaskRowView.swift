import SwiftUI

private enum Constants {
    enum Layout {
        static let spacing: CGFloat = 12
        static let largeTextSpacing: CGFloat = 8
        static let metaSpacing: CGFloat = 6
        static let textSpacing: CGFloat = 2
        static let titleLines = 3
        static let notesLines = 2
        static let toggleFont = Font.title2
        static let largeTextToggleFont = Font.system(size: 20)
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
                .font(dynamicTypeSize.isAccessibilitySize ? Constants.Layout.largeTextToggleFont : Constants.Layout.toggleFont)
                .foregroundStyle(task.isDone ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityHidden(true)
    }

    private var meta: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Layout.metaSpacing))
            : AnyLayout(HStackLayout(spacing: Constants.Layout.metaSpacing))
        return layout {
            PriorityBadge(priority: task.priority)
            DueDateLabel(task: task)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: dynamicTypeSize.isAccessibilitySize ? Constants.Layout.largeTextSpacing : Constants.Layout.spacing) {
            toggleButton
            VStack(alignment: .leading, spacing: Constants.Layout.textSpacing) {
                Text(task.title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : Constants.Layout.titleLines)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(Constants.Layout.notesFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(Constants.Layout.notesLines)
                }
                meta.padding(.top, Constants.Layout.metaSpacing)
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
