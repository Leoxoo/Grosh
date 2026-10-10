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
                    Button("Choose CSV File…", systemImage: "doc.badge.plus") {
                        isPickingFile = true
                    }
                } footer: {
                    Text("Replaces every wallet, Card and transaction with those in a MoneyLover CSV export. Your categories are kept.")
                }
            }
        }
        .navigationTitle("Import from MoneyLover")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            read(result)
        }
        .confirmationDialog(
            "Replace all data?",
            isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
            titleVisibility: .visible,
            presenting: picked
        ) { export in
            Button("Replace All Data", role: .destructive) {
                replaceAllData(with: export)
            }
            Button("Cancel", role: .cancel) {}
        } message: { export in
            Text("Every wallet, Card and transaction will be deleted and replaced with the \(export.rows.count) transactions in \(export.fileName). Categories are kept. This can't be undone.")
        }
        .disabled(isImporting)
        .overlay {
            if isImporting {
                ProgressView("Importing…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .errorAlert("Couldn't Import", message: $errorMessage)
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
            errorMessage = error.localizedDescription
        }
    }

    private func replaceAllData(with export: PickedExport) {
        isImporting = true
        Task {
            // Lets "Importing…" appear before the import holds the main actor for a moment.
            try? await Task.sleep(for: .milliseconds(100))
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
    .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
