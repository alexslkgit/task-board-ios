import SwiftUI

private enum Constants {
    enum Layout {
        static let largeTextSpacing: CGFloat = 8
        static let metaSpacing: CGFloat = 6
        static let textSpacing: CGFloat = 2
        static let titleLines = 4
        static let notesLines = 2
        static let toggleSize: CGFloat = 22
        static let hitTarget: CGFloat = 44
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
    @ScaledMetric(relativeTo: .title2) private var toggleSize = Constants.Layout.toggleSize

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    private var toggleButton: some View {
        Button(action: onToggle) {
            Image(systemName: task.isDone ? Constants.Symbols.done : Constants.Symbols.notDone)
                .font(.system(size: toggleSize))
                .foregroundStyle(task.isDone ? Color.accentColor : .secondary)
                .frame(
                    minWidth: Constants.Layout.hitTarget,
                    minHeight: Constants.Layout.hitTarget,
                    alignment: isLargeText ? .leading : .topLeading
                )
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(task.title)
            .lineLimit(isLargeText ? nil : Constants.Layout.titleLines)
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? .secondary : .primary)
    }

    @ViewBuilder private var notesText: some View {
        if !task.notes.isEmpty {
            Text(task.notes)
                .font(Constants.Layout.notesFont)
                .foregroundStyle(.secondary)
                .lineLimit(isLargeText ? nil : Constants.Layout.notesLines)
        }
    }

    private var regularLayout: some View {
        // The hit target's slack doubles as the gap before the title.
        HStack(alignment: .top, spacing: 0) {
            toggleButton
            VStack(alignment: .leading, spacing: Constants.Layout.textSpacing) {
                titleText
                notesText
                HStack(spacing: Constants.Layout.metaSpacing) {
                    PriorityBadge(priority: task.priority)
                    DueDateLabel(task: task)
                }
                .padding(.top, Constants.Layout.metaSpacing)
            }
        }
    }

    // Controls share one line so the title and notes get the full row width.
    private var largeTextLayout: some View {
        VStack(alignment: .leading, spacing: Constants.Layout.largeTextSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Constants.Layout.largeTextSpacing) {
                    toggleButton
                    PriorityBadge(priority: task.priority)
                    DueDateLabel(task: task)
                }
                VStack(alignment: .leading, spacing: Constants.Layout.metaSpacing) {
                    HStack(spacing: Constants.Layout.largeTextSpacing) {
                        toggleButton
                        PriorityBadge(priority: task.priority)
                    }
                    DueDateLabel(task: task).fixedSize(horizontal: false, vertical: true)
                }
            }
            titleText
            notesText
        }
    }

    var body: some View {
        Group {
            if isLargeText {
                largeTextLayout
            } else {
                regularLayout
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
