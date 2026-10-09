import os
import SwiftUI

private enum Constants {
    enum Layout {
        static let notesLines = 3...8
    }

    enum Symbols {
        static let unavailable = "trash"
        static let saveError = "exclamationmark.triangle.fill"
    }

    enum Strings {
        static let unavailable: LocalizedStringKey = "Task unavailable"
        static let unavailableDescription: LocalizedStringKey = "This task was deleted."
        static let editTitle: LocalizedStringKey = "Edit Task"
        static let newTitle: LocalizedStringKey = "New Task"
        static let title: LocalizedStringKey = "Title"
        static let notes: LocalizedStringKey = "Notes"
        static let priority: LocalizedStringKey = "Priority"
        static let done: LocalizedStringKey = "Done"
        static let cancel: LocalizedStringKey = "Cancel"
        static let save: LocalizedStringKey = "Save"
    }
}

struct TaskFormView: View {
    enum Mode {
        case add
        case edit(TaskItem)
    }

    let viewModel: TaskListViewModel
    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var isDone: Bool
    @State private var isSaving = false
    @State private var saveError: String?

    init(viewModel: TaskListViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _priority = State(initialValue: .medium)
            _isDone = State(initialValue: false)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes)
            _priority = State(initialValue: task.priority)
            _isDone = State(initialValue: task.isDone)
        }
    }

    private var editedTask: TaskItem? {
        guard case .edit(let task) = mode else { return nil }
        return viewModel.task(id: task.id)
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if isEditing, editedTask == nil {
                ContentUnavailableView(
                    Constants.Strings.unavailable,
                    systemImage: Constants.Symbols.unavailable,
                    description: Text(Constants.Strings.unavailableDescription)
                )
                .onAppear { Logger.ui.info("Deleted-while-editing state shown") }
            } else {
                form
            }
        }
        .navigationTitle(isEditing ? Constants.Strings.editTitle : Constants.Strings.newTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        Form {
            Section {
                TextField(Constants.Strings.title, text: $title)
                TextField(Constants.Strings.notes, text: $notes, axis: .vertical)
                    .lineLimit(Constants.Layout.notesLines)
            }
            Section {
                Picker(Constants.Strings.priority, selection: $priority) {
                    ForEach(Priority.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if isEditing {
                Section {
                    Toggle(Constants.Strings.done, isOn: $isDone)
                }
            }
            if let saveError {
                Section {
                    Label(saveError, systemImage: Constants.Symbols.saveError)
                        .foregroundStyle(.red)
                }
            }
        }
        .toolbar {
            if !isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Constants.Strings.cancel) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(Constants.Strings.save, action: save)
                    .disabled(trimmedTitle.isEmpty || isSaving)
            }
        }
    }

    // Stay open on failure so the user keeps their input and can retry.
    private func save() {
        Logger.ui.info("Save tapped")
        isSaving = true
        saveError = nil
        Task {
            let saved: Bool
            if var task = editedTask {
                task.title = trimmedTitle
                task.notes = notes
                task.priority = priority
                task.isDone = isDone
                saved = await viewModel.update(task)
            } else {
                saved = await viewModel.add(title: trimmedTitle, notes: notes, priority: priority)
            }
            isSaving = false
            if saved {
                dismiss()
            } else {
                let message = viewModel.mutationError
                viewModel.mutationError = nil
                saveError = message
                Logger.ui.info("Save error shown")
                if let message { AccessibilityNotification.Announcement(message).post() }
            }
        }
    }
}
