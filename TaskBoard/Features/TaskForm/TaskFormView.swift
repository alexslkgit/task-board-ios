import os
import SwiftUI

private enum Constants {
    enum Layout {
        static let notesLines = 3...8
        static let saveErrorID = "saveError"
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
        static let dueDate: LocalizedStringKey = "Due date"
        static let due: LocalizedStringKey = "Due"
        static let cancel: LocalizedStringKey = "Cancel"
        static let discardPrompt: LocalizedStringKey = "Discard changes?"
        static let discard: LocalizedStringKey = "Discard changes"
        static let keepEditing: LocalizedStringKey = "Keep editing"
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
    private let baseline: TaskItem

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var isDone: Bool
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var showingDiscard = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(viewModel: TaskListViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode
        let base: TaskItem
        switch mode {
        case .add: base = TaskItem(title: "")
        case .edit(let task): base = task
        }
        baseline = base
        _title = State(initialValue: base.title)
        _notes = State(initialValue: base.notes)
        _priority = State(initialValue: base.priority)
        _isDone = State(initialValue: base.isDone)
        _hasDueDate = State(initialValue: base.dueDate != nil)
        _dueDate = State(initialValue: base.dueDate ?? Calendar.current.startOfDay(for: .now))
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

    private var effectiveDueDate: Date? {
        hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
    }

    private var hasChanges: Bool {
        title != baseline.title
            || notes != baseline.notes
            || priority != baseline.priority
            || isDone != baseline.isDone
            || effectiveDueDate != baseline.dueDate.map { Calendar.current.startOfDay(for: $0) }
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
        ScrollViewReader { proxy in
            Form {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: Constants.Symbols.saveError)
                            .foregroundStyle(.red)
                    }
                    .id(Constants.Layout.saveErrorID)
                }
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
                Section {
                    Toggle(Constants.Strings.dueDate, isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker(Constants.Strings.due, selection: $dueDate, displayedComponents: .date)
                    }
                }
                if isEditing {
                    Section {
                        Toggle(Constants.Strings.done, isOn: $isDone)
                    }
                }
            }
            .onChange(of: saveError) { _, message in
                guard message != nil else { return }
                withAnimation { proxy.scrollTo(Constants.Layout.saveErrorID, anchor: .top) }
            }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Constants.Strings.cancel, action: cancel)
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(Constants.Strings.save, action: save)
                    .disabled(trimmedTitle.isEmpty || isSaving)
            }
        }
        .confirmationDialog(Constants.Strings.discardPrompt, isPresented: $showingDiscard, titleVisibility: .visible) {
            Button(Constants.Strings.discard, role: .destructive) {
                Logger.ui.info("Changes discarded")
                dismiss()
            }
            Button(Constants.Strings.keepEditing, role: .cancel) {}
        }
    }

    private func cancel() {
        if hasChanges {
            showingDiscard = true
        } else {
            dismiss()
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
                task.dueDate = effectiveDueDate
                saved = await viewModel.update(task)
            } else {
                saved = await viewModel.add(title: trimmedTitle, notes: notes, priority: priority, dueDate: effectiveDueDate)
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

#if DEBUG
#Preview("Add") {
    NavigationStack {
        TaskFormView(viewModel: PreviewData.viewModel(), mode: .add)
    }
}

#Preview("Edit") {
    let viewModel = PreviewData.viewModel()
    return NavigationStack {
        TaskFormView(viewModel: viewModel, mode: .edit(PreviewData.tasks[0]))
    }
    .task { await viewModel.load() }
}
#endif
