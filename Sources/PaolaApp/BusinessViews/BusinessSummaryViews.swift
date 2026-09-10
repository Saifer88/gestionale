import PaolaCore
import SwiftData
import SwiftUI

struct ClientBusinessSection: View {
    let client: Client
    @Query private var entries: [LedgerEntry]
    @Query private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]

    private var clientPackages: [LessonPackage] { packages.filter { $0.clientID == client.id } }
    private var availableLessons: Int {
        clientPackages.filter { $0.expiresOn.map { BusinessDates.exclusiveEnd($0) > Date() } ?? true }
            .reduce(0) { $0 + BusinessReports.remaining(package: $1, uses: uses) }
    }

    var body: some View {
        Section {
            if let error = _entries.fetchError ?? _packages.fetchError ?? _uses.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                BalanceLabel(cents: BusinessReports.balance(clientID: client.id, entries: entries))
                LabeledContent("Lezioni residue non scadute", value: "\(availableLessons)")
                NavigationLink {
                    PaymentsView(clientID: client.id)
                } label: {
                    Label("Saldo e cronologia movimenti", systemImage: "eurosign.circle")
                }
                NavigationLink {
                    PackagesView(clientID: client.id)
                } label: {
                    Label("Pacchetti e utilizzi", systemImage: "square.stack.3d.up")
                }
                NavigationLink {
                    ClientSessionsView(clientID: client.id)
                } label: {
                    Label("Storico appuntamenti", systemImage: "calendar")
                }
                NavigationLink {
                    ReportsView(clientID: client.id)
                } label: {
                    Label("Estratto conto ed esportazione", systemImage: "doc.text")
                }
            }
        } header: {
            Text("Lezioni e conto cliente")
        } footer: {
            Text(client.isArchived
                 ? "Il cliente è archiviato: appuntamenti, pacchetti e movimenti restano consultabili. Sono disponibili le rettifiche."
                 : "Gli incassi si registrano con i pacchetti e al completamento delle lezioni senza pacchetto.")
        }
    }
}
