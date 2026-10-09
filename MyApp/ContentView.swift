import SwiftUI

#Preview {
    TaskListView(viewModel: TaskListViewModel(repository: DefaultTaskRepository(api: MockTaskAPI())))
}
