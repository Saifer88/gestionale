import PaolaCore
import SwiftUI

/// Sezione "Credenziali e fatturazione": dati fiscali del cedente (locali) e
/// credenziali del servizio Aruba (Keychain). Usata per la fattura elettronica.
struct CredentialsView: View {
    @State private var profile = SellerFiscalProfile()
    @State private var username = ""
    @State private var password = ""
    @State private var saved = false

    private let profileStore = SellerProfileStore()
    private let credentialsStore = ArubaCredentialsStore(secrets: KeychainSecretStore())

    var body: some View {
        Form {
            Section {
                TextField("Denominazione o nome e cognome", text: $profile.name)
                    .accessibilityIdentifier("seller.name")
                TextField("Partita IVA", text: $profile.vatNumber)
                    .accessibilityIdentifier("seller.vat")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("Codice fiscale", text: $profile.taxCode)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("seller.taxCode")
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
            } header: {
                Text("Dati fiscali (cedente)")
            } footer: {
                Text("Regime forfettario. Questi dati compaiono nella fattura elettronica come cedente/prestatore. Restano salvati solo su questo dispositivo.")
            }

            Section("Indirizzo del cedente") {
                TextField("Indirizzo (via e civico)", text: $profile.addressStreet)
                    .accessibilityIdentifier("seller.street")
                TextField("CAP", text: $profile.addressPostalCode)
                    .accessibilityIdentifier("seller.cap")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("Comune", text: $profile.addressCity)
                    .accessibilityIdentifier("seller.city")
                TextField("Provincia (sigla)", text: $profile.addressProvince)
                    .accessibilityIdentifier("seller.province")
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
            }

            if !profile.validationIssues.isEmpty {
                Section {
                    ForEach(profile.validationIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Completa i dati per poter emettere fatture elettroniche.")
                }
            }

            Section {
                TextField("Username servizio (es. 123456@aruba.it)", text: $username)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("aruba.username")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password servizio", text: $password)
                    .accessibilityIdentifier("aruba.password")
            } header: {
                Text("Credenziali Aruba")
            } footer: {
                Text("Salvate nel Keychain del dispositivo. \(AppEnvironment.usesArubaDemo ? "Questa build usa l'ambiente demo di Aruba." : "Questa build usa l'ambiente di produzione di Aruba.")")
            }
        }
        .formStyle(.grouped)
        .sectionTitle("Credenziali e fatturazione", symbol: "key")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: save)
                    .accessibilityIdentifier("credentials.save")
            }
        }
        .onAppear {
            profile = profileStore.load()
            let credentials = credentialsStore.load()
            username = credentials.username
            password = credentials.password
        }
        .alert("Salvato", isPresented: $saved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Dati fiscali e credenziali aggiornati.")
        }
    }

    private func save() {
        profileStore.save(profile)
        profile = profileStore.load()
        try? credentialsStore.save(ArubaCredentials(username: username, password: password))
        saved = true
    }
}
