#if os(macOS) || os(iOS)
import Foundation
import PaolaCore
import SwiftData
import SwiftUI

/// Coordinatore dell'invio della fattura elettronica.
///
/// Orchestra la sequenza completa: validazione dei dati fiscali (cedente, credenziali
/// Aruba, dati del cliente), creazione della fattura in bozza tramite `BusinessRepository`
/// (idempotente), generazione dell'XML FatturaPA e trasmissione ad Aruba, con
/// aggiornamento dello stato dell'`Invoice`.
///
/// Non modifica la logica di dominio: usa i pezzi esistenti. Non logga mai credenziali,
/// segreti o il corpo dell'XML.
@MainActor
final class InvoiceSender: ObservableObject {
    /// Fase dell'invio pubblicata alla UI.
    enum Phase: Equatable {
        case idle
        case creating
        case sending
        case done(InvoiceStatus)
        case failed(String)
    }

    @Published var phase: Phase = .idle

    private let profileStore: SellerProfileStore
    private let credentialsStore: ArubaCredentialsStore

    init(profileStore: SellerProfileStore = SellerProfileStore(),
         credentialsStore: ArubaCredentialsStore = ArubaCredentialsStore(secrets: KeychainSecretStore())) {
        self.profileStore = profileStore
        self.credentialsStore = credentialsStore
    }

    var isBusy: Bool {
        switch phase {
        case .creating, .sending: return true
        default: return false
        }
    }

    // MARK: - API pubblica

    /// Emette e invia la fattura per l'incasso della lezione singola di un partecipante.
    func sendSessionInvoice(context: ModelContext, sessionID: UUID, clientID: UUID,
                            client: Client, issueDate: Date, lineDescription: String) async {
        await send(client: client, issueDate: issueDate, lineDescription: lineDescription) { repo in
            try repo.createInvoiceForSession(sessionID: sessionID, clientID: clientID, issueDate: issueDate)
        } context: { context }
    }

    /// Emette e invia la fattura per l'acquisto di un pacchetto.
    func sendPackageInvoice(context: ModelContext, packageID: UUID,
                            client: Client, issueDate: Date, lineDescription: String) async {
        await send(client: client, issueDate: issueDate, lineDescription: lineDescription) { repo in
            try repo.createInvoiceForPackage(packageID: packageID, issueDate: issueDate)
        } context: { context }
    }

    // MARK: - Sequenza comune

    private func send(client: Client, issueDate: Date, lineDescription: String,
                      create: (BusinessRepository) throws -> UUID,
                      context: () -> ModelContext) async {
        // (a) Validazione dei dati fiscali prima di procedere.
        let profile = profileStore.load()
        let credentials = credentialsStore.load()
        if let message = validationMessage(profile: profile, credentials: credentials, client: client) {
            phase = .failed(message)
            return
        }

        let modelContext = context()
        let repo = BusinessRepository(context: modelContext)

        // (b) Creazione della fattura in bozza (idempotente).
        phase = .creating
        let invoiceID: UUID
        do {
            invoiceID = try create(repo)
        } catch {
            phase = .failed(creationMessage(for: error))
            return
        }

        // (c) Recupero dell'Invoice appena creata.
        guard let invoice = fetchInvoice(id: invoiceID, in: modelContext) else {
            phase = .failed("Fattura creata ma non più recuperabile dall'archivio.")
            return
        }

        // (d) Costruzione dell'input FatturaPA.
        let progressive = String(invoice.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
        let seller = FatturaPAParty(
            name: profile.name,
            taxCode: profile.taxCode,
            vatNumber: profile.vatNumber,
            address: profile.addressStreet,
            postalCode: profile.addressPostalCode,
            city: profile.addressCity,
            province: profile.addressProvince,
            country: "IT"
        )
        let buyer = FatturaPAParty(
            name: client.fullName,
            taxCode: client.taxCode,
            vatNumber: nil,
            address: client.billingAddress,
            postalCode: "",
            city: "",
            province: "",
            country: "IT"
        )
        let breakdown = ForfettarioBreakdown(
            taxableCents: invoice.taxableCents,
            contributionCents: invoice.contributionCents,
            totalCents: invoice.totalCents
        )
        let input = FatturaPAInput(
            seller: seller,
            buyer: buyer,
            breakdown: breakdown,
            issueDate: invoice.issueDate,
            paymentMethod: invoice.paymentMethod,
            lineDescription: lineDescription,
            transmissionProgressive: progressive,
            recipientCode: ForfettarioTax.defaultRecipientCode
        )

        // (e) Generazione dell'XML.
        let xml: String
        do {
            xml = try FatturaPAXMLBuilder.build(input)
        } catch {
            invoice.status = .failed
            invoice.errorMessage = error.localizedDescription
            invoice.updatedAt = Date()
            saveQuietly(modelContext)
            phase = .failed(error.localizedDescription)
            return
        }

        // (f)/(g) Invio ad Aruba e aggiornamento dello stato.
        phase = .sending
        let fileName = "IT\(profile.vatNumber)_\(progressive).xml"
        let arubaClient = ArubaClient(credentials: credentials)
        do {
            try await arubaClient.authenticate()
            let arubaID = try await arubaClient.upload(xml: xml, fileName: fileName)
            invoice.arubaInvoiceId = arubaID
            invoice.status = .transmitted
            invoice.errorMessage = nil
            invoice.updatedAt = Date()
            saveQuietly(modelContext)
            phase = .done(.transmitted)
        } catch {
            invoice.status = .failed
            invoice.errorMessage = error.localizedDescription
            invoice.updatedAt = Date()
            saveQuietly(modelContext)
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Supporto

    /// Verifica i prerequisiti fiscali. Ritorna un messaggio se qualcosa manca, altrimenti nil.
    private func validationMessage(profile: SellerFiscalProfile,
                                   credentials: ArubaCredentials,
                                   client: Client) -> String? {
        if !profile.isComplete {
            let issues = profile.validationIssues.joined(separator: " ")
            return "Completa i dati fiscali del cedente nella sezione Credenziali. " + issues
        }
        if !credentials.isComplete {
            return "Credenziali Aruba mancanti. Inseriscile nella sezione Credenziali."
        }
        if client.taxCode.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Il cliente non ha un codice fiscale. Aggiungilo nell'anagrafica."
        }
        if client.billingAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Il cliente non ha un indirizzo di fatturazione. Aggiungilo nell'anagrafica."
        }
        return nil
    }

    /// Traduce l'errore di creazione della fattura in un messaggio per la UI.
    /// `BusinessError` non è `Equatable`: si intercettano i casi con `if case`.
    private func creationMessage(for error: Error) -> String {
        if case BusinessError.alreadyInvoiced = error {
            return "Per questo incasso è già stata creata una fattura elettronica."
        }
        if case BusinessError.notInvoiceable(let reason) = error {
            return reason
        }
        return error.localizedDescription
    }

    private func fetchInvoice(id: UUID, in context: ModelContext) -> Invoice? {
        let descriptor = FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    private func saveQuietly(_ context: ModelContext) {
        do { try context.save() } catch { /* stato aggiornato in memoria; nessun segreto loggato */ }
    }
}
#endif
