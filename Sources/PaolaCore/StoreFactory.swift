import Foundation
import SwiftData

@MainActor
public enum StoreFactory {
    public static func makeContainer(
        url: URL? = nil,
        inMemory: Bool = false,
        cloudKitContainerIdentifier: String? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PaolaSchemaV5.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                "PaolaGestionale",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            let storeURL = try url ?? defaultStoreURL()
            guard storeURL.isFileURL else {
                throw CocoaError(.fileWriteUnsupportedScheme)
            }
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(
                "PaolaGestionale",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: cloudKitContainerIdentifier.map { .private($0) } ?? .none
            )
        }

        let container = try ModelContainer(
            for: schema,
            migrationPlan: PaolaSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        container.mainContext.autosaveEnabled = false
        return container
    }

    /// Creates the directory, not the store: Application Support/PaolaGestionale/Clienti-v1.store.
    public static func defaultStoreURL() throws -> URL {
        let directory = try applicationDirectory()
        return try selectedStoreURL(in: directory, relativePath: UserDefaults.standard.string(forKey: "storage.restoredStore"))
    }

    static func selectedStoreURL(in directory: URL, relativePath: String?) throws -> URL {
        if let relative = relativePath {
            guard relative.hasPrefix("Restored/"), !relative.contains(".."),
                  relative.hasSuffix("/Clienti-v1.store") else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let selected = directory.appendingPathComponent(relative)
            let base = directory.appendingPathComponent("Restored", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            guard selected.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(base.path + "/") else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            guard FileManager.default.fileExists(atPath: selected.path) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return selected
        }
        return directory.appendingPathComponent("Clienti-v1.store", isDirectory: false)
    }

    public static func applicationDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PaolaGestionale", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func activateRestoredStore(at url: URL) throws {
        let base = try applicationDirectory().appendingPathComponent("Restored", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        guard destination.path.hasPrefix(base.path + "/"), destination.lastPathComponent == "Clienti-v1.store",
              FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let relative = "Restored/" + destination.path.dropFirst(base.path.count + 1)
        UserDefaults.standard.set(relative, forKey: "storage.restoredStore")
    }
}
