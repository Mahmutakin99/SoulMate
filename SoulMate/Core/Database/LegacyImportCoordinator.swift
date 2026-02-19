import Foundation

final class LegacyImportCoordinator {
    static let shared = LegacyImportCoordinator()

    private let queue = DispatchQueue(label: "com.soulmate.database.legacyimport", qos: .utility)
    private var isRunning = false

    private init() {}

    func scheduleIfNeeded(database: AppDatabase) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunning else { return }
            guard !self.isImportCompleted else { return }

            self.isRunning = true
            defer { self.isRunning = false }

            do {
                try database.runLegacyImportIfNeeded()
                self.isImportCompleted = true
                #if DEBUG
                print("Legacy mesaj import kontrolü tamamlandı.")
                #endif
            } catch {
                #if DEBUG
                print("Legacy mesaj importu ertelendi: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private var isImportCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: importCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: importCompletedKey) }
    }

    private var importCompletedKey: String {
        "db.legacy_import_completed.v1"
    }
}
