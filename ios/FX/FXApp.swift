import SwiftUI

@main
struct FXApp: App {
    @State private var store = RatesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
