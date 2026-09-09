import Foundation
import PaolaCore

struct BusinessInputError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum BusinessFormatting {
    static func editableMoney(_ cents: Int64) -> String {
        let magnitude = cents.magnitude
        let sign = cents < 0 ? "-" : ""
        return "\(sign)\(magnitude / 100),\(String(format: "%02d", Int(magnitude % 100)))"
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "it_IT")))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "it_IT")))
    }

    static func balanceTitle(_ cents: Int64) -> String {
        cents > 0 ? "Da saldare" : cents < 0 ? "Credito cliente" : "Saldo in pari"
    }

    static func balanceAmount(_ cents: Int64) -> String {
        cents == Int64.min ? Money.format(cents) : Money.format(abs(cents))
    }
}
