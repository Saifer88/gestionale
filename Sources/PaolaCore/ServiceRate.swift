import Foundation
import SwiftData

@Model public final class ServiceRate {
    public var id: UUID = UUID()
    public var serviceID: UUID = UUID()
    public var name: String = "Standard"
    public var priceCents: Int64 = 0
    public var sortOrder: Int = 0

    public init(id: UUID = UUID(), serviceID: UUID = UUID(), name: String = "Standard",
                priceCents: Int64 = 0, sortOrder: Int = 0) {
        self.id = id
        self.serviceID = serviceID
        self.name = name
        self.priceCents = priceCents
        self.sortOrder = sortOrder
    }
}

public struct ServiceRateDraft: Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var priceCents: Int64

    public init(id: UUID = UUID(), name: String = "Standard", priceCents: Int64 = 0) {
        self.id = id
        self.name = name
        self.priceCents = priceCents
    }
}

public enum ServiceTariffs {
    public static func options(for service: TrainingService, rates: [ServiceRate]) -> [ServiceRateDraft] {
        let options = rates.filter { $0.serviceID == service.id }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }.map { ServiceRateDraft(id: $0.id, name: $0.name, priceCents: $0.priceCents) }
        return options.isEmpty
            ? [ServiceRateDraft(id: service.id, priceCents: service.priceCents)]
            : options
    }
}
