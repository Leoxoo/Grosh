import SwiftUI

/// Home's coming-soon cards (Report this month, Top spending), placed where the real reports will go.
/// Use inside a `List`.
struct HomeComingSoonCards: View {
    var body: some View {
        ForEach(ComingSoon.homeCards, id: \.self) { placeholder in
            ComingSoonCard(placeholder: placeholder)
        }
    }
}

/// A list section that holds a feature's place on Home until it's built. Nothing in it is tappable.
struct ComingSoonCard: View {
    let placeholder: ComingSoon

    var body: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: placeholder.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
                Text("Coming Soon")
                    .font(.headline)
                Text(placeholder.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        } header: {
            Text(placeholder.title)
        }
        .headerProminence(.increased)
    }
}

#Preview {
    List {
        HomeComingSoonCards()
    }
}
