import Fluent
import Vapor

final class SyncStatus: Model, Content, @unchecked Sendable {
    static let schema = "sync_status"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "entity_name")
    var entityName: String

    @Field(key: "session_id")
    var sessionID: Int?

    @Field(key: "last_sync_at")
    var lastSyncAt: Date?

    @Field(key: "status")
    var status: String

    @Field(key: "items_synced")
    var itemsSynced: Int

    @Field(key: "error_message")
    var errorMessage: String?

    init() {}

    init(entityName: String, sessionID: Int? = nil, status: String = "pending", itemsSynced: Int = 0) {
        self.entityName = entityName
        self.sessionID = sessionID
        self.status = status
        self.itemsSynced = itemsSynced
    }
}
