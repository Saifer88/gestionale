import Foundation

/// Dati fiscali del cedente/prestatore (il professionista) necessari alla fattura
/// elettronica. Non sono segreti crittografici, ma dati personali: restano locali.
/// Le credenziali Aruba (username/password) NON stanno qui: vanno in Keychain.
public struct SellerFiscalProfile: Codable, Equatable, Sendable {
    public var vatNumber: String        // Partita IVA (11 cifre)
    public var taxCode: String          // Codice fiscale
    public var name: String             // Denominazione o nome e cognome
    public var addressStreet: String    // Indirizzo (via e civico)
    public var addressPostalCode: String // CAP
    public var addressCity: String      // Comune
    public var addressProvince: String  // Provincia (sigla)

    public init(vatNumber: String = "", taxCode: String = "", name: String = "",
                addressStreet: String = "", addressPostalCode: String = "",
                addressCity: String = "", addressProvince: String = "") {
        self.vatNumber = vatNumber
        self.taxCode = taxCode
        self.name = name
        self.addressStreet = addressStreet
        self.addressPostalCode = addressPostalCode
        self.addressCity = addressCity
        self.addressProvince = addressProvince
    }

    /// True se tutti i campi obbligatori per emettere una fattura sono presenti e plausibili.
    public var isComplete: Bool {
        validationIssues.isEmpty
    }

    /// Elenco leggibile dei problemi che impediscono l'emissione. Vuoto se il profilo è valido.
    public var validationIssues: [String] {
        var issues: [String] = []
        let vat = vatNumber.trimmingCharacters(in: .whitespaces)
        if !(vat.count == 11 && vat.allSatisfy(\.isNumber)) {
            issues.append("La partita IVA deve avere 11 cifre.")
        }
        if taxCode.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Inserisci il codice fiscale.")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Inserisci la denominazione o il nome.")
        }
        if addressStreet.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Inserisci l'indirizzo.")
        }
        if !(addressPostalCode.trimmingCharacters(in: .whitespaces).count == 5
             && addressPostalCode.trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber)) {
            issues.append("Il CAP deve avere 5 cifre.")
        }
        if addressCity.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Inserisci il comune.")
        }
        if addressProvince.trimmingCharacters(in: .whitespaces).count != 2 {
            issues.append("La provincia deve essere la sigla di 2 lettere.")
        }
        return issues
    }

    /// Normalizza gli spazi e le maiuscole dei campi codificati.
    public func normalized() -> SellerFiscalProfile {
        SellerFiscalProfile(
            vatNumber: vatNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            taxCode: taxCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            name: TextNormalization.spaces(name),
            addressStreet: TextNormalization.spaces(addressStreet),
            addressPostalCode: addressPostalCode.trimmingCharacters(in: .whitespacesAndNewlines),
            addressCity: TextNormalization.spaces(addressCity),
            addressProvince: addressProvince.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        )
    }
}

/// Persistenza locale del profilo fiscale del cedente (JSON in UserDefaults).
/// Iniettabile per i test.
public final class SellerProfileStore {
    private let defaults: UserDefaults
    private let key = "fiscal.sellerProfile"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SellerFiscalProfile {
        guard let data = defaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(SellerFiscalProfile.self, from: data) else {
            return SellerFiscalProfile()
        }
        return profile
    }

    public func save(_ profile: SellerFiscalProfile) {
        let normalized = profile.normalized()
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: key)
        }
    }
}
