import PaolaCore
import SwiftUI

struct AdditionalParticipantDraft: Identifiable {
    let id = UUID()
    var clientID: UUID?
    var packageID: UUID?
    var rateID: UUID?
    var price = "0,00"
}

enum SessionPackageChoices {
    static func usable(_ package: LessonPackage, clientID: UUID?, date: Date, uses: [PackageUse]) -> Bool {
        package.clientID == clientID && package.purchasedOn <= date
            && (package.expiresOn.map { BusinessDates.exclusiveEnd($0) > date } ?? true)
            && BusinessReports.remaining(package: package, uses: uses) > 0
    }

    static func available(
        clientID: UUID?, selectedID: UUID?, date: Date, packages: [LessonPackage], uses: [PackageUse]
    ) -> [LessonPackage] {
        packages.filter {
            $0.clientID == clientID && ($0.id == selectedID || usable($0, clientID: clientID, date: date, uses: uses))
        }.sorted { $0.purchasedOn < $1.purchasedOn }
    }

    static func label(_ package: LessonPackage, uses: [PackageUse]) -> String {
        "Pacchetto del \(BusinessFormatting.day(package.purchasedOn)) · \(BusinessReports.remaining(package: package, uses: uses))/\(package.capacity) residue"
            + (package.expiresOn.map { " · scade \(BusinessFormatting.day($0))" } ?? " · senza scadenza")
    }
}

struct AdditionalParticipantEditor: View {
    @Binding var person: AdditionalParticipantDraft
    let number: Int
    let clients: [Client]
    let tariffs: [ServiceRateDraft]
    let packages: [LessonPackage]
    let uses: [PackageUse]
    let startDate: Date
    let onClientChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Section("Partecipante \(number)") {
            BusinessClientPicker(title: "Cliente", clients: clients, selection: Binding(
                get: { person.clientID },
                set: { person.clientID = $0; onClientChange() }
            ))
            .accessibilityIdentifier("session.client\(number)")
            if person.clientID != nil {
                Picker("Pacchetto in uso", selection: $person.packageID) {
                    Text("No").tag(nil as UUID?)
                    ForEach(SessionPackageChoices.available(
                        clientID: person.clientID, selectedID: person.packageID, date: startDate, packages: packages, uses: uses
                    )) { package in
                        Text(SessionPackageChoices.label(package, uses: uses)).tag(Optional(package.id))
                    }
                }
                .accessibilityIdentifier("session.package\(number)")
                if person.packageID == nil {
                    Picker("Tariffa", selection: Binding(
                        get: { person.rateID },
                        set: { id in
                            person.rateID = id
                            if let tariff = tariffs.first(where: { $0.id == id }) {
                                person.price = BusinessFormatting.editableMoney(tariff.priceCents)
                            }
                        }
                    )) {
                        Text("Prezzo personalizzato").tag(nil as UUID?)
                        ForEach(tariffs) { tariff in
                            Text("\(tariff.name) · \(Money.format(tariff.priceCents))").tag(Optional(tariff.id))
                        }
                    }
                    .accessibilityIdentifier("session.tariff\(number)")
                }
                MoneyField(title: "Prezzo concordato (€)", text: $person.price)
                    .disabled(person.packageID != nil)
                    .accessibilityIdentifier("session.price\(number)")
            }
            Button("Rimuovi partecipante", systemImage: "person.badge.minus", role: .destructive, action: onRemove)
                .accessibilityIdentifier("session.removeParticipant\(number)")
        }
        .onChange(of: person.price) { _, text in
            if let tariff = tariffs.first(where: { $0.id == person.rateID }),
               text != BusinessFormatting.editableMoney(tariff.priceCents) {
                person.rateID = nil
            }
        }
    }
}
