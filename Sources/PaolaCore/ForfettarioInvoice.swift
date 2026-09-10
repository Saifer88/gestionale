import Foundation

/// Costanti fiscali per il regime forfettario usate nella fattura elettronica.
public enum ForfettarioTax {
    /// Aliquota della rivalsa previdenziale INPS gestione separata, in percentuale.
    public static let cassaPercent = 4
    /// Tipo cassa previdenziale FatturaPA per INPS gestione separata.
    public static let cassaType = "TC22"
    /// Codice Natura IVA per operazione non soggetta in regime forfettario.
    public static let naturaCode = "N2.2"
    /// Dicitura di legge (RiferimentoNormativo) per il regime forfettario.
    public static let riferimentoNormativo =
        "Operazione senza applicazione dell'IVA, ai sensi dell'articolo 1, commi da 54 a 89, della Legge n. 190/2014 e successive modificazioni"
    /// Codice destinatario SDI per clienti senza PEC/codice destinatario.
    public static let defaultRecipientCode = "0000000"
    /// Codice fiscale dell'intermediario Aruba PEC che trasmette la fattura.
    /// Richiesto come IdTrasmittente/IdCodice: il controllo SDI 0094 rifiuta
    /// qualsiasi altro valore quando si trasmette tramite Aruba.
    public static let arubaTransmitterCode = "01879020517"
}

/// Ripartizione economica di una fattura forfettaria a partire dal totale incassato.
///
/// La rivalsa INPS 4% concorre all'imponibile: il cliente paga `totalCents`, di cui
/// `taxableCents` è l'imponibile e `contributionCents` è la rivalsa 4%.
/// Tutto in centesimi interi (nessun floating point).
public struct ForfettarioBreakdown: Equatable, Sendable {
    /// Imponibile della prestazione (base su cui si calcola la rivalsa).
    public let taxableCents: Int64
    /// Rivalsa previdenziale INPS 4%.
    public let contributionCents: Int64
    /// Totale a carico del cliente (imponibile + rivalsa).
    public let totalCents: Int64

    public init(taxableCents: Int64, contributionCents: Int64, totalCents: Int64) {
        self.taxableCents = taxableCents
        self.contributionCents = contributionCents
        self.totalCents = totalCents
    }

    /// Calcola la ripartizione a partire dal totale incassato (comprensivo della rivalsa).
    ///
    /// imponibile = round(totale / 1,04); rivalsa = totale − imponibile.
    /// L'arrotondamento è half-up al centesimo; la rivalsa è la differenza esatta,
    /// così `taxable + contribution == total` sempre, senza errori di arrotondamento.
    public static func from(totalCents: Int64) throws -> ForfettarioBreakdown {
        guard totalCents >= 0 else {
            throw BusinessError.invalidInput("Il totale della fattura non può essere negativo.")
        }
        // imponibile = totale / 1,04 = totale * 100 / 104, arrotondato half-up.
        let numerator = try BusinessRules.multiply(totalCents, 100)
        let denominator: Int64 = 100 + Int64(ForfettarioTax.cassaPercent) // 104
        let taxable = (numerator + denominator / 2) / denominator
        let contribution = try BusinessRules.subtract(totalCents, taxable)
        return ForfettarioBreakdown(taxableCents: taxable,
                                    contributionCents: contribution,
                                    totalCents: totalCents)
    }
}
