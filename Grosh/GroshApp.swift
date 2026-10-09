//
//  GroshApp.swift
//  Grosh
//
//  Created by Leonid Mateush on 4/11/26.
//

import SwiftData
import SwiftUI

@main
struct GroshApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try GroshStore.makeContainer()
            try CategorySeed.seedIfNeeded(container.mainContext)
        } catch {
            fatalError("Couldn't open the Grosh store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
