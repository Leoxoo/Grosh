import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension View {
    /// Presents Text them for `reminder` while it is set: the Messages compose sheet with the number and the message
    /// filled in, or, where texting isn't available, the message to copy or share. Nothing is sent without the user's
    /// tap on Send.
    func textThemSheet(_ reminder: Binding<TextReminder?>) -> some View {
        sheet(item: reminder) { reminder in
            TextThemSheet(reminder: reminder)
        }
    }
}

/// What Text them opens. It asks the Domain where the message goes (``TextReminder/delivery(canSendText:using:)``):
/// Messages, prefilled, when this device can text and the Person has a number (their contact's current one when it
/// resolves), otherwise the message itself with Copy and Share.
private struct TextThemSheet: View {
    let reminder: TextReminder

    @Environment(\.dismiss) private var dismiss
    @State private var delivery: TextDelivery?

    var body: some View {
        Group {
            switch delivery {
            case nil:
                ProgressView()
            case .compose(let phone, let text)?:
                composer(to: phone, saying: text)
            case .copyOrShare(let text)?:
                CopyOrShare(personName: reminder.personName, text: text) { dismiss() }
            }
        }
        .task {
            delivery = await reminder.delivery(canSendText: MessageComposer.canSendText, using: SystemContacts())
        }
    }

    @ViewBuilder
    private func composer(to phone: String, saying text: String) -> some View {
        #if canImport(MessageUI)
        MessageComposeView(phone: phone, body: text) { dismiss() }
            .ignoresSafeArea()
        #else
        CopyOrShare(personName: reminder.personName, text: text) { dismiss() }
        #endif
    }
}

/// Whether this device can send a text at all: not the simulator, nor an iPad without Messages.
private enum MessageComposer {
    static var canSendText: Bool {
        #if canImport(MessageUI)
        MFMessageComposeViewController.canSendText()
        #else
        false
        #endif
    }
}

/// The message for a device that can't text: shown to read, copy or share.
private struct CopyOrShare: View {
    let personName: String
    let text: String
    let onDone: () -> Void

    @State private var hasCopied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(text)
                        .textSelection(.enabled)
                } footer: {
                    Text("This device can't text \(personName) from here. Copy the message or share it instead.")
                }
                Section {
                    Button {
                        copy(text)
                        hasCopied = true
                    } label: {
                        if hasCopied {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    ShareLink(item: text)
                }
            }
            .navigationTitle("Text \(personName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 300, idealHeight: 360)
        #endif
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#if canImport(MessageUI)
/// The Messages compose sheet, to `phone` with `body` filled in. It sends only when the user taps Send; `onFinish` runs
/// whether they sent or cancelled.
private struct MessageComposeView: UIViewControllerRepresentable {
    let phone: String
    let body: String
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [phone]
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult
        ) {
            onFinish()
        }
    }
}
#endif
