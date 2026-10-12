import os
import SwiftUI

private enum Constants {
    enum Layout {
        static let bannerSpacing: CGFloat = 8
        static let bannerBottomPadding: CGFloat = 8
        static let bottomSearchClearance: CGFloat = 52
    }

    enum Symbols {
        static let loadFailed = "exclamationmark.triangle"
        static let empty = "checklist"
        static let add = "plus"
        static let delete = "trash"
        static let sort = "arrow.up.arrow.down"
        static let search = "magnifyingglass"
    }

    enum Strings {
        static let title: LocalizedStringKey = "Tasks"
        static let loadFailed: LocalizedStringKey = "Couldn't load tasks"
        static let retry: LocalizedStringKey = "Retry"
        static let empty: LocalizedStringKey = "No tasks"
        static let emptyDescription: LocalizedStringKey = "Tap + to add your first task."
        static let addTask: LocalizedStringKey = "Add task"
        static let delete: LocalizedStringKey = "Delete"
        static let sortBy: LocalizedStringKey = "Sort by"
        static let noResults: LocalizedStringKey = "No results"
        static let clearSearch: LocalizedStringKey = "Clear search"
        static func noResultsDescription(_ query: String) -> LocalizedStringKey { "No tasks match \"\(query)\"." }
    }
}

struct TaskListView: View {
    @Bindable var viewModel: TaskListViewModel
    @State private var showingAdd = false
    @State private var path: [TaskItem.ID] = []
    @SceneStorage("sortOrder") private var storedSortOrder = TaskListViewModel.SortOrder.created
    @SceneStorage("searchText") private var storedSearchText = ""

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(Constants.Strings.title)
                .navigationDestination(for: TaskItem.ID.self) { id in
                    TaskDetailView(viewModel: viewModel, taskID: id)
                }
                .toolbar {
                    // The iOS 26 glass toolbar draws glyphs monochrome unless tinted explicitly.
                    if !viewModel.tasks.isEmpty {
                        ToolbarItem(placement: .topBarLeading) { sortMenu.tint(.accentColor) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(Constants.Strings.addTask, systemImage: Constants.Symbols.add) { showingAdd = true }
                            .tint(.accentColor)
                    }
                }
                .sheet(isPresented: $showingAdd) {
                    NavigationStack {
                        TaskFormView(viewModel: viewModel, mode: .add)
                    }
                }
                .task { await viewModel.load() }
        }
        .safeAreaInset(edge: .bottom) { banners }
        .onAppear {
            viewModel.sortOrder = storedSortOrder
            viewModel.searchText = storedSearchText
        }
        .onChange(of: viewModel.sortOrder) { _, order in storedSortOrder = order }
        .onChange(of: viewModel.searchText) { _, text in storedSearchText = text }
    }

    private var sortMenu: some View {
        Menu {
            Picker(Constants.Strings.sortBy, selection: $viewModel.sortOrder) {
                ForEach(TaskListViewModel.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(viewModel.sortOrder.title, systemImage: Constants.Symbols.sort)
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel(Constants.Strings.sortBy)
        .accessibilityValue(viewModel.sortOrder.title)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.tasks.isEmpty {
            emptyState
        } else {
            Group {
                if viewModel.visibleTasks.isEmpty {
                    ContentUnavailableView {
                        Label(Constants.Strings.noResults, systemImage: Constants.Symbols.search)
                    } description: {
                        Text(Constants.Strings.noResultsDescription(viewModel.searchText))
                    } actions: {
                        Button(Constants.Strings.clearSearch) { viewModel.searchText = "" }
                            .buttonStyle(.borderedProminent)
                    }
                    .groupedBackground()
                } else {
                    taskList
                }
            }
            .searchable(text: $viewModel.searchText)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if case .failed(let message) = viewModel.loadState {
            ContentUnavailableView {
                Label(Constants.Strings.loadFailed, systemImage: Constants.Symbols.loadFailed)
            } description: {
                Text(message)
            } actions: {
                Button(Constants.Strings.retry) {
                    Logger.ui.info("Retry tapped")
                    Task { await viewModel.load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .groupedBackground()
            .onAppear { Logger.ui.info("Load error screen shown") }
        } else if viewModel.isEmpty {
            ContentUnavailableView {
                Label(Constants.Strings.empty, systemImage: Constants.Symbols.empty)
            } description: {
                Text(Constants.Strings.emptyDescription)
            } actions: {
                Button(Constants.Strings.addTask) { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
            .groupedBackground()
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).groupedBackground()
        }
    }

    private var taskList: some View {
        List {
            ForEach(viewModel.visibleTasks) { task in
                NavigationLink(value: task.id) {
                    TaskRowView(
                        task: task,
                        onToggle: { Task { await viewModel.toggleDone(task) } },
                        onDelete: { Task { await viewModel.delete(task) } }
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button(Constants.Strings.delete, systemImage: Constants.Symbols.delete, role: .destructive) {
                        Task { await viewModel.delete(task) }
                    }
                }
            }
        }
        .refreshable { await viewModel.refresh() }
    }

    /// From iOS 26 the search field floats at the bottom of the list screen, exactly where the banners sit.
    private var searchClearance: CGFloat {
        guard #available(iOS 26, *), path.isEmpty, !viewModel.tasks.isEmpty else { return 0 }
        return Constants.Layout.bottomSearchClearance
    }

    private var banners: some View {
        VStack(spacing: Constants.Layout.bannerSpacing) {
            if let banner = viewModel.mutationError {
                ErrorBannerView(banner: banner) { viewModel.mutationError = nil }
            }
            if let deleted = viewModel.recentlyDeleted {
                UndoBannerView(
                    id: deleted.id,
                    onUndo: { Task { await viewModel.undoDelete() } },
                    onExpire: { viewModel.dismissUndo(for: deleted.id) }
                )
            }
        }
        .padding(.horizontal)
        .padding(.bottom, Constants.Layout.bannerBottomPadding + searchClearance)
        .animation(.default, value: viewModel.mutationError)
        .animation(.default, value: viewModel.recentlyDeleted?.id)
    }
}

#if DEBUG
#Preview("Tasks") {
    TaskListView(viewModel: PreviewData.viewModel())
}

#Preview("Empty") {
    TaskListView(viewModel: PreviewData.viewModel(seed: []))
}

#Preview("Banners") {
    let viewModel = PreviewData.viewModel()
    return TaskListView(viewModel: viewModel)
        .task {
            await viewModel.load()
            viewModel.mutationError = ErrorBanner(message: "Network request failed. Please try again.")
            await viewModel.delete(PreviewData.tasks[2])
        }
}
#endif
