import Foundation
import os

/// Marcatori `os_signpost` per misurare le operazioni lente con Instruments.
///
/// Subsystem `local.paola.gestionale`, categoria dedicata `Performance` (non compare in
/// "Points of Interest"). I nomi sono `StaticString` costanti: nessun dato di cliente,
/// importo o nota entra mai nei messaggi.
public enum PaolaSignpost {
    public static let subsystem = "local.paola.gestionale"
    public static let category = "Performance"
    public static let signposter = OSSignposter(subsystem: subsystem, category: category)

    /// Esegue `body` dentro un intervallo signpost con nome fisso.
    @discardableResult
    public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
