import SwiftUI

@main
struct ColorizeDesignerRebuildApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
