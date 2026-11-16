import SwiftUI

/// Shared measurements for the compact Add Transaction form so every row's text starts in the same place.
enum CompactFormLayout {
    static let markSide: CGFloat = 28
    static let markSpacing: CGFloat = 12
    static let horizontalInset: CGFloat = 16
}

/// A form row's title, or an icon alone when `systemImage` is set so VoiceOver still has the field's name.
struct FieldLabel: View {
    let title: LocalizedStringResource
    var systemImage: String?

    var body: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        } else {
            Text(title)
        }
    }
}

extension View {
    /// Fixes the leading mark to the same width on every compact form row.
    func compactFormMarkSlot() -> some View {
        frame(width: CompactFormLayout.markSide, height: CompactFormLayout.markSide, alignment: .center)
    }

    @ViewBuilder
    func compactFormRowChrome(_ compact: Bool) -> some View {
        if compact {
            self
                .listRowInsets(
                    EdgeInsets(
                        top: 11, leading: CompactFormLayout.horizontalInset,
                        bottom: 11, trailing: CompactFormLayout.horizontalInset
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            self
        }
    }
}

/// A form row's leading mark and main content. With an icon-only mark (`systemImage` set), the content is
/// left-aligned in one line; otherwise the mark is a ``LabeledContent`` title and the content stays at the trailing
/// edge, as on other forms. `leading` replaces the default ``FieldLabel`` when the mark should reflect a choice, such
/// as a wallet's colored symbol.
struct FormFieldRow<Content: View>: View {
    let title: LocalizedStringResource
    let compact: Bool
    /// When the row sits inside a list-row ``Button`` or ``NavigationLink``, put ``View/compactFormRowChrome(_:)`` on
    /// that wrapper instead so the form does not pick up a second leading inset.
    let appliesListChrome: Bool
    private let leading: AnyView
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringResource, systemImage: String?, appliesListChrome: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        compact = systemImage != nil
        self.appliesListChrome = appliesListChrome
        leading = AnyView(FieldLabel(title: title, systemImage: systemImage).compactFormMarkSlot())
        self.content = content
    }

    init(
        title: LocalizedStringResource, compact: Bool, appliesListChrome: Bool = true, leading: some View,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.compact = compact
        self.appliesListChrome = appliesListChrome
        self.leading = AnyView(leading.compactFormMarkSlot())
        self.content = content
    }

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .center, spacing: CompactFormLayout.markSpacing) {
                    leading
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent(content: content, label: { leading })
            }
        }
        .compactFormRowChrome(compact && appliesListChrome)
    }
}
