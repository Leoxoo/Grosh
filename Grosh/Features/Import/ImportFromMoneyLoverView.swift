import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Account → Import from MoneyLover: picks a MoneyLover CSV export and, once the user confirms "Replace all data",
/// replaces every wallet, Card and transaction with it, keeping the categories. Then shows what was imported.
struct ImportFromMoneyLoverView: View {
    @Environment(\.modelContext) private var context
    @State private var isPickingFile = false
    /// The export read from the picked file, waiting for the user to confirm.
    @State private var picked: PickedExport?
    @State private var isImporting = false
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
        .confirmationDialog(
            Strings.ImportExport.replaceAllDataQuestion,
            isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
            titleVisibility: .visible,
            presenting: picked
        ) { export in
            Button(Strings.ImportExport.replaceAllData, role: .destructive) {
                replaceAllData(with: export)
            }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: { export in
            Text(Strings.ImportExport.replaceConfirmation(export.rows.count, export.fileName))
        }
        .disabled(isImporting)
        .overlay {
            if isImporting {
                ProgressView(Strings.ImportExport.importing)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .transition(.opacity)
            }
        }
        .errorAlert(Strings.ImportExport.couldntImport, message: $errorMessage)
    }

    /// Reads the picked file and checks it is a MoneyLover export before asking to replace anything.
    private func read(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            picked = PickedExport(fileName: url.lastPathComponent, rows: try MoneyLoverCSV.rows(in: text))
        } catch {
            Log.importing.failed("Reading the picked file", error, expected: true)
            errorMessage = error.localizedDescription
        }
    }

    /// Shows "Importing…", then imports `export` once it has finished appearing. The import holds the main actor
    /// until it is done, so nothing new is drawn meanwhile: started any sooner, it would run before the progress is on
    /// screen.
    private func replaceAllData(with export: PickedExport) {
        withAnimation {
            isImporting = true
        } completion: {
            do {
                summary = try MoneyLoverImport.replaceAllData(with: export.rows, in: context)
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

/// A MoneyLover export read from a file the user picked.
private struct PickedExport {
    let fileName: String
    let rows: [MoneyLoverRow]
}

#Preview {
    NavigationStack {
        ImportFromMoneyLoverView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
