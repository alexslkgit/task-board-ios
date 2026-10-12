import SwiftUI

@main struct TaskBoardApp: App {
    @State private var viewModel = TaskListViewModel(
        repository: DefaultTaskRepository(api: LaunchConfiguration.current().makeAPI())
    )

    var body: some Scene {
        WindowGroup {
            TaskListView(viewModel: viewModel)
        }
    }
}
