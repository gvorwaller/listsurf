import Foundation

public enum AppError: Error, Sendable {
    case persistenceSave(underlying: String)
    case persistenceLoad(underlying: String)
    case migrationFailed(from: Int, to: Int, reason: String)
    case importValidation(message: String)
    case importPartial(imported: Int, failed: Int, details: [String])
    case orphanRepair(repairedCount: Int, listTitle: String)
    case storeCorrupted(reason: String)
}
