import SwiftUI

/// A form row's title, with an icon beside it when one is given.
struct FieldLabel: View {
    let title: LocalizedStringResource
    var systemImage: String?

    var body: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}
