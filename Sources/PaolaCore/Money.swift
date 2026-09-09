import Foundation

public enum Money {
    public static func parse(_ text: String) throws -> Int64 {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "." })
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.count == 1 || parts[1].count <= 2 else {
            throw BusinessError.invalidInput("Importo non valido: usare al massimo due decimali, senza separatori delle migliaia.")
        }
        var cents: Int64 = 0
        let decimals = parts.count == 2 ? String(parts[1]) : ""
        for digit in (String(parts[0]) + decimals + String(repeating: "0", count: 2 - decimals.count)).utf8 {
            let multiplied = cents.multipliedReportingOverflow(by: 10)
            guard !multiplied.overflow else { throw BusinessError.arithmeticOverflow }
            cents = try BusinessRules.add(multiplied.partialValue, Int64(digit - 48))
        }
        return cents
    }

    public static func format(_ cents: Int64) -> String {
        let magnitude = cents.magnitude
        let euros = String(magnitude / 100)
        var grouped = ""
        for (index, digit) in euros.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(".") }
            grouped.append(digit)
        }
        let fraction = magnitude % 100
        return "\(cents < 0 ? "-" : "")\(String(grouped.reversed())),\(fraction < 10 ? "0" : "")\(fraction) €"
    }
}
