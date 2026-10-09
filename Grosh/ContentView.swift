//
//  ContentView.swift
//  Grosh
//
//  Created by Leonid Mateush on 4/11/26.
//

import SwiftUI

/// The app's top-level sections: a tab bar on iPhone, a sidebar on iPad and Mac.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case transactions
    case budgets
    case account

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .transactions: "Transactions"
        case .budgets: "Budgets"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .transactions: "list.bullet.rectangle.portrait.fill"
        case .budgets: "chart.pie.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

struct ContentView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    PlaceholderScreen(tab: tab)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .defaultAdaptableTabBarPlacement(.sidebar)
        #endif
    }
}

/// Stands in for a tab until its screen is built.
private struct PlaceholderScreen: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            ContentUnavailableView(tab.title, systemImage: tab.systemImage, description: Text("Coming soon"))
                .navigationTitle(tab.title)
        }
    }
}

#Preview {
    ContentView()
}
