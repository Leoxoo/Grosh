import SwiftData
import SwiftUI

/// Account → Export CSV: writes every transaction to a CSV file (``GroshCSVExport``) and shares it through the system
/// share sheet. Import from MoneyLover restores the file with "Replace all data".
struct ExportCSVView: View {
    @Environment(\.modelContext) private var context
    /// The written file, once it is ready to share.
    @State private var file: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if let file {
                    ShareLink(item: file) {
                        Label("Share CSV File…", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Every transaction in MoneyLover's CSV format, with its Card and the transactions it is linked to. Import from MoneyLover restores it with “Replace all data”.")
            }
        }
        .navigationTitle("Export CSV")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            write()
        }
        .errorAlert("Couldn't Export", message: $errorMessage)
    }

    /// Writes the export to a temporary file named for today.
    private func write() {
        do {
            let url = URL.temporaryDirectory.appending(path: GroshCSVExport.fileName(on: .today))
            try GroshCSVExport.csv(in: context).write(to: url, atomically: true, encoding: .utf8)
            file = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ExportCSVView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
