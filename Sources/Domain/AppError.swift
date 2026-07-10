import Foundation

public enum AppError: Error, Sendable {
    case persistenceSave(underlying: String)
    case persistenceLoad(underlying: String)
    case migrationFailed(from: Int, to: Int, reason: String)
    case importValidation(message: String)
    case backupExportFailed(message: String)
    case orphanRepair(repairedCount: Int, listTitle: String)
    case storeCorrupted(reason: String)
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .persistenceSave:
            "Changes Could Not Be Saved"
        case .persistenceLoad:
            "Data Could Not Be Loaded"
        case .migrationFailed:
            "Database Upgrade Failed"
        case .importValidation:
            "Import Could Not Be Validated"
        case .backupExportFailed:
            "Backup Could Not Be Exported"
        case .orphanRepair:
            "Some Items Were Reorganized"
        case .storeCorrupted:
            "The Database Could Not Be Opened"
        }
    }

    public var failureReason: String? {
        switch self {
        case .persistenceSave(let underlying),
             .persistenceLoad(let underlying):
            underlying
        case .migrationFailed(let from, let to, let reason):
            "Migration from version \(from) to \(to) failed: \(reason)"
        case .importValidation(let message):
            message
        case .backupExportFailed(let message):
            message
        case .orphanRepair(let repairedCount, let listTitle):
            "\(repairedCount) items in “\(listTitle)” were moved to the root because their parent links were invalid."
        case .storeCorrupted(let reason):
            reason
        }
    }
}
