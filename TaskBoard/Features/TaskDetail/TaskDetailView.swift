import os
import SwiftUI

private enum Constants {
    enum Layout {
        static let headerSpacing: CGFloat = 10
        static let badgeSpacing: CGFloat = 12
        static let titleFont = Font.title2.weight(.semibold)
        static let statusFont = Font.subheadline
    }

    enum Symbols {
        static let unavailable = "trash"
        static let done = "checkmark.circle.fill"
        static let notDone = "circle"
        static let delete = "trash"
    }

    enum Strings {
        static let title: LocalizedStringKey = "Task"
        static let unavailable: LocalizedStringKey = "Task unavailable"
        static let unavailableDescription: LocalizedStringKey = "This task was deleted."
        static let edit: LocalizedStringKey = "Edit"
        static let notes: LocalizedStringKey = "Notes"
        static let noNotes: LocalizedStringKey = "No notes"
        static let dueDate: LocalizedStringKey = "Due date"
        static let created: LocalizedStringKey = "Created"
        static let done: LocalizedStringKey = "Done"
        static let notDone: LocalizedStringKey = "Not done"
        static let markDone: LocalizedStringKey = "Mark done"
        static let markNotDone: LocalizedStringKey = "Mark not done"
        static let delete: LocalizedStringKey = "Delete task"
        static let deletePrompt: LocalizedStringKey = "Delete this task?"
    }
}

struct TaskDetailView: View {
    let viewModel: TaskListViewModel
    let taskID: TaskItem.ID

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let task = viewModel.task(id: taskID) {
                detail(for: task)
            } else {
                ContentUnavailableView(
                    Constants.Strings.unavailable,
                    systemImage: Constants.Symbols.unavailable,
                    description: Text(Constants.Strings.unavailableDescription)
                )
                .onAppear { Logger.ui.info("Deleted-while-opening state shown") }
            }
        }
        .navigationTitle(Constants.Strings.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(for task: TaskItem) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Constants.Layout.headerSpacing) {
                    Text(task.title)
                        .font(Constants.Layout.titleFont)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    ViewThatFits(in: .horizontal) {
                        badges(for: task, axis: .horizontal)
                        badges(for: task, axis: .vertical)
                    }
                }
            }
            Section(Constants.Strings.notes) {
                if task.notes.isEmpty {
                    Text(Constants.Strings.noNotes).foregroundStyle(.secondary)
                } else {
                    Text(task.notes)
                }
            }
            Section {
                if let dueDate = task.dueDate {
                    LabeledContent(Constants.Strings.dueDate) {
                        VStack(alignment: .trailing) {
                            Text(dueDate, format: .dateTime.day().month(.abbreviated).year())
                            DueDateLabel(task: task)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                LabeledContent(Constants.Strings.created) {
                    Text(task.createdAt, format: .dateTime.day().month(.abbreviated).year())
                }
            }
            Section {
                Button(
                    task.isDone ? Constants.Strings.markNotDone : Constants.Strings.markDone,
                    systemImage: task.isDone ? Constants.Symbols.notDone : Constants.Symbols.done
                ) {
                    Task { await viewModel.toggleDone(task) }
                }
                Button(Constants.Strings.delete, systemImage: Constants.Symbols.delete, role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Constants.Strings.edit) { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                TaskFormView(viewModel: viewModel, mode: .edit(task))
            }
        }
        .confirmationDialog(Constants.Strings.deletePrompt, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(Constants.Strings.delete, role: .destructive) {
                Logger.ui.info("Delete confirmed from detail")
                dismiss()
                Task { await viewModel.delete(task) }
            }
        }
    }

    private func badges(for task: TaskItem, axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: Constants.Layout.badgeSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Layout.headerSpacing))
        return layout {
            PriorityBadge(priority: task.priority)
            Label(
                task.isDone ? Constants.Strings.done : Constants.Strings.notDone,
                systemImage: task.isDone ? Constants.Symbols.done : Constants.Symbols.notDone
            )
            .font(Constants.Layout.statusFont)
            .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Overdue") {
    let viewModel = PreviewData.viewModel()
    return NavigationStack {
        TaskDetailView(viewModel: viewModel, taskID: PreviewData.tasks[1].id)
    }
    .task { await viewModel.load() }
}

#Preview("Long title, accessibility size") {
    let viewModel = PreviewData.viewModel()
    return NavigationStack {
        TaskDetailView(viewModel: viewModel, taskID: PreviewData.tasks[4].id)
    }
    .task { await viewModel.load() }
    .dynamicTypeSize(.accessibility3)
}
#endif
