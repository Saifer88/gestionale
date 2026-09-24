import Foundation

/// Calcolo delle "conversioni": dato un incasso lordo, mostra l'incremento del netto a
/// seconda del metodo con cui viene registrato, secondo le stesse regole del riepilogo
/// fiscale (`BusinessReports.taxSummary`) e delle commissioni (`TransactionFee`).
///
/// - Contanti (nero): il netto aumenta del lordo pieno (nessuna tassa, nessuna commissione).
/// - Bianco (contanti bianco): si rimuove prima il 4% dal lordo, poi INPS e imposte.
///     base = lordo × 0,96; imponibile = base × 0,78; inps = imponibile × 0,2607;
///     imposte = (imponibile − inps) × 0,05; incremento = base − inps − imposte.
/// - Carta (bianco): come il bianco, meno la commissione carta (1,4% + 0,10 €).
/// - Stripe (bianco): come il bianco, meno la commissione Stripe (1,5% + 0,25 €).
///
/// Tutti gli importi sono in centesimi (Int64). Gli arrotondamenti replicano quelli del
/// riepilogo (Decimal, al centesimo) e delle commissioni.
public enum ConversionRates {

    /// Quota rimossa dal lordo prima del calcolo fiscale del bianco (4%).
    private static let whiteDeduction = Decimal(string: "0.96")!

    /// Incremento del netto per un incasso in contanti (nero): pari al lordo.
    public static func cash(_ grossCents: Int64) -> Int64 {
        max(0, grossCents)
    }

    /// Incremento del netto per un incasso bianco in contanti (nessuna commissione).
    /// Prima si toglie il 4% dal lordo, poi si applicano INPS e imposte sulla base ridotta.
    public static func white(_ grossCents: Int64) -> Int64 {
        let gross = max(0, grossCents)
        let base = Decimal(gross) * whiteDeduction
        let baseCents = roundedCents(base)
        let imponibile = base * Decimal(string: "0.78")!
        let inps = imponibile * Decimal(string: "0.2607")!
        let imposte = (imponibile - inps) * Decimal(string: "0.05")!
        return baseCents - roundedCents(inps) - roundedCents(imposte)
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

    // MARK: - Spiegazioni (tooltip su hover): operazioni una per riga.

    // Ogni riga tooltip: 3 colonne separate da "\t" (operatore, descrizione, formula/valore).
    // Riga con operatore "=" è il totale (in grassetto).

    /// Intestazione colonna Bianco.
    public static var whiteFormula: String {
        [
            "\tLordo\t",
            "-\trivalsa INPS\tLordo × 4%",
            "×\tcoefficiente redditività\t(Lordo − Rivalsa Inps) × 78%",
            "-\tinps\t(Lordo − Rivalsa Inps) × Coeff. redditività × 26,07%",
            "-\timposte\t(imponibile − Inps) × 5%"
        ].joined(separator: "\n")
    }
    /// Intestazione colonna Carta.
    public static var cardFormula: String {
        whiteFormula + "\n" + "-\tspese carta\tLordo × 1,4% + 0,10 €"
    }
    /// Intestazione colonna Stripe.
    public static var stripeFormula: String {
        whiteFormula + "\n" + "-\tspese stripe\tLordo × 1,5% + 0,25 €"
    }

    /// Passaggi reali per una cella "bianco".
    public static func whiteSteps(_ grossCents: Int64) -> String {
        let d = detail(grossCents)
        return [
            "\tLordo\t\(euro(d.gross))",
            "-\trivalsa INPS\t\(euro(d.fourPercent))",
            "×\tcoefficiente redditività\t\(euro(d.imponibile))",
            "-\tinps\t\(euro(d.inps))",
            "-\timposte\t\(euro(d.imposte))",
            "=\t\t\(euro(white(grossCents)))"
        ].joined(separator: "\n")
    }

    /// Passaggi reali per una cella "carta".
    public static func cardSteps(_ grossCents: Int64) -> String {
        let d = detail(grossCents)
        let fee = TransactionFee.cents(for: d.gross, method: .card) ?? 0
        return [
            "\tLordo\t\(euro(d.gross))",
            "-\trivalsa INPS\t\(euro(d.fourPercent))",
            "×\tcoefficiente redditività\t\(euro(d.imponibile))",
            "-\tinps\t\(euro(d.inps))",
            "-\timposte\t\(euro(d.imposte))",
            "-\tspese carta\t\(euro(fee))",
            "=\t\t\(euro(card(grossCents)))"
        ].joined(separator: "\n")
    }

    /// Passaggi reali per una cella "Stripe".
    public static func stripeSteps(_ grossCents: Int64) -> String {
        let d = detail(grossCents)
        let fee = TransactionFee.cents(for: d.gross, method: .stripe) ?? 0
        return [
            "\tLordo\t\(euro(d.gross))",
            "-\trivalsa INPS\t\(euro(d.fourPercent))",
            "×\tcoefficiente redditività\t\(euro(d.imponibile))",
            "-\tinps\t\(euro(d.inps))",
            "-\timposte\t\(euro(d.imposte))",
            "-\tspese stripe\t\(euro(fee))",
            "=\t\t\(euro(stripe(grossCents)))"
        ].joined(separator: "\n")
    }

    /// Componenti del calcolo bianco per un lordo (centesimi).
    private static func detail(_ grossCents: Int64) -> (gross: Int64, fourPercent: Int64, imponibile: Int64, inps: Int64, imposte: Int64) {
        let gross = max(0, grossCents)
        let baseCents = roundedCents(Decimal(gross) * whiteDeduction)
        let fourPercent = gross - baseCents
        let base = Decimal(gross) * whiteDeduction
        let imponibileDec = base * Decimal(string: "0.78")!
        let imponibile = roundedCents(imponibileDec)
        let inps = roundedCents(imponibileDec * Decimal(string: "0.2607")!)
        let imposte = roundedCents((imponibileDec - Decimal(inps)) * Decimal(string: "0.05")!)
        return (gross, fourPercent, imponibile, inps, imposte)
    }

    private static func euro(_ cents: Int64) -> String { Money.format(cents) }
}
