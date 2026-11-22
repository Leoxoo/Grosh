import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Account → Import from MoneyLover: picks a MoneyLover CSV export and, once the user confirms "Replace all data",
/// replaces every wallet, Card and transaction with it, keeping the categories. Then shows what was imported.
struct ImportFromMoneyLoverView: View {
    @Environment(\.modelContext) private var context
    /// The currency of a row that names none, and so of its wallet.
    @AppStorage(AppSettings.currencyCode) private var currencyCode
    @State private var isPickingFile = false
    /// The export read from the picked file, waiting for the user to confirm.
    @State private var picked: PickedExport?
    /// The export being imported, from the user's "Replace all data" until the import is done.
    @State private var importing: PickedExport?
    @State private var summary: MoneyLoverImportSummary?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let summary {
                MoneyLoverImportSummarySections(summary: summary)
            } else {
                Section {
                    Button(Strings.ImportExport.chooseCSVFile, systemImage: "doc.badge.plus") {
                        isPickingFile = true
                    }
                    // On the button, so that where the question shows as a popover, it points at the button.
                    .confirmationDialog(
                        Strings.ImportExport.replaceAllDataQuestion,
                        isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
                        titleVisibility: .visible,
                        presenting: picked
                    ) { export in
                        Button(Strings.ImportExport.replaceAllData, role: .destructive) {
                            importing = export
                        }
                        Button(Strings.Common.cancel, role: .cancel) {}
                    } message: { export in
                        Text(Strings.ImportExport.replaceConfirmation(export.export.rows.count, export.fileName))
                    }
                } footer: {
                    Text(Strings.ImportExport.importFooter)
                }
            }
        }
        .navigationTitle(Strings.Screens.importFromMoneyLover)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            read(result)
        }
        // Covering the whole app, tabs included, so that nothing else is changed or saved while the import's
        // changes wait unsaved in the context.
        .fullScreenCover(isPresented: Binding(get: { importing != nil }, set: { _ in })) {
            if let importing {
                ImportProgressScreen(export: importing.export, done: finish)
            }
        }
        .errorAlert(Strings.ImportExport.couldntImport, message: $errorMessage)
    }

    /// Reads the picked file and checks it is a MoneyLover export before asking to replace anything.
    private func read(_ result: Result<URL, Error>) {
        Log.importing.perform("Reading the picked file", errorMessage: &errorMessage, expected: true) {
            let url = try result.get()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            picked = PickedExport(
                fileName: url.lastPathComponent, export: try MoneyLoverCSV.read(data, currencyCode: currencyCode)
            )
        }
    }

    /// Shows what the import did, or why it couldn't be done, once it is over.
    private func finish(_ result: Result<MoneyLoverImportSummary, any Error>) {
        Log.importing.perform("Importing from MoneyLover", errorMessage: &errorMessage) {
            summary = try result.get()
        }
        importing = nil
    }
}

/// "Replace all data" under way: a progress bar, moved on between the import's steps (``MoneyLoverImport/Run``). The
/// import starts once the screen is up and runs on the main actor, handing it back for a moment after each step so the
/// bar is drawn. Nothing new can be drawn during the save, the last and longest step, so a spinner, which the system
/// keeps turning meanwhile, shows the app is still at work.
private struct ImportProgressScreen: View {
    let export: MoneyLoverExport
    let done: (Result<MoneyLoverImportSummary, any Error>) -> Void
    @Environment(\.modelContext) private var context
    @State private var fractionDone = 0.0
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: fractionDone) {
                Text(isSaving ? Strings.ImportExport.saving : Strings.ImportExport.importing)
            } currentValueLabel: {
                Text(fractionDone, format: .percent.precision(.fractionLength(0)))
            }
            .progressViewStyle(.linear)
            ProgressView()
                .opacity(isSaving ? 1 : 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled()
        .task { await run() }
    }

    private func run() async {
        do {
            let run = try MoneyLoverImport.Run(export: export, cards: .ownersCards, in: context)
            while true {
                fractionDone = run.fractionDone
                isSaving = run.isSaving
                // Not cancellable: a run left halfway would leave its changes unsaved in the context.
                try? await Task.sleep(for: .milliseconds(15))
                if let summary = try run.next() {
                    done(.success(summary))
                    return
                }
            }
        } catch {
            done(.failure(error))
        }
    }
}

/// A MoneyLover export read from a file the user picked.
private struct PickedExport {
    let fileName: String
    let export: MoneyLoverExport
}

#Preview {
    NavigationStack {
        ImportFromMoneyLoverView()
    }
    .modelContainer(try! StoreOpening.open(inMemory: true))
}
