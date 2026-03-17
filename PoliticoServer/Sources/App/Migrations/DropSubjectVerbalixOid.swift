import Fluent

struct DropSubjectVerbalixOid: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("subject")
            .deleteField("verbalix_oid")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("subject")
            .field("verbalix_oid", .int)
            .update()
    }
}
