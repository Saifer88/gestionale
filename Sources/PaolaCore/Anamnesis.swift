import Foundation

/// Scheda anamnesi del cliente (dato riservato). È salvata come JSON dentro il campo
/// testuale `Client.anamnesis`, quindi non richiede modifiche allo schema SwiftData né
/// migrazioni: aggiungere o togliere un campo qui non tocca il database.
///
/// Robustezza dei dati:
/// - Il contenuto è un dizionario chiave→valore (`values`). Ogni voce prevista ha una
///   chiave stabile (vedi `Field`). Le voci presenti nei dati ma non più previste dal
///   codice NON vengono perse: restano in `values` e sono esposte come "elementi non
///   più attivi" (`inactiveEntries`), così si conservano anche dopo un salvataggio.
/// - Un eventuale testo libero preesistente (non JSON) viene conservato come nota
///   legacy nella chiave `legacyNoteKey`.
public struct Anamnesis: Equatable, Identifiable {
    /// Chiavi stabili dei campi previsti. Non rinominare le esistenti (romperebbe il
    /// collegamento ai dati salvati); aggiungere in coda le nuove.
    public enum Field: String, CaseIterable {
        case height = "height"
        case reference = "reference"
        case currentWeight = "currentWeight"
        case weightChanges = "weightChanges"
        case sportsHistory = "sportsHistory"
        case activityStatus = "activityStatus"
        case stressLevel = "stressLevel"
        case smoking = "smoking"
        case work = "work"
        case sleepQuality = "sleepQuality"
        case sleepHours = "sleepHours"
        case controlledDiet = "controlledDiet"
        case dietDetails = "dietDetails"
        case eatingDisorders = "eatingDisorders"
        case waterIntake = "waterIntake"
        case boneJointIssues = "boneJointIssues"
        case muscleIssues = "muscleIssues"
        case cardioRespiratoryIssues = "cardioRespiratoryIssues"
        case incidents = "incidents"
        case exams = "exams"
        case pregnancies = "pregnancies"
        case pregnancyComplications = "pregnancyComplications"
        case anxietyPanic = "anxietyPanic"
        case chronicConditions = "chronicConditions"
        case longTermMedications = "longTermMedications"
        case substances = "substances"
        case motivation = "motivation"
        case weeklyFrequency = "weeklyFrequency"
        case trainingLevel = "trainingLevel"
        case circumferences = "circumferences"
        case physique = "physique"
        case tests = "tests"

        /// Etichetta mostrata nell'editor.
        public var label: String {
            switch self {
            case .height: return "Altezza"
            case .reference: return "Referenza"
            case .currentWeight: return "Peso attuale? Variazioni importanti (quali, quando, perché)"
            case .weightChanges: return "Dettaglio variazioni di peso"
            case .sportsHistory: return "Attività o sport praticati per almeno 2 anni"
            case .activityStatus: return "Sei attivo? Da quanto tempo sei fermo?"
            case .stressLevel: return "Sei stressato? Quanto (da 1 a 10)?"
            case .smoking: return "Fumi?"
            case .work: return "Lavoro sedentario? Quanto incide nella tua vita?"
            case .sleepQuality: return "Come dormi? (ti addormenti facilmente, ti svegli di notte e perché, ti svegli riposato)"
            case .sleepHours: return "Quante ore in media dormi?"
            case .controlledDiet: return "Segui un'alimentazione controllata?"
            case .dietDetails: return "Che tipo? Ne hai mai seguita una? Nome nutrizionista"
            case .eatingDisorders: return "Hai o hai mai avuto problemi alimentari?"
            case .waterIntake: return "Quanta acqua bevi al giorno?"
            case .boneJointIssues: return "Problemi (anche passati) a ossa o articolazioni?"
            case .muscleIssues: return "Problemi (anche passati) muscolari?"
            case .cardioRespiratoryIssues: return "Problemi cardio-respiratori o circolatori negli ultimi 12 mesi?"
            case .incidents: return "Incidenti, ricoveri, ospedalizzazioni da segnalare?"
            case .exams: return "Controlli effettuati (occlusione, baropodometrico)?"
            case .pregnancies: return "Gravidanze/parti? Intenzione di averne? Stai allattando?"
            case .pregnancyComplications: return "Ci sono state complicazioni?"
            case .anxietyPanic: return "Crisi d'ansia o attacchi di panico?"
            case .chronicConditions: return "Soffri di patologie croniche?"
            case .longTermMedications: return "Farmaci assunti per lungo periodo?"
            case .substances: return "Sostanze stupefacenti?"
            case .motivation: return "Motivazione che ti spinge ad allenarti"
            case .weeklyFrequency: return "Quante volte vuoi/puoi allenarti a settimana?"
            case .trainingLevel: return "Grado di allenamento"
            case .circumferences: return "Circonferenze"
            case .physique: return "Fisicità"
            case .tests: return "Test"
            }
        }

        /// Tipo di controllo da usare nell'editor.
        public enum Kind { case date, shortText, longText, integer, boolean }
        public var kind: Kind {
            switch self {
            case .height, .currentWeight, .waterIntake, .sleepHours, .stressLevel,
                 .weeklyFrequency: return .integer
            case .smoking, .controlledDiet, .eatingDisorders, .boneJointIssues, .muscleIssues,
                 .cardioRespiratoryIssues, .anxietyPanic, .chronicConditions: return .boolean
            case .reference, .activityStatus: return .shortText
            default: return .longText
            }
        }
    }

    /// Chiave della nota legacy (testo libero preesistente non strutturato).
    public static let legacyNoteKey = "_legacyNote"

    /// Identificativo stabile della versione.
    public var id: UUID
    /// Data della versione (quando è stata compilata questa anamnesi).
    public var date: Date
    /// Etichetta libera facoltativa della versione (es. "Prima visita").
    public var title: String
    /// Tutte le voci salvate (chiavi previste + eventuali chiavi sconosciute preservate).
    public private(set) var values: [String: String]

    public init(id: UUID = UUID(), date: Date = Date(), title: String = "",
                values: [String: String] = [:]) {
        self.id = id
        self.date = date
        self.title = title
        self.values = values
    }

    // MARK: - Accesso ai campi

    public func value(_ field: Field) -> String {
        values[field.rawValue] ?? ""
    }
    public mutating func set(_ field: Field, _ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { values[field.rawValue] = nil }
        else { values[field.rawValue] = trimmed }
    }

    public var legacyNote: String { values[Anamnesis.legacyNoteKey] ?? "" }

    /// True se non ci sono dati compilati.
    public var isEmpty: Bool { values.isEmpty }

    /// Voci presenti nei dati ma non più previste dal codice: si conservano e si mostrano
    /// come "elementi non più attivi". Esclude la nota legacy (gestita a parte).
    public var inactiveEntries: [(key: String, value: String)] {
        let known = Set(Field.allCases.map(\.rawValue) + [Anamnesis.legacyNoteKey])
        return values.filter { !known.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    /// Rappresentazione Codable di una versione (per l'array JSON).
    fileprivate struct Payload: Codable {
        var id: UUID
        var date: Date
        var title: String
        var values: [String: String]
    }

    fileprivate var payload: Payload { Payload(id: id, date: date, title: title, values: values) }
    fileprivate init(payload: Payload) {
        self.init(id: payload.id, date: payload.date, title: payload.title, values: payload.values)
    }
}

/// Storico versionato delle anamnesi di un cliente, salvato come array JSON nel campo
/// testuale `Client.anamnesis`. Consente di aggiungere nuove versioni conservando le
/// precedenti. Nessuna modifica allo schema SwiftData.
public struct AnamnesisHistory: Equatable {
    /// Versioni ordinate dalla più recente alla più vecchia.
    public private(set) var versions: [Anamnesis]

    public init(versions: [Anamnesis] = []) {
        self.versions = versions.sorted { $0.date > $1.date }
    }

    /// Versione corrente (la più recente), se presente.
    public var current: Anamnesis? { versions.first }
    public var isEmpty: Bool { versions.isEmpty }

    /// Inserisce o aggiorna una versione (per id) e riordina per data decrescente.
    public mutating func upsert(_ version: Anamnesis) {
        if let index = versions.firstIndex(where: { $0.id == version.id }) {
            versions[index] = version
        } else {
            versions.append(version)
        }
        versions.sort { $0.date > $1.date }
    }

    /// Rimuove una versione per id.
    public mutating func remove(_ id: UUID) {
        versions.removeAll { $0.id == id }
    }

    // MARK: - Serializzazione da/verso il campo String del Client

    /// Legge lo storico dal campo `Client.anamnesis`. Gestisce tre formati, senza perdere dati:
    /// - array JSON di versioni (formato nuovo);
    /// - oggetto JSON singolo `[String:String]` (formato precedente, non versionato) → una versione;
    /// - testo libero non JSON → una versione con nota legacy.
    public static func parse(_ raw: String) -> AnamnesisHistory {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return AnamnesisHistory()
        }
        let decoder = JSONDecoder()
        // Formato nuovo: array di versioni.
        if let payloads = try? decoder.decode([Anamnesis.Payload].self, from: data) {
            return AnamnesisHistory(versions: payloads.map(Anamnesis.init(payload:)))
        }
        // Formato precedente: oggetto singolo chiave→valore.
        if let dict = try? decoder.decode([String: String].self, from: data) {
            return AnamnesisHistory(versions: [Anamnesis(values: dict)])
        }
        // Testo libero: nota legacy.
        return AnamnesisHistory(versions: [Anamnesis(values: [Anamnesis.legacyNoteKey: trimmed])])
    }

    /// Serializza in JSON (array di versioni) per il campo `Client.anamnesis`. Vuoto → "".
    public func serialized() -> String {
        let nonEmpty = versions.filter { !$0.values.isEmpty }
        guard !nonEmpty.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(nonEmpty.map(\.payload)),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }
}
