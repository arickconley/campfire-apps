import SwiftUI

@main
struct CampfireApp: App {
    @State private var store = PostsStore()

    var body: some Scene {
        WindowGroup {
            PostListView()
                .environment(store)
        }
    }
}
