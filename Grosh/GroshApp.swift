import SwiftData
import SwiftUI

@main
struct GroshApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try GroshStore.makeSeededContainer()
        } catch {
            fatalError("Couldn't open the Grosh store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .commands {
            NewTransactionCommands()
        }
    }
}
