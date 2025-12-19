import SwiftUI

struct ContentView: View {
    @State var scanManager: ScanManager
    @State private var selectedFindingID: String?

    private var selectedFinding: Finding? {
        guard let id = selectedFindingID else { return nil }
        return scanManager.allFindings.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            // Findings list (main panel)
            FindingsTableView(
                scanManager: scanManager,
                selectedFindingID: $selectedFindingID
            )
            .frame(minWidth: 450)

            // Detail panel
            Group {
                if let finding = selectedFinding {
                    FindingDetailView(
                        finding: finding,
                        isDismissed: scanManager.dismissedStore.isDismissed(finding),
                        onDismiss: { scanManager.dismiss(finding) },
                        onRestore: { scanManager.restore(finding) }
                    )
                } else {
                    EmptyDetailView()
                }
            }
            .frame(minWidth: 280, idealWidth: 320)
        }
        .onAppear {
            scanManager.startScheduledScanning()
        }
    }
}

#Preview {
    ContentView(scanManager: ScanManager())
}
