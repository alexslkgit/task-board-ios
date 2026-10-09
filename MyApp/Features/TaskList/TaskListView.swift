import os
import SwiftUI

private enum Constants {
    enum Layout {
        static let bannerSpacing: CGFloat = 8
        static let bannerBottomPadding: CGFloat = 8
        static let bannerItemSpacing: CGFloat = 12
        static let bannerSpacerMinLength: CGFloat = 8
        static let bannerHorizontalPadding: CGFloat = 16
        static let bannerVerticalPadding: CGFloat = 10
        static let bannerLines = 2
        static let bannerShadowRadius: CGFloat = 4
        static let bannerShadowOffset: CGFloat = 2
        static let hitTarget: CGFloat = 44
        static let bannerFont = Font.subheadline
    }

    enum Timing {
        static let errorAutoHide = Duration.seconds(4)
        static let undoAutoHide = Duration.seconds(6)
    }

    enum Symbols {
        static let loadFailed = "exclamationmark.triangle"
        static let empty = "checklist"
        static let add = "plus"
        static let delete = "trash"
        static let error = "exclamationmark.circle.fill"
        static let dismiss = "xmark"
        static let deleted = "trash"
        static let unavailable = "trash"
    }

    enum Strings {
        static let title: LocalizedStringKey = "Tasks"
        static let loadFailed: LocalizedStringKey = "Couldn't load tasks"
        static let retry: LocalizedStringKey = "Retry"
        static let empty: LocalizedStringKey = "No tasks"
        static let addTask: LocalizedStringKey = "Add task"
        static let delete: LocalizedStringKey = "Delete"
        static let sortBy: LocalizedStringKey = "Sort by"
        static let dismiss: LocalizedStringKey = "Dismiss"
        static let undo: LocalizedStringKey = "Undo"
        static let deleted = String(localized: "Task deleted")
        static let unavailable: LocalizedStringKey = "Task unavailable"
        static let unavailableDescription: LocalizedStringKey = "This task was deleted."
    }
}

struct TaskListView: View {
    @Bindable var viewModel: TaskListViewModel
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Constants.Strings.title)
                .navigationDestination(for: TaskItem.ID.self) { id in
                    if let task = viewModel.task(id: id) {
                        TaskFormView(viewModel: viewModel, mode: .edit(task))
                    } else {
                        ContentUnavailableView(
                            Constants.Strings.unavailable,
                            systemImage: Constants.Symbols.unavailable,
                            description: Text(Constants.Strings.unavailableDescription)
                        )
                        .onAppear { Logger.ui.info("Deleted-while-opening state shown") }
                    }
                }
                .searchable(text: $viewModel.searchText)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(Constants.Strings.addTask, systemImage: Constants.Symbols.add) { showingAdd = true }
                    }
                }
                .sheet(isPresented: $showingAdd) {
                    NavigationStack {
                        TaskFormView(viewModel: viewModel, mode: .add)
                    }
                }
                .safeAreaInset(edge: .bottom) { banners }
                .task { await viewModel.load() }
                .task(id: viewModel.mutationError) {
                    guard viewModel.mutationError != nil else { return }
                    try? await Task.sleep(for: Constants.Timing.errorAutoHide)
                    guard !Task.isCancelled else { return }
                    viewModel.mutationError = nil
                    Logger.ui.info("Error banner auto-hidden")
                }
                .task(id: viewModel.recentlyDeleted?.id) {
                    guard let id = viewModel.recentlyDeleted?.id else { return }
                    try? await Task.sleep(for: Constants.Timing.undoAutoHide)
                    guard !Task.isCancelled else { return }
                    viewModel.dismissUndo(for: id)
                    Logger.ui.info("Undo banner auto-hidden")
                }
                .onChange(of: viewModel.mutationError) { _, message in
                    guard let message else { return }
                    Logger.ui.info("Error banner shown")
                    AccessibilityNotification.Announcement(message).post()
                }
                .onChange(of: viewModel.recentlyDeleted?.id) { _, id in
                    guard id != nil else { return }
                    Logger.ui.info("Undo banner shown")
                    AccessibilityNotification.Announcement(Constants.Strings.deleted).post()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.tasks.isEmpty, viewModel.loadState == .idle || viewModel.loadState == .loading {
            ProgressView()
        } else if viewModel.tasks.isEmpty, case .failed(let message) = viewModel.loadState {
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
            .onAppear { Logger.ui.info("Load error screen shown") }
        } else if viewModel.isEmpty {
            ContentUnavailableView {
                Label(Constants.Strings.empty, systemImage: Constants.Symbols.empty)
            } actions: {
                Button(Constants.Strings.addTask) { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if viewModel.visibleTasks.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            List {
                Section {
                    Picker(Constants.Strings.sortBy, selection: $viewModel.sortOrder) {
                        ForEach(TaskListViewModel.SortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ForEach(viewModel.visibleTasks) { task in
                    NavigationLink(value: task.id) {
                        TaskRowView(task: task) {
                            Task { await viewModel.toggleDone(task) }
                        }
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
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: Constants.Layout.bannerSpacing) {
            if let message = viewModel.mutationError {
                Banner(message: message, systemImage: Constants.Symbols.error, tint: .red) {
                    Button(Constants.Strings.dismiss, systemImage: Constants.Symbols.dismiss) {
                        viewModel.mutationError = nil
                        Logger.ui.info("Error banner dismissed")
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Constants.Layout.hitTarget, minHeight: Constants.Layout.hitTarget)
                    .contentShape(.rect)
                }
            }
            if viewModel.recentlyDeleted != nil {
                Banner(message: Constants.Strings.deleted, systemImage: Constants.Symbols.deleted, tint: .secondary) {
                    Button(Constants.Strings.undo) {
                        Logger.ui.info("Undo tapped")
                        Task { await viewModel.undoDelete() }
                    }
                    .fontWeight(.semibold)
                    .frame(minWidth: Constants.Layout.hitTarget, minHeight: Constants.Layout.hitTarget)
                    .contentShape(.rect)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, Constants.Layout.bannerBottomPadding)
        .animation(.default, value: viewModel.mutationError)
        .animation(.default, value: viewModel.recentlyDeleted?.id)
    }
}

private struct Banner<Action: View>: View {
    let message: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: Constants.Layout.bannerItemSpacing) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(message).font(Constants.Layout.bannerFont).lineLimit(Constants.Layout.bannerLines)
            Spacer(minLength: Constants.Layout.bannerSpacerMinLength)
            action
        }
        .padding(.horizontal, Constants.Layout.bannerHorizontalPadding)
        .padding(.vertical, Constants.Layout.bannerVerticalPadding)
        .background(.regularMaterial, in: .capsule)
        .shadow(radius: Constants.Layout.bannerShadowRadius, y: Constants.Layout.bannerShadowOffset)
    }
}
