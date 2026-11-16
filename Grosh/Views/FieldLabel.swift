import SwiftUI

/// A form row's title, or an icon alone when `systemImage` is set so VoiceOver still has the field's name.
struct FieldLabel: View {
    let title: LocalizedStringResource
    var systemImage: String?

    var body: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
                .accessibilityLabel(Text(title))
        } else {
            Text(title)
        }
    }
}

/// A form row's leading mark and main content. With an icon-only mark (`systemImage` set), the content is
/// left-aligned in one line; otherwise the mark is a ``LabeledContent`` title and the content stays at the trailing
/// edge, as on other forms.
struct FormFieldRow<Content: View>: View {
    let title: LocalizedStringResource
    var systemImage: String?
    @ViewBuilder let content: () -> Content

    private var compact: Bool { systemImage != nil }

    var body: some View {
        if compact {
            HStack(alignment: .center, spacing: 12) {
                FieldLabel(title: title, systemImage: systemImage)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            LabeledContent(content: content, label: {
                FieldLabel(title: title, systemImage: systemImage)
            })
        }
    }
}
