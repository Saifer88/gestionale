import Foundation
import PaolaCore

/// Determina l'ambiente dei servizi esterni in base al tipo di build.
/// Le build locali di sviluppo (PaolaLocalBuild=YES) usano gli ambienti demo;
/// le release usano gli ambienti di produzione.
enum AppEnvironment {
    static var isLocalBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PaolaLocalBuild") as? String) == "YES"
    }

    /// True se le chiamate ad Aruba devono usare l'ambiente demo.
    static var usesArubaDemo: Bool { isLocalBuild }
}
