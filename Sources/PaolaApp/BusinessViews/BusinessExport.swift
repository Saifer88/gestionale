import CoreGraphics
import CoreText
import Foundation
import PaolaCore
import SwiftUI
import UniformTypeIdentifiers

struct BusinessReportSnapshot: Identifiable, Sendable {
    struct Movement: Sendable {
        let id: UUID
        let date: Date
        let client: String
        let kind: String
        let amountCents: Int64
        let method: String
        let notes: String
        let originalID: UUID?
    }

    struct Unpaid: Identifiable, Sendable {
        let id: UUID
        let name: String
        let balance: Int64
        let archived: Bool
    }

    let id = UUID()
    let clientLabel: String
    let from: Date
    let through: Date
    let generatedAt: Date
    let openingBalance: Int64
    let closingBalance: Int64
    let chargedCents: Int64
    let paidCents: Int64
    let refundedCents: Int64
    let creditedCents: Int64
    let workedMinutes: Double
    let completedSessions: Int
    let popularHours: [Int: Int]
    let hourlyIncomeCents: Double?
    let movements: [Movement]
    let unpaid: [Unpaid]
    var warnings: [String] = []

    var plainText: String {
        var lines = [
            "Estratto conto e attività",
            "DOCUMENTO NON FISCALE",
            clientLabel,
            "Periodo: \(BusinessFormatting.day(from)) – \(BusinessFormatting.day(through)) (estremi compresi)",
            "Generato il \(BusinessFormatting.dateTime(generatedAt))",
            "",
            "RIEPILOGO ECONOMICO",
            "Saldo iniziale: \(Money.format(openingBalance))",
            "Addebiti: \(Money.format(chargedCents))",
            "Incassi: \(Money.format(paidCents))",
            "Rimborsi: \(Money.format(refundedCents))",
            "Note di credito: \(Money.format(creditedCents))",
            "Saldo finale: \(Money.format(closingBalance))",
            "Saldo positivo = importo da saldare; negativo = credito del cliente.",
            "",
            "ATTIVITÀ SVOLTA",
            "Lezioni completate: \(completedSessions)",
            "Ore lavorate: \((workedMinutes / 60).formatted(.number.precision(.fractionLength(2))))",
            "Incasso netto per ora: \(hourlyIncomeCents.map { ($0 / 100).formatted(.currency(code: "EUR")) } ?? "Non calcolabile: nessuna ora lavorata")",
            "Il rapporto usa incassi meno rimborsi: pacchetti alla registrazione, lezioni singole al completamento. Nessun secondo incasso sugli utilizzi dei pacchetti. Le sovrapposizioni non raddoppiano le ore lavorate. I movimenti storici restano inclusi.",
            "",
            "ORARI PIÙ FREQUENTI · INIZIO LEZIONI COMPLETATE"
        ]
        if !warnings.isEmpty {
            lines.insert(contentsOf: ["", "ATTENZIONE: DATI DA VERIFICARE"] + warnings + [""], at: 5)
        }
        if popularHours.isEmpty { lines.append("Nessuna lezione completata nel periodo.") }
        for hour in popularHours.keys.sorted() {
            lines.append(String(format: "%02d:00", hour) + ": \(popularHours[hour] ?? 0) lezioni")
        }
        lines += ["", "CLIENTI CON IMPORTI DA SALDARE ALLA DATA FINALE"]
        if unpaid.isEmpty { lines.append("Nessun importo da saldare.") }
        for client in unpaid {
            lines.append("\(client.name)\(client.archived ? " (archiviato)" : ""): \(Money.format(client.balance))")
        }
        lines += ["", "MOVIMENTI DEL PERIODO · \(movements.count)"]
        if movements.isEmpty { lines.append("Nessun movimento nel periodo.") }
        for movement in movements {
            lines += [
                "",
                "\(BusinessFormatting.day(movement.date)) · \(movement.kind) · \(Money.format(movement.amountCents))",
                "Cliente: \(movement.client)"
            ]
            if !movement.method.isEmpty { lines.append("Metodo: \(movement.method)") }
            if !movement.notes.isEmpty { lines.append("Note: \(movement.notes)") }
            lines.append("Riferimento: \(movement.id.uuidString)")
            if let originalID = movement.originalID { lines.append("Rettifica di: \(originalID.uuidString)") }
        }
        lines += ["", "DOCUMENTO NON FISCALE — Prospetto organizzativo, non è una fattura né una ricevuta fiscale."]
        return lines.joined(separator: "\n")
    }
}

struct BusinessExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .pdf] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BusinessInputError(message: "Il documento non contiene un file leggibile.")
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BusinessExport {
    static func csvCell(_ value: String, untrusted: Bool = false) -> String {
        var protected = value
        if untrusted {
            let ignored = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
                .union(CharacterSet(charactersIn: "\u{FEFF}\u{200B}\u{200C}\u{200D}"))
            let meaningful = value.unicodeScalars.drop(while: { ignored.contains($0) })
            let first = meaningful.first
            let startsWithControl = value.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false
            if startsWithControl || first.map({ "=+-@".unicodeScalars.contains($0) }) == true {
                protected = "'" + value
            }
        }
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csv(_ report: BusinessReportSnapshot) -> Data {
        func row(_ cells: [String], untrusted: Set<Int> = []) -> String {
            cells.enumerated().map { csvCell($0.element, untrusted: untrusted.contains($0.offset)) }
                .joined(separator: ";")
        }
        var rows = [
            row(["Sezione", "Data", "Cliente", "Tipo / indicatore", "Importo EUR / valore", "Metodo", "Note", "Riferimento", "Movimento originale"]),
            row(["Documento", "", report.clientLabel, "DOCUMENTO NON FISCALE", "", "",
                 "Prospetto organizzativo, non è una fattura né una ricevuta fiscale.", "", ""], untrusted: [2]),
            row(["Periodo", BusinessFormatting.day(report.from), "", "Dal (compreso)", "", "", "", "", ""]),
            row(["Periodo", BusinessFormatting.day(report.through), "", "Al (compreso)", "", "", "", "", ""])
        ]
        for warning in report.warnings {
            rows.append(row(["Avvertenza", "", "", "Dati da verificare", "", "", warning, "", ""], untrusted: [6]))
        }
        let totals: [(String, Int64)] = [
            ("Saldo iniziale", report.openingBalance), ("Addebiti", report.chargedCents),
            ("Incassi", report.paidCents), ("Rimborsi", report.refundedCents),
            ("Note di credito", report.creditedCents), ("Saldo finale", report.closingBalance)
        ]
        for (title, cents) in totals {
            rows.append(row(["Riepilogo", "", "", title, BusinessFormatting.editableMoney(cents), "", "", "", ""]))
        }
        rows.append(row(["Legenda", "", "", "", "", "",
                         "Saldo positivo: da saldare. Saldo negativo: credito cliente.", "", ""]))
        rows.append(row(["Attività", "", "", "Lezioni completate", "\(report.completedSessions)", "", "", "", ""]))
        rows.append(row(["Attività", "", "", "Ore lavorate",
                         (report.workedMinutes / 60).formatted(.number.locale(Locale(identifier: "it_IT")).precision(.fractionLength(2))),
                         "", "", "", ""]))
        rows.append(row(["Attività", "", "", "Incasso netto per ora",
                         report.hourlyIncomeCents.map {
                             ($0 / 100).formatted(.number.locale(Locale(identifier: "it_IT")).precision(.fractionLength(2)))
                         } ?? "Non calcolabile", "",
                         "Incassi meno rimborsi / ore svolte. Anticipi e incassi di altri periodi alterano il rapporto.", "", ""]))
        for hour in report.popularHours.keys.sorted() {
            rows.append(row(["Orari", "", "", String(format: "%02d:00", hour),
                             "\(report.popularHours[hour] ?? 0)", "", "Inizio lezioni completate", "", ""]))
        }
        for client in report.unpaid {
            rows.append(row(["Da saldare", BusinessFormatting.day(report.through), client.name,
                             "Saldo alla data finale", BusinessFormatting.editableMoney(client.balance),
                             "", client.archived ? "Cliente archiviato" : "", client.id.uuidString, ""], untrusted: [2]))
        }
        for movement in report.movements {
            rows.append(row(["Movimento", BusinessFormatting.day(movement.date), movement.client, movement.kind,
                             BusinessFormatting.editableMoney(movement.amountCents), movement.method,
                             movement.notes, movement.id.uuidString, movement.originalID?.uuidString ?? ""],
                            untrusted: [2, 6]))
        }
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func pdf(_ report: BusinessReportSnapshot) throws -> Data {
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else {
            throw BusinessInputError(message: "Impossibile preparare i dati del PDF.")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                      [kCGPDFContextTitle: "Estratto conto — DOCUMENTO NON FISCALE",
                                       kCGPDFContextCreator: "Paola Gestionale"] as CFDictionary) else {
            throw BusinessInputError(message: "Impossibile creare il documento PDF.")
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)
        ]
        let text = NSAttributedString(string: report.plainText, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let bodyRect = CGRect(x: 44, y: 52, width: mediaBox.width - 88, height: mediaBox.height - 104)
        let path = CGPath(rect: bodyRect, transform: nil)
        var offset = 0
        var pageNumber = 1
        while offset < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else {
                context.closePDF()
                throw BusinessInputError(message: "Il testo non può essere impaginato. Nessun PDF incompleto è stato esportato.")
            }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            drawLine("DOCUMENTO NON FISCALE", at: CGPoint(x: 44, y: mediaBox.height - 30), in: context)
            drawLine("Paola Gestionale · Pagina \(pageNumber)", at: CGPoint(x: 44, y: 27), in: context)
            context.endPDFPage()
            offset += visibleRange.length
            pageNumber += 1
        }
        context.closePDF()
        return buffer as Data
    }

    private static func drawLine(_ value: String, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 9, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.35, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
