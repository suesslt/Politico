import Fluent

struct DropMeetingSessionName: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("meeting")
            .deleteField("session_name")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("meeting")
            .field("session_name", .string)
            .update()
    }
}
