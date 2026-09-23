import Foundation

/// Calcolo delle "conversioni": dato un incasso lordo, mostra l'incremento del netto a
/// seconda del metodo con cui viene registrato, secondo le stesse regole del riepilogo
/// fiscale (`BusinessReports.taxSummary`) e delle commissioni (`TransactionFee`).
///
/// - Contanti (nero): il netto aumenta del lordo pieno (nessuna tassa, nessuna commissione).
/// - Bianco (contanti bianco): il netto aumenta del lordo meno INPS e imposte.
///     imponibile = lordo × 0,78; inps = imponibile × 0,2607;
///     imposte = (imponibile − inps) × 0,05; incremento = lordo − inps − imposte.
/// - Carta (bianco): come il bianco, meno la commissione carta (1,4% + 0,10 €).
/// - Stripe (bianco): come il bianco, meno la commissione Stripe (1,5% + 0,25 €).
///
/// Tutti gli importi sono in centesimi (Int64). Gli arrotondamenti replicano quelli del
/// riepilogo (Decimal, al centesimo) e delle commissioni.
public enum ConversionRates {

    /// Incremento del netto per un incasso in contanti (nero): pari al lordo.
    public static func cash(_ grossCents: Int64) -> Int64 {
        max(0, grossCents)
    }

    /// Incremento del netto per un incasso bianco in contanti (nessuna commissione).
    public static func white(_ grossCents: Int64) -> Int64 {
        let gross = max(0, grossCents)
        let imponibile = Decimal(gross) * Decimal(string: "0.78")!
        let inps = imponibile * Decimal(string: "0.2607")!
        let imposte = (imponibile - inps) * Decimal(string: "0.05")!
        return gross - roundedCents(inps) - roundedCents(imposte)
    }

    /// Incremento del netto per un incasso bianco con carta: bianco meno commissione carta.
    public static func card(_ grossCents: Int64) -> Int64 {
        white(grossCents) - (TransactionFee.cents(for: max(0, grossCents), method: .card) ?? 0)
    }

    /// Incremento del netto per un incasso bianco con Stripe: bianco meno commissione Stripe.
    public static func stripe(_ grossCents: Int64) -> Int64 {
        white(grossCents) - (TransactionFee.cents(for: max(0, grossCents), method: .stripe) ?? 0)
    }

    private static func roundedCents(_ value: Decimal) -> Int64 {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        if rounded > Decimal(Int64.max) { return Int64.max }
        if rounded < Decimal(Int64.min) { return Int64.min }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
